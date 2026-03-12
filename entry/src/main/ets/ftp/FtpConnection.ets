import socket from '@ohos.net.socket';
import util from '@ohos.util';
import { FtpConfig } from './FtpConfig';
import { FtpLogger } from './FtpLogger';
import { FtpCommandHandler } from './FtpCommandHandler';
import { EventEmitter } from './EventEmitter';

export type DataServer = socket.TCPSocketServer;

export class FtpConnection extends EventEmitter {
  private clientSocket: socket.TCPSocketConnection;
  private config: FtpConfig;
  private logger: FtpLogger;
  private commandHandler: FtpCommandHandler;
  private isAuthenticated: boolean = false;
  private currentUser: string = '';
  private currentDirectory: string = '/';
  private isActive: boolean = true;
  private transferType: string = 'A'; // A=ASCII, I=Binary

  // 被动模式数据连接
  private dataServer: DataServer | null = null;
  private dataSocket: socket.TCPSocketConnection | null = null;
  private dataPort: number = 0;
  private static nextPassivePort: number = 50000;

  // 断点续传偏移
  private restOffset: number = 0;

  // 重命名源路径
  private renameFrom: string = '';

  // UTF-8 编解码
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private textEncoder: util.TextEncoder = new util.TextEncoder();

  constructor(clientSocket: socket.TCPSocketConnection, config: FtpConfig, logger: FtpLogger) {
    super();
    this.clientSocket = clientSocket;
    this.config = config;
    this.logger = logger;
    this.commandHandler = new FtpCommandHandler(this);
  }

  start(): void {
    try {
      this.sendResponse(220, 'HarmonyOS FTP Server ready');

      this.clientSocket.on('message', async (info: socket.SocketMessageInfo) => {
        await this.handleData(info.message);
      });

      this.clientSocket.on('error', (error: Error) => {
        this.logger.error(`Connection error: ${error.message}`);
        this.close();
      });

      this.clientSocket.on('close', () => {
        this.logger.info('Client disconnected');
        this.close();
      });
    } catch (error) {
      this.logger.error(`Error starting connection: ${error}`);
      this.close();
    }
  }

  private async handleData(data: ArrayBuffer): Promise<void> {
    try {
      const text = this.textDecoder.decodeWithStream(new Uint8Array(data));
      // FTP 可能一次收到多条命令（以 \r\n 分隔）
      const lines = text.split('\r\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.length > 0) {
          this.logger.debug(`<< ${trimmed}`);
          await this.commandHandler.handleCommand(trimmed);
        }
      }
    } catch (error) {
      this.logger.error(`Error handling data: ${error}`);
      this.sendResponse(500, 'Internal server error');
    }
  }

  sendResponse(code: number, message: string): void {
    try {
      const response = `${code} ${message}\r\n`;
      this.logger.debug(`>> ${response.trim()}`);
      const encoded = this.textEncoder.encodeInto(response);
      this.clientSocket.send({ data: encoded.buffer });
    } catch (error) {
      this.logger.error(`Error sending response: ${error}`);
    }
  }

  // 多行响应的中间行：格式 "code-text"
  sendMultiLineBegin(code: number, message: string): void {
    try {
      const encoded = this.textEncoder.encodeInto(`${code}-${message}\r\n`);
      this.clientSocket.send({ data: encoded.buffer });
    } catch (error) {
      this.logger.error(`Error sending multi-line begin: ${error}`);
    }
  }

  // 多行响应的特性行：以空格开头
  sendMultiLineLine(message: string): void {
    try {
      const encoded = this.textEncoder.encodeInto(` ${message}\r\n`);
      this.clientSocket.send({ data: encoded.buffer });
    } catch (error) {
      this.logger.error(`Error sending multi-line: ${error}`);
    }
  }

  // 多行响应的结束行：格式 "code text"
  sendMultiLineEnd(code: number, message: string): void {
    this.sendResponse(code, message);
  }

  async sendData(data: string | ArrayBuffer): Promise<void> {
    if (!this.dataSocket) {
      throw new Error('No data connection');
    }
    if (typeof data === 'string') {
      const encoded = this.textEncoder.encodeInto(data);
      await this.dataSocket.send({ data: encoded.buffer });
    } else {
      await this.dataSocket.send({ data });
    }
  }

  // 打开被动模式数据监听
  async openPassiveDataServer(): Promise<number> {
    await this.closeDataConnection();

    this.dataServer = socket.constructTCPSocketServerInstance();

    // 端口分配
    FtpConnection.nextPassivePort++;
    if (FtpConnection.nextPassivePort > this.config.passivePortMax) {
      FtpConnection.nextPassivePort = this.config.passivePortMin;
    }
    this.dataPort = FtpConnection.nextPassivePort;

    // 设置连接回调
    this.dataServer.on('connect', (conn: socket.TCPSocketConnection) => {
      this.dataSocket = conn;
    });

    const addr: socket.NetAddress = { address: '0.0.0.0', port: this.dataPort };
    await this.dataServer.listen(addr);
    this.logger.debug(`Passive data server on port ${this.dataPort}`);
    return this.dataPort;
  }

  // 等待客户端连接到被动数据端口
  async waitForDataConnection(timeoutMs: number = 30000): Promise<boolean> {
    const start = Date.now();
    while (!this.dataSocket) {
      if (Date.now() - start > timeoutMs) {
        this.logger.error('Data connection timeout');
        return false;
      }
      await new Promise<void>(resolve => setTimeout(resolve, 50));
    }
    return true;
  }

  // 从数据连接读取所有数据（用于 STOR/APPE）
  async readAllDataFromSocket(): Promise<ArrayBuffer> {
    if (!this.dataSocket) throw new Error('No data connection');
    const ds = this.dataSocket;

    return new Promise<ArrayBuffer>((resolve, reject) => {
      const chunks: ArrayBuffer[] = [];
      let totalSize = 0;

      const timer = setTimeout(() => {
        if (chunks.length > 0) {
          resolve(this.mergeBuffers(chunks, totalSize));
        } else {
          reject(new Error('Data receive timeout'));
        }
      }, 30000);

      ds.on('message', (info: socket.SocketMessageInfo) => {
        if (info.message && info.message.byteLength > 0) {
          chunks.push(info.message);
          totalSize += info.message.byteLength;
        }
      });

      ds.on('close', () => {
        clearTimeout(timer);
        resolve(this.mergeBuffers(chunks, totalSize));
      });

      ds.on('error', (err: Error) => {
        clearTimeout(timer);
        reject(err);
      });
    });
  }

  private mergeBuffers(chunks: ArrayBuffer[], totalSize: number): ArrayBuffer {
    if (totalSize === 0) return new ArrayBuffer(0);
    const result = new ArrayBuffer(totalSize);
    const view = new Uint8Array(result);
    let offset = 0;
    for (const chunk of chunks) {
      view.set(new Uint8Array(chunk), offset);
      offset += chunk.byteLength;
    }
    return result;
  }

  async closeDataConnection(): Promise<void> {
    if (this.dataSocket) {
      try { await this.dataSocket.close(); } catch (e) { /* ignore */ }
      this.dataSocket = null;
    }
    if (this.dataServer) {
      try { await this.dataServer.close(); } catch (e) { /* ignore */ }
      this.dataServer = null;
    }
  }

  async close(): Promise<void> {
    if (!this.isActive) return;
    this.isActive = false;
    await this.closeDataConnection();
    try { await this.clientSocket.close(); } catch (e) { /* ignore */ }
    this.emit('close');
  }

  // Getters / Setters
  getConfig(): FtpConfig { return this.config; }
  getLogger(): FtpLogger { return this.logger; }
  getDataPort(): number { return this.dataPort; }

  isUserAuthenticated(): boolean { return this.isAuthenticated; }
  setAuthenticated(v: boolean): void { this.isAuthenticated = v; }

  getCurrentUser(): string { return this.currentUser; }
  setCurrentUser(u: string): void { this.currentUser = u; }

  getCurrentDirectory(): string { return this.currentDirectory; }
  setCurrentDirectory(d: string): void { this.currentDirectory = d; }

  getTransferType(): string { return this.transferType; }
  setTransferType(t: string): void { this.transferType = t; }

  getRestOffset(): number { return this.restOffset; }
  setRestOffset(o: number): void { this.restOffset = o; }

  getRenameFrom(): string { return this.renameFrom; }
  setRenameFrom(p: string): void { this.renameFrom = p; }

  isConnectionActive(): boolean { return this.isActive; }
}
