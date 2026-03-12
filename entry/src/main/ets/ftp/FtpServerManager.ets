import { FtpServer, ServerStatus } from './FtpServer';
import { FtpConfig, FtpConfigOptions } from './FtpConfig';
import { FtpLogger, LogCallback } from './FtpLogger';

export class FtpServerManager {
  private static instance: FtpServerManager;
  private server: FtpServer | null = null;
  private config: FtpConfig;
  private logger: FtpLogger;

  private constructor() {
    this.config = new FtpConfig();
    this.logger = new FtpLogger();
  }

  static getInstance(): FtpServerManager {
    if (!FtpServerManager.instance) {
      FtpServerManager.instance = new FtpServerManager();
    }
    return FtpServerManager.instance;
  }

  async startServer(options?: FtpConfigOptions): Promise<boolean> {
    if (this.server) {
      await this.stopServer();
    }
    if (options) {
      this.config = new FtpConfig(options);
    }
    this.server = new FtpServer(this.config, this.logger);
    const ok = await this.server.start();
    if (!ok) this.server = null;
    return ok;
  }

  async stopServer(): Promise<void> {
    if (this.server) {
      await this.server.stop();
      this.server = null;
    }
  }

  getServerStatus(): ServerStatus {
    if (this.server) return this.server.getStatus();
    return { isRunning: false, port: this.config.port, connectionCount: 0 };
  }

  getConfig(): FtpConfig {
    return this.config;
  }

  setLogLevel(level: 'debug' | 'info' | 'warn' | 'error'): void {
    this.logger.setLogLevel(level);
  }

  setLogCallback(cb: LogCallback | null): void {
    this.logger.setCallback(cb);
  }
}
