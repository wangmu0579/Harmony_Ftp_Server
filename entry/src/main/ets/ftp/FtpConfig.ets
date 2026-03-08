// 配置接口
export interface FtpConfigOptions {
  port?: number;
  rootDirectory?: string;
  maxConnections?: number;
  user?: string;
  password?: string;
  allowAnonymous?: boolean;
  serverIp?: string;
}

export class FtpConfig {
  readonly port: number;
  readonly rootDirectory: string;
  readonly maxConnections: number;
  readonly user: string;
  readonly password: string;
  readonly allowAnonymous: boolean;
  readonly serverIp: string;

  constructor(options: FtpConfigOptions = {}) {
    this.port = options.port || 2121;
    this.rootDirectory = options.rootDirectory || '/';
    this.maxConnections = options.maxConnections || 10;
    this.user = options.user || 'anonymous';
    this.password = options.password || '';
    this.allowAnonymous = options.allowAnonymous !== undefined ? options.allowAnonymous : true;
    this.serverIp = options.serverIp || '127.0.0.1';
  }

  // 验证用户凭据
  validateCredentials(user: string, password: string): boolean {
    if (this.allowAnonymous && user === 'anonymous') {
      return true;
    }
    return user === this.user && password === this.password;
  }
}