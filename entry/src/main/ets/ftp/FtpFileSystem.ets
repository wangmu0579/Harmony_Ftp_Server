import fs from '@ohos.file.fs';
import { FtpConnection } from './FtpConnection';

export interface FileEntry {
  name: string;
  path: string;
}

export interface FileInfo {
  name: string;
  size: number;
  modifiedTime: Date;
  type: 'file' | 'directory';
}

export class FtpFileSystem {
  private connection: FtpConnection;
  private rootPath: string;

  constructor(connection: FtpConnection) {
    this.connection = connection;
    const config = connection.getConfig();
    this.rootPath = config.rootDirectory;
    if (!this.rootPath || this.rootPath === '/') {
      try {
        this.rootPath = getContext().filesDir;
      } catch (e) {
        this.rootPath = '/';
      }
    }
  }

  // 将 FTP 虚拟路径解析为真实文件系统路径
  resolvePath(ftpPath: string): string {
    if (!ftpPath || ftpPath === '/') {
      return this.rootPath;
    }
    // 绝对路径
    if (ftpPath.startsWith('/')) {
      const normalized = this.normalizePath(ftpPath);
      if (normalized === '/') return this.rootPath;
      return `${this.rootPath}${normalized}`;
    }
    // 相对路径：基于当前目录
    const cwd = this.connection.getCurrentDirectory();
    const combined = cwd === '/' ? `/${ftpPath}` : `${cwd}/${ftpPath}`;
    const normalized = this.normalizePath(combined);
    if (normalized === '/') return this.rootPath;
    return `${this.rootPath}${normalized}`;
  }

  // 规范化路径，处理 . 和 .. ，防止路径穿越
  private normalizePath(path: string): string {
    const parts = path.split('/');
    const stack: string[] = [];
    for (const part of parts) {
      if (part === '' || part === '.') continue;
      if (part === '..') {
        if (stack.length > 0) stack.pop();
      } else {
        stack.push(part);
      }
    }
    return '/' + stack.join('/');
  }

  async listFiles(ftpPath: string): Promise<string> {
    const fullPath = this.resolvePath(ftpPath);
    const entries = await this.getFilesInDirectory(fullPath);
    let result = '';
    for (const entry of entries) {
      const info = await this.getFileInfo(entry);
      const perm = info.type === 'directory' ? 'drwxr-xr-x' : '-rw-r--r--';
      const dateStr = this.formatListDate(info.modifiedTime);
      const sizeStr = info.size.toString().padStart(13, ' ');
      result += `${perm}   1 ftp      ftp      ${sizeStr} ${dateStr} ${info.name}\r\n`;
    }
    return result;
  }

  async listFileNames(ftpPath: string): Promise<string> {
    const fullPath = this.resolvePath(ftpPath);
    const entries = await this.getFilesInDirectory(fullPath);
    return entries.map(e => e.name).join('\r\n') + '\r\n';
  }

  async getFilesInDirectory(realPath: string): Promise<FileEntry[]> {
    try {
      const names: string[] = await fs.listFile(realPath);
      const result: FileEntry[] = [];
      for (const name of names) {
        const entry: FileEntry = { name: name, path: `${realPath}/${name}` };
        result.push(entry);
      }
      return result;
    } catch (error) {
      console.error('[FTP] listFile error:', error);
      return [];
    }
  }

  async getFileInfo(file: FileEntry): Promise<FileInfo> {
    try {
      const stat = await fs.stat(file.path);
      return {
        name: file.name,
        size: stat.size,
        modifiedTime: new Date(stat.mtime * 1000),
        type: stat.isDirectory() ? 'directory' : 'file'
      };
    } catch (error) {
      return { name: file.name, size: 0, modifiedTime: new Date(), type: 'file' };
    }
  }

  async getFileSize(ftpPath: string): Promise<number> {
    const fullPath = this.resolvePath(ftpPath);
    const stat = await fs.stat(fullPath);
    return stat.size;
  }

  async getModifiedTime(ftpPath: string): Promise<Date> {
    const fullPath = this.resolvePath(ftpPath);
    const stat = await fs.stat(fullPath);
    return new Date(stat.mtime * 1000);
  }

  async readFile(ftpPath: string): Promise<ArrayBuffer> {
    const fullPath = this.resolvePath(ftpPath);
    const fileStat = await fs.stat(fullPath);
    const file = await fs.open(fullPath, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(fileStat.size);
    await fs.read(file.fd, buffer);
    await fs.close(file.fd);
    return buffer;
  }

  async readFileFrom(ftpPath: string, offset: number): Promise<ArrayBuffer> {
    const fullPath = this.resolvePath(ftpPath);
    const fileStat = await fs.stat(fullPath);
    const remaining = fileStat.size - offset;
    if (remaining <= 0) return new ArrayBuffer(0);
    const file = await fs.open(fullPath, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(remaining);
    await fs.read(file.fd, buffer, { offset: offset });
    await fs.close(file.fd);
    return buffer;
  }

  async writeFile(ftpPath: string, data: ArrayBuffer): Promise<void> {
    const fullPath = this.resolvePath(ftpPath);
    await this.ensureParentDir(fullPath);
    const file = await fs.open(fullPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    await fs.write(file.fd, data);
    await fs.close(file.fd);
  }

  async appendFile(ftpPath: string, data: ArrayBuffer): Promise<void> {
    const fullPath = this.resolvePath(ftpPath);
    await this.ensureParentDir(fullPath);
    const file = await fs.open(fullPath, fs.OpenMode.CREATE | fs.OpenMode.APPEND);
    await fs.write(file.fd, data);
    await fs.close(file.fd);
  }

  async deleteFile(ftpPath: string): Promise<void> {
    const fullPath = this.resolvePath(ftpPath);
    await fs.unlink(fullPath);
  }

  async rename(fromFtpPath: string, toFtpPath: string): Promise<void> {
    const fromFull = this.resolvePath(fromFtpPath);
    const toFull = this.resolvePath(toFtpPath);
    await fs.rename(fromFull, toFull);
  }

  async createDirectory(ftpPath: string): Promise<void> {
    const fullPath = this.resolvePath(ftpPath);
    await this.mkdirRecursive(fullPath);
  }

  async deleteDirectory(ftpPath: string): Promise<void> {
    const fullPath = this.resolvePath(ftpPath);
    await this.rmdirRecursive(fullPath);
  }

  async exists(ftpPath: string): Promise<boolean> {
    try {
      await fs.stat(this.resolvePath(ftpPath));
      return true;
    } catch (e) {
      return false;
    }
  }

  async isDirectory(ftpPath: string): Promise<boolean> {
    try {
      const stat = await fs.stat(this.resolvePath(ftpPath));
      return stat.isDirectory();
    } catch (e) {
      return false;
    }
  }

  private formatListDate(date: Date): string {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const now = new Date();
    const month = months[date.getMonth()];
    const day = date.getDate().toString().padStart(2, ' ');
    // 如果是今年内的文件，显示时间；否则显示年份
    if (date.getFullYear() === now.getFullYear()) {
      const h = date.getHours().toString().padStart(2, '0');
      const m = date.getMinutes().toString().padStart(2, '0');
      return `${month} ${day} ${h}:${m}`;
    } else {
      return `${month} ${day}  ${date.getFullYear()}`;
    }
  }

  private async ensureParentDir(fullPath: string): Promise<void> {
    const dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
    if (dir) {
      await this.mkdirRecursive(dir);
    }
  }

  private async mkdirRecursive(path: string): Promise<void> {
    const parts = path.split('/');
    let current = '';
    for (const part of parts) {
      if (!part) continue;
      current += '/' + part;
      try {
        await fs.stat(current);
      } catch (e) {
        try {
          await fs.mkdir(current);
        } catch (mkErr) {
          // 可能已被并发创建
        }
      }
    }
  }

  private async rmdirRecursive(path: string): Promise<void> {
    const entries: string[] = await fs.listFile(path);
    for (const name of entries) {
      const entryPath = `${path}/${name}`;
      try {
        const stat = await fs.stat(entryPath);
        if (stat.isDirectory()) {
          await this.rmdirRecursive(entryPath);
        } else {
          await fs.unlink(entryPath);
        }
      } catch (e) {
        // ignore
      }
    }
    await fs.rmdir(path);
  }
}
