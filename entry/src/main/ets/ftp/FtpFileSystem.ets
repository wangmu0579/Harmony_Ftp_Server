import fs from '@ohos.file.fs';
import { FtpConnection } from './FtpConnection';
import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit'
import featureAbility from '@ohos.ability.featureAbility';

// 接口定义
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
    // 从配置中获取FTP根目录
    const config = connection.getConfig();
    this.rootPath = config.rootDirectory;
    console.info('[FTP] FtpFileSystem constructor: rootDirectory from config:', this.rootPath);
    
    // 如果配置目录为空或不可访问，使用默认目录
    if (!this.rootPath || this.rootPath === '/') {
      try {
        const context = getContext();
        this.rootPath = context.filesDir;
        console.info('[FTP] Using default filesDir:', this.rootPath);
      } catch (e) {
        this.rootPath = '/';
      }
    }
  }

  async listFiles(path: string): Promise<string> {
    try {
      const fullPath = this.getFullPath(path);

      // 先打开目录获取文件描述符
      const files = await this.getFilesInDirectory(fullPath);
      console.info('[FTP] listFiles: got', files.length, 'files');

      let result = '';
      
      for (const file of files) {
        const fileInfo = await this.getFileInfo(file);
        result += `${fileInfo.type === 'directory' ? 'd' : '-'}rwxrwxrwx 1 ftp ftp ${fileInfo.size} ${this.formatDate(fileInfo.modifiedTime)} ${fileInfo.name}\r\n`;
      }
      
      return result;
    } catch (error) {
      console.error('[FTP] listFiles error:', error);
      throw new Error('Failed to list files');
    }
  }

  async listFileNames(path: string): Promise<string> {
    try {
      const fullPath = this.getFullPath(path);
      const files = await this.getFilesInDirectory(fullPath);
      return files.map(file => file.name).join('\r\n') + '\r\n';
    } catch (error) {
      throw new Error('Failed to list file names');
    }
  }

  async getFilesInDirectory(path: string): Promise<FileEntry[]> {
    console.info('[FTP] getFilesInDirectory: Listing files in:', path);
    try {
      // 先检查目录是否存在
      try {
        const dirStat = await fs.stat(path);
        console.info('[FTP] getFilesInDirectory: Directory exists, isDirectory:', dirStat.isDirectory());
      } catch (statError) {
        console.error('[FTP] getFilesInDirectory: Directory does not exist or not accessible:', statError);
      }
      
      // 使用listFile列出文件
      const entries: string[] = await fs.listFile(path);
      console.info('[FTP] getFilesInDirectory: Found', entries.length, 'entries');
      
      const result: FileEntry[] = [];
      for (let i = 0; i < entries.length; i++) {
        const entryName: string = entries[i];
        const entryPath = `${path}/${entryName}`;
        
        // 检查是文件还是目录
        try {
          const stat = await fs.stat(entryPath);
          console.info('[FTP] getFilesInDirectory: Entry:', entryName, 'isDirectory:', stat.isDirectory());
        } catch (entryStatError) {
          console.error('[FTP] getFilesInDirectory: Cannot stat entry:', entryName, entryStatError);
        }
        
        result.push({
          name: entryName,
          path: entryPath
        });
      }
      return result;
    } catch (error) {
      console.error('[FTP] getFilesInDirectory error:', error);
      // 如果目录不存在，返回空数组
      return [];
    }
  }

  async getFileInfo(file: FileEntry): Promise<FileInfo> {
    try {
      const stat = await fs.stat(file.path);
      return {
        name: file.name,
        size: stat.size,
        modifiedTime: new Date(stat.mtime),
        type: stat.isDirectory() ? 'directory' : 'file'
      };
    } catch (error) {
      // 如果获取文件信息失败，返回默认值
      return {
        name: file.name,
        size: 0,
        modifiedTime: new Date(),
        type: 'file'
      };
    }
  }

  private formatDate(date: Date): string {
    const month = date.toLocaleString('default', { month: 'short' });
    const day = date.getDate().toString().padStart(2, ' ');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    
    return `${month} ${day} ${hours}:${minutes}`;
  }

  async readFile(path: string): Promise<ArrayBuffer> {
    try {
      const fullPath = this.getFullPath(path);
      const file = await fs.open(fullPath, fs.OpenMode.READ_ONLY);
      const size = (await fs.stat(fullPath)).size;
      const buffer = new ArrayBuffer(size);
      await fs.read(file.fd, buffer);
      await fs.close(file.fd);
      return buffer;
    } catch (error) {
      throw new Error('Failed to read file');
    }
  }

  async writeFile(path: string, data: ArrayBuffer): Promise<void> {
    try {
      const fullPath = this.getFullPath(path);
      console.info('[FTP] writeFile: Writing to fullPath:', fullPath, 'size:', data.byteLength);
      // 确保目录存在
      await this.ensureDirectoryExists(fullPath.substring(0, fullPath.lastIndexOf('/')));
      const file = await fs.open(fullPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      await fs.write(file.fd, data);
      await fs.close(file.fd);
      console.info('[FTP] writeFile: Success');
    } catch (error) {
      console.error('[FTP] writeFile error:', error);
      throw new Error('Failed to write file');
    }
  }

  async deleteFile(path: string): Promise<void> {
    try {
      const fullPath = this.getFullPath(path);
      await fs.unlink(fullPath);
    } catch (error) {
      throw new Error('Failed to delete file');
    }
  }

  async createDirectory(path: string): Promise<void> {
    try {
      const fullPath = this.getFullPath(path);
      // 使用递归方式创建目录
      await this.createDirectoryRecursive(fullPath);
    } catch (error) {
      throw new Error('Failed to create directory');
    }
  }

  async deleteDirectory(path: string): Promise<void> {
    try {
      const fullPath = this.getFullPath(path);
      await this.rmdirRecursive(fullPath);
    } catch (error) {
      throw new Error('Failed to delete directory');
    }
  }

  async exists(path: string): Promise<boolean> {
    try {
      const fullPath = this.getFullPath(path);
      await fs.stat(fullPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  async isDirectory(path: string): Promise<boolean> {
    try {
      const fullPath = this.getFullPath(path);
      const stat = await fs.stat(fullPath);
      return stat.isDirectory();
    } catch (error) {
      return false;
    }
  }

  private getFullPath(relativePath: string): string {
    // 处理相对路径，确保使用应用沙箱路径作为根目录
    if (relativePath === '/') {
      return this.rootPath;
    }
    // 移除开头的斜杠
    const normalizedPath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return `${this.rootPath}/${normalizedPath}`;
  }

  private async ensureDirectoryExists(directory: string): Promise<void> {
    try {
      await fs.stat(directory);
    } catch (error) {
      // 目录不存在，创建它
      try {
        await this.createDirectoryRecursive(directory);
      } catch (mkdirError) {
        throw new Error('Failed to create directory');
      }
    }
  }

  private async createDirectoryRecursive(path: string): Promise<void> {
    const parts = path.split('/');
    let currentPath = '';
    
    for (const part of parts) {
      if (part) {
        currentPath += '/' + part;
        try {
          await fs.stat(currentPath);
        } catch (error) {
          await fs.mkdir(currentPath);
        }
      }
    }
  }

  private async rmdirRecursive(path: string): Promise<void> {
    try {
      const entries: string[] = await fs.listFile(path);
      for (let i = 0; i < entries.length; i++) {
        const entryName: string = entries[i];
        const entryPath = `${path}/${entryName}`;
        try {
          const stat = await fs.stat(entryPath);
          if (stat.isDirectory()) {
            await this.rmdirRecursive(entryPath);
          } else {
            await fs.unlink(entryPath);
          }
        } catch (entryError) {
          // 忽略单个文件/目录的错误，继续处理其他项
        }
      }
      await fs.rmdir(path);
    } catch (error) {
      throw new Error('Failed to delete directory recursively');
    }
  }
}