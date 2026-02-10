export class FtpLogger {
  private logLevel: 'debug' | 'info' | 'warn' | 'error' = 'info';

  setLogLevel(level: 'debug' | 'info' | 'warn' | 'error'): void {
    this.logLevel = level;
  }

  debug(message: string): void {
    if (this.logLevel === 'debug') {
      console.debug(`[FTP DEBUG] ${new Date().toISOString()} - ${message}`);
    }
  }

  info(message: string): void {
    if (['debug', 'info'].includes(this.logLevel)) {
      console.info(`[FTP INFO] ${new Date().toISOString()} - ${message}`);
    }
  }

  warn(message: string): void {
    if (['debug', 'info', 'warn'].includes(this.logLevel)) {
      console.warn(`[FTP WARN] ${new Date().toISOString()} - ${message}`);
    }
  }

  error(message: string): void {
    console.error(`[FTP ERROR] ${new Date().toISOString()} - ${message}`);
  }
}