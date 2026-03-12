import socket from '@ohos.net.socket';
import { FtpConnection } from './FtpConnection';
import { FtpConfig } from './FtpConfig';
import { FtpLogger } from './FtpLogger';

export interface ServerStatus {
  isRunning: boolean;
  port: number;
  connectionCount: number;
}

export class FtpServer {
  private serverSocket: socket.TCPSocketServer | null = null;
  private connections: FtpConnection[] = [];
  private config: FtpConfig;
  private logger: FtpLogger;
  private isRunning: boolean = false;

  constructor(config: FtpConfig, logger: FtpLogger) {
    this.config = config;
    this.logger = logger;
  }

  async start(): Promise<boolean> {
    try {
      this.serverSocket = socket.constructTCPSocketServerInstance();

      this.serverSocket.on('connect', (conn: socket.TCPSocketConnection) => {
        this.handleNewConnection(conn);
      });

      this.serverSocket.on('error', (error: Error) => {
        this.logger.error(`Server error: ${error.message}`);
      });

      const addr: socket.NetAddress = { address: '0.0.0.0', port: this.config.port };
      await this.serverSocket.listen(addr);

      this.isRunning = true;
      this.logger.info(`FTP Server started on port ${this.config.port}`);
      return true;
    } catch (error) {
      this.logger.error(`Failed to start: ${error}`);
      this.isRunning = false;
      return false;
    }
  }

  private handleNewConnection(clientSocket: socket.TCPSocketConnection): void {
    if (this.connections.length >= this.config.maxConnections) {
      this.logger.warn('Max connections reached, rejecting');
      try { clientSocket.close(); } catch (e) { /* ignore */ }
      return;
    }

    this.logger.info(`New connection (total: ${this.connections.length + 1})`);
    const conn = new FtpConnection(clientSocket, this.config, this.logger);
    this.connections.push(conn);

    conn.on('close', () => {
      this.connections = this.connections.filter(c => c !== conn);
      this.logger.info(`Connection closed (remaining: ${this.connections.length})`);
    });

    conn.start();
  }

  async stop(): Promise<void> {
    if (!this.isRunning) return;
    this.isRunning = false;

    for (const conn of this.connections) {
      try { await conn.close(); } catch (e) { /* ignore */ }
    }
    this.connections = [];

    if (this.serverSocket) {
      try { await this.serverSocket.close(); } catch (e) { /* ignore */ }
      this.serverSocket = null;
    }

    this.logger.info('FTP Server stopped');
  }

  getStatus(): ServerStatus {
    return {
      isRunning: this.isRunning,
      port: this.config.port,
      connectionCount: this.connections.length
    };
  }
}
