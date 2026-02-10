import { FtpServer, ServerStatus } from './FtpServer';
import { FtpConfig } from './FtpConfig';
import { FtpLogger } from './FtpLogger';

export class FtpServerManager {
  private static instance: FtpServerManager;
  private server: FtpServer | null = null;
  private config: FtpConfig;
  private logger: FtpLogger;

  private constructor() {
    this.config = new FtpConfig();
    this.logger = new FtpLogger();
  }

  public static getInstance(): FtpServerManager {
    if (!FtpServerManager.instance) {
      FtpServerManager.instance = new FtpServerManager();
    }
    return FtpServerManager.instance;
  }

  // 启动FTP服务器
  async startServer(config?: Partial<FtpConfig>): Promise<boolean> {
    try {
      // 如果服务器已经在运行，先停止
      if (this.server) {
        await this.stopServer();
      }

      // 更新配置
      if (config) {
        this.config = new FtpConfig({
          port: config.port || this.config.port,
          rootDirectory: config.rootDirectory || this.config.rootDirectory,
          maxConnections: config.maxConnections || this.config.maxConnections,
          user: config.user || this.config.user,
          password: config.password || this.config.password,
          allowAnonymous: config.allowAnonymous !== undefined ? config.allowAnonymous : this.config.allowAnonymous
        });
      }

      // 创建并启动服务器
      this.server = new FtpServer(this.config);
      const result = await this.server.start();
      
      if (result) {
        this.logger.info('FTP Server started successfully');
      } else {
        this.logger.error('Failed to start FTP Server');
      }
      
      return result;
    } catch (error) {
      this.logger.error(`Error starting FTP Server: ${error}`);
      return false;
    }
  }

  // 停止FTP服务器
  async stopServer(): Promise<void> {
    try {
      if (this.server) {
        await this.server.stop();
        this.server = null;
        this.logger.info('FTP Server stopped successfully');
      }
    } catch (error) {
      this.logger.error(`Error stopping FTP Server: ${error}`);
    }
  }

  // 重启FTP服务器
  async restartServer(): Promise<boolean> {
    await this.stopServer();
    return await this.startServer();
  }

  // 获取服务器状态
  getServerStatus(): ServerStatus {
    if (this.server) {
      return this.server.getStatus();
    }
    return {
      isRunning: false,
      port: this.config.port,
      connectionCount: 0
    };
  }

  // 获取当前配置
  getConfig(): FtpConfig {
    return this.config;
  }

  // 更新配置
  updateConfig(configUpdate: Partial<FtpConfig>): void {
    this.config = new FtpConfig({
      port: configUpdate.port || this.config.port,
      rootDirectory: configUpdate.rootDirectory || this.config.rootDirectory,
      maxConnections: configUpdate.maxConnections || this.config.maxConnections,
      user: configUpdate.user || this.config.user,
      password: configUpdate.password || this.config.password,
      allowAnonymous: configUpdate.allowAnonymous !== undefined ? configUpdate.allowAnonymous : this.config.allowAnonymous
    });
  }

  // 设置日志级别
  setLogLevel(logLevel: 'debug' | 'info' | 'warn' | 'error'): void {
    this.logger.setLogLevel(logLevel);
  }
}