import socket from '@ohos.net.socket';
import { FtpConnection, Address, DataServer } from './FtpConnection';
import { FtpConfig } from './FtpConfig';
import { FtpLogger } from './FtpLogger';

export interface ServerStatus {
  isRunning: boolean;
  port: number;
  connectionCount: number;
}

export class FtpServer {
  private serverSocket: DataServer | null = null;
  private connections: FtpConnection[] = [];
  private config: FtpConfig;
  private logger: FtpLogger;
  private isRunning: boolean = false;

  constructor(config: FtpConfig) {
    this.config = config;
    this.logger = new FtpLogger();
  }

  async start(): Promise<boolean> {
    try {
      this.serverSocket = socket.constructTCPSocketServerInstance();
      
      if (this.serverSocket) {
        this.serverSocket.on('connect', (data: socket.TCPSocketConnection) => {
          this.handleNewConnection(data);
        });

        this.serverSocket.on('error', (error: Error) => {
          this.logger.error(`Server error: ${error.message}`);
        });

        const address: socket.NetAddress = {
          address: '0.0.0.0',
          port: this.config.port
        };
        await this.serverSocket.listen(address);
        
        this.isRunning = true;
        this.logger.info(`FTP Server started on port ${this.config.port}`);
        return true;
      } else {
        this.logger.error('Failed to create server socket');
        return false;
      }
    } catch (error) {
      this.logger.error(`Failed to start server: ${error}`);
      this.isRunning = false;
      return false;
    }
  }

  private handleNewConnection(clientSocket: socket.TCPSocketConnection) {
    try {
      this.logger.info('New client connection received');
      const connection = new FtpConnection(clientSocket, this.config, this.logger);
      this.connections.push(connection);
      
      connection.on('close', () => {
        this.connections = this.connections.filter(conn => conn !== connection);
        this.logger.info(`Client connection closed. Current connections: ${this.connections.length}`);
      });

      connection.start();
    } catch (error) {
      this.logger.error(`Error handling new connection: ${error}`);
      try {
        clientSocket.close();
      } catch (closeError) {
        // Ignore close error
      }
    }
  }

  async stop(): Promise<void> {
    if (!this.isRunning) {
      this.logger.warn('Attempting to stop server that is not running');
      return;
    }

    this.isRunning = false;
    this.logger.info('Stopping FTP Server...');

    // Close all connections
    this.logger.info(`Closing ${this.connections.length} active connections`);
    for (let i = 0; i < this.connections.length; i++) {
      const connection = this.connections[i];
      try {
        await connection.close();
      } catch (error) {
        this.logger.error(`Error closing connection: ${error}`);
      }
    }
    this.connections = [];

    // Close server socket
    if (this.serverSocket) {
      try {
        await this.serverSocket.close();
        this.serverSocket = null;
        this.logger.info('Server socket closed');
      } catch (error) {
        this.logger.error(`Error closing server socket: ${error}`);
      }
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