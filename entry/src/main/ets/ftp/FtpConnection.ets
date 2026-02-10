import socket from '@ohos.net.socket';
import { FtpConfig } from './FtpConfig';
import { FtpLogger } from './FtpLogger';
import { FtpCommandHandler } from './FtpCommandHandler';
import { EventEmitter } from './EventEmitter';

// 定义接口
export interface Address {
  port: number;
}

export interface ServerAddress {
  port: number;
}

// 定义数据服务器类型
export type DataServer = socket.TCPSocketServer;

export class FtpConnection extends EventEmitter {
  private clientSocket: socket.TCPSocketConnection;
  private dataSocket: socket.TCPSocketConnection | null = null;
  private config: FtpConfig;
  private logger: FtpLogger;
  private commandHandler: FtpCommandHandler;
  private isAuthenticated: boolean = false;
  private currentUser: string = '';
  private currentDirectory: string = '/';
  private isActive: boolean = true;

  constructor(clientSocket: socket.TCPSocketConnection, config: FtpConfig, logger: FtpLogger) {
    super();
    this.clientSocket = clientSocket;
    this.config = config;
    this.logger = logger;
    this.commandHandler = new FtpCommandHandler(this);
  }

  start(): void {
    try {
      this.sendResponse(220, 'FTP Server ready');
      this.logger.info('FTP Server ready for commands');
      
      this.clientSocket.on('message', async (messageInfo: socket.SocketMessageInfo) => {
        await this.handleData(messageInfo.message);
      });

      this.clientSocket.on('error', (error: Error) => {
        this.logger.error(`Connection error: ${error.message}`);
        this.close();
      });

      this.clientSocket.on('close', () => {
        this.logger.info('Client connection closed');
        this.close();
      });
    } catch (error) {
      this.logger.error(`Error starting connection handling: ${error}`);
      this.close();
    }
  }

  private async handleData(data: ArrayBuffer): Promise<void> {
    try {
      const uint8Array = new Uint8Array(data);
      let command = '';
      for (let i = 0; i < uint8Array.length; i++) {
        command += String.fromCharCode(uint8Array[i]);
      }
      command = command.trim();
      this.logger.debug(`Received command: ${command}`);
      await this.commandHandler.handleCommand(command);
    } catch (error) {
      this.logger.error(`Error handling command data: ${error}`);
      this.sendResponse(500, 'Internal server error');
    }
  }

  sendResponse(code: number, message: string): void {
    try {
      const response = `${code} ${message}\r\n`;
      this.logger.debug(`Sending response: ${response.trim()}`);
      this.clientSocket.send({ data: response });
    } catch (error) {
      this.logger.error(`Error sending response: ${error}`);
      // If we can't send a response, the connection is probably broken
      this.close();
    }
  }

  private dataPort: number = 0;
  private dataServer: DataServer | null = null;
  private activeModeAddress: string = '';
  private activeModePort: number = 0;

  async openDataConnection(): Promise<socket.TCPSocketConnection | null> {
    try {
      // 这里实现被动模式的数据连接
      this.dataServer = socket.constructTCPSocketServerInstance();
      
      return new Promise<socket.TCPSocketConnection | null>((resolve) => {
        if (this.dataServer) {
          this.dataServer.on('connect', (data: socket.TCPSocketConnection) => {
            this.dataSocket = data;
            resolve(data);
          });

          this.dataServer.on('error', (error: Error) => {
            this.logger.error(`Data server error: ${error.message}`);
            resolve(null);
          });

          // 绑定到一个随机端口
          const address: socket.NetAddress = {
            address: '',
            port: 0
          };
          this.dataServer.listen(address).then(() => {
            this.logger.debug(`Data server started`);
          }).catch((error: Error) => {
            this.logger.error(`Failed to start data server: ${error.message}`);
            resolve(null);
          });
        } else {
          resolve(null);
        }
      });
    } catch (error) {
      this.logger.error(`Failed to open data connection: ${error}`);
      return null;
    }
  }

  setActiveModeAddress(address: string, port: number): void {
    this.activeModeAddress = address;
    this.activeModePort = port;
  }

  getPassiveModePort(): number {
    return this.dataPort;
  }

  async closeDataServer(): Promise<void> {
    if (this.dataServer) {
      try {
        await this.dataServer.close();
      } catch (error) {
        this.logger.error(`Error closing data server: ${error}`);
      }
      this.dataServer = null;
    }
  }

  async closeDataConnection(): Promise<void> {
    if (this.dataSocket) {
      try {
        await this.dataSocket.close();
      } catch (error) {
        this.logger.error(`Error closing data socket: ${error}`);
      }
      this.dataSocket = null;
    }
    await this.closeDataServer();
  }

  async close(): Promise<void> {
    if (!this.isActive) {
      this.logger.debug('Attempting to close already closed connection');
      return;
    }

    this.isActive = false;
    this.logger.info('Closing FTP connection...');

    // Close data connection first
    try {
      await this.closeDataConnection();
    } catch (error) {
      this.logger.error(`Error closing data connection: ${error}`);
    }
    
    // Close control connection
    try {
      await this.clientSocket.close();
      this.logger.info('Control connection closed');
    } catch (error) {
      this.logger.error(`Error closing control connection: ${error}`);
    }

    this.emit('close');
    this.logger.info('FTP connection closed completely');
  }

  // Getters and setters
  getConfig(): FtpConfig {
    return this.config;
  }

  getLogger(): FtpLogger {
    return this.logger;
  }

  isUserAuthenticated(): boolean {
    return this.isAuthenticated;
  }

  setAuthenticated(authenticated: boolean): void {
    this.isAuthenticated = authenticated;
  }

  setCurrentUser(user: string): void {
    this.currentUser = user;
  }

  getCurrentUser(): string {
    return this.currentUser;
  }

  getCurrentDirectory(): string {
    return this.currentDirectory;
  }

  setCurrentDirectory(directory: string): void {
    this.currentDirectory = directory;
  }

  isConnectionActive(): boolean {
    return this.isActive;
  }
}