export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export type LogCallback = (level: LogLevel, message: string) => void;

export class FtpLogger {
  private logLevel: LogLevel = 'debug';
  private callback: LogCallback | null = null;

  setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }

  setCallback(cb: LogCallback | null): void {
    this.callback = cb;
  }

  debug(message: string): void {
    if (this.logLevel === 'debug') {
      console.debug(`[FTP DEBUG] ${message}`);
      this.callback?.('debug', message);
    }
  }

  info(message: string): void {
    if (['debug', 'info'].includes(this.logLevel)) {
      console.info(`[FTP INFO] ${message}`);
      this.callback?.('info', message);
    }
  }

  warn(message: string): void {
    if (['debug', 'info', 'warn'].includes(this.logLevel)) {
      console.warn(`[FTP WARN] ${message}`);
      this.callback?.('warn', message);
    }
  }

  error(message: string): void {
    console.error(`[FTP ERROR] ${message}`);
    this.callback?.('error', message);
  }
}
