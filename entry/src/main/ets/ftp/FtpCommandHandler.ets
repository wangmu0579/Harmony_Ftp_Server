import { FtpConnection } from './FtpConnection';
import { FtpFileSystem } from './FtpFileSystem';
import net from '@ohos.net.socket';
import socket from '@ohos.net.socket';
import { fileIo } from '@kit.CoreFileKit'

export class FtpCommandHandler {
  private connection: FtpConnection;
  private fileSystem: FtpFileSystem;

  constructor(connection: FtpConnection) {
    this.connection = connection;
    this.fileSystem = new FtpFileSystem(connection);
  }

  async handleCommand(command: string): Promise<void> {
    const commandParts = command.split(' ');
    const cmd = commandParts[0];
    const args = commandParts.slice(1);
    const commandName = cmd.toUpperCase();
    const commandArgs = args.join(' ');

    try {
      switch (commandName) {
        case 'USER':
          this.handleUSER(commandArgs);
          break;
        case 'PASS':
          this.handlePASS(commandArgs);
          break;
        case 'LIST':
          await this.handleLIST(commandArgs);
          break;
        case 'NLST':
          await this.handleNLST(commandArgs);
          break;
        case 'RETR':
          await this.handleRETR(commandArgs);
          break;
        case 'STOR':
          await this.handleSTOR(commandArgs);
          break;
        case 'DELE':
          await this.handleDELE(commandArgs);
          break;
        case 'MKD':
          await this.handleMKD(commandArgs);
          break;
        case 'RMD':
          await this.handleRMD(commandArgs);
          break;
        case 'CWD':
          this.handleCWD(commandArgs);
          break;
        case 'PWD':
          this.handlePWD();
          break;
        case 'CDUP':
          this.handleCDUP();
          break;
        case 'TYPE':
          this.handleTYPE(commandArgs);
          break;
        case 'PORT':
          this.handlePORT(commandArgs);
          break;
        case 'PASV':
          this.handlePASV();
          break;
        case 'QUIT':
          this.handleQUIT();
          break;
        case 'SYST':
          this.handleSYST();
          break;
        case 'FEAT':
          this.handleFEAT();
          break;
        default:
          this.connection.sendResponse(502, 'Command not implemented');
      }
    } catch (error) {
      this.connection.sendResponse(500, 'Internal server error');
    }
  }

  private handleUSER(username: string): void {
    this.connection.setCurrentUser(username);
    this.connection.sendResponse(331, 'User name okay, need password');
  }

  private handlePASS(password: string): void {
    const config = this.connection.getConfig();
    if (config.validateCredentials(this.connection.getCurrentUser(), password)) {
      this.connection.setAuthenticated(true);
      this.connection.sendResponse(230, 'User logged in, proceed');
    } else {
      this.connection.sendResponse(530, 'User not logged in');
    }
  }

  private async handleLIST(path: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      // 先启动数据服务器监听
      await this.connection.openDataConnection();

      this.connection.sendResponse(150, 'Opening ASCII mode data connection for file list');
      
      // 等待客户端连接到数据服务器
      const dataSocket = await this.connection.waitForDataConnection();
      if (!dataSocket) {
          this.connection.sendResponse(425, 'Can\'t open data connection');
        return;
      }

      const fileList = await this.fileSystem.listFiles(path || this.connection.getCurrentDirectory());
      
      // 发送文件列表数据
      await this.connection.sendData(fileList);
      await this.connection.closeDataConnection();
      
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      console.error('Error handling LIST command:', error);
      this.connection.sendResponse(550, 'Failed to list files');
    }
  }

  private async handleNLST(path: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      // 先启动数据服务器监听
      await this.connection.openDataConnection();
      
      this.connection.sendResponse(150, 'Opening ASCII mode data connection for file list');
      
      // 等待客户端连接到数据服务器
      const dataSocket = await this.connection.waitForDataConnection();
      if (!dataSocket) {
        this.connection.sendResponse(425, 'Can\'t open data connection');
        return;
      }
      
      const fileList = await this.fileSystem.listFileNames(path || this.connection.getCurrentDirectory());
      
      // 发送文件列表数据
      await this.connection.sendData(fileList);
      await this.connection.closeDataConnection();
      
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      console.error('Error handling NLST command:', error);
      this.connection.sendResponse(550, 'Failed to list files');
    }
  }

  private async handleRETR(filename: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      // 先启动数据服务器监听
      await this.connection.openDataConnection();
      
      this.connection.sendResponse(150, 'Opening BINARY mode data connection for file transfer');
      
      // 等待客户端连接到数据服务器
      const dataSocket = await this.connection.waitForDataConnection();
      if (!dataSocket) {
        this.connection.sendResponse(425, 'Can\'t open data connection');
        return;
      }
      
      const filePath = `${this.connection.getCurrentDirectory()}/${filename}`;
      const fileData = await this.fileSystem.readFile(filePath);
      await this.connection.sendData(fileData);
      await this.connection.closeDataConnection();
      
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      console.error('Error handling RETR command:', error);
      this.connection.sendResponse(550, 'Failed to retrieve file');
    }
  }

  private async handleSTOR(filename: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      // 先启动数据服务器监听
      console.info('[FTP] STOR: Opening data connection for file:', filename);
      await this.connection.openDataConnection();
      
      this.connection.sendResponse(150, 'Opening BINARY mode data connection for file transfer');
      
      // 等待客户端连接到数据服务器
      const dataSocket = await this.connection.waitForDataConnection();
      if (!dataSocket) {
        console.error('[FTP] STOR: Data connection timeout');
        this.connection.sendResponse(425, 'Can\'t open data connection');
        return;
      }
      
      console.info('[FTP] STOR: Data connection established, reading file data...');
      // 实现从数据连接读取文件数据的逻辑
      const fileData = await this.readDataFromSocket(dataSocket);
      
      console.info('[FTP] STOR: Received', fileData.byteLength, 'bytes, writing to:', filename);

      // 将读取的数据写入文件
      const filePath = `${this.connection.getCurrentDirectory()}/${filename}`;
      console.info('[FTP] STOR: Full path:', filePath);
      await this.fileSystem.writeFile(filePath, fileData);

      await this.connection.closeDataConnection();

      this.connection.sendResponse(226, 'Transfer complete');
      console.info('[FTP] STOR: File stored successfully');
    } catch (error) {
      console.error('[FTP] STOR error:', error);
      this.connection.sendResponse(550, 'Failed to store file');
    }
  }

  // 从数据连接读取文件数据
  private async readDataFromSocket(dataSocket: socket.TCPSocketConnection): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve, reject) => {
      let dataChunks: ArrayBuffer[] = [];
      let totalSize = 0;
      
      // 设置超时 - 30秒
      const timeoutId = setTimeout(() => {
        console.error('[FTP] readDataFromSocket: Timeout waiting for data');
        // 即使超时也返回已接收的数据
        if (dataChunks.length > 0) {
          const result = new ArrayBuffer(totalSize);
          const resultView = new Uint8Array(result);
          let offset = 0;
          for (const chunk of dataChunks) {
            const chunkView = new Uint8Array(chunk);
            resultView.set(chunkView, offset);
            offset += chunk.byteLength;
          }
          console.info('[FTP] readDataFromSocket: Timeout but returning', totalSize, 'bytes');
          resolve(result);
        } else {
          reject(new Error('Timeout waiting for data'));
        }
      }, 30000);

      // 监听消息
      dataSocket.on('message', (messageInfo: socket.SocketMessageInfo) => {
        try {
          const data = messageInfo.message;
          if (data && data.byteLength > 0) {
            dataChunks.push(data);
            totalSize += data.byteLength;
            console.info('[FTP] readDataFromSocket: Received chunk,', data.byteLength, 'bytes, total:', totalSize);
          }
        } catch (error) {
          console.error('[FTP] Error receiving data:', error);
          clearTimeout(timeoutId);
          reject(new Error('Failed to receive data'));
        }
      });

      // 监听连接关闭
      dataSocket.on('close', () => {
        clearTimeout(timeoutId);
        console.info('[FTP] readDataFromSocket: Connection closed, total received:', totalSize);
        try {
          // 合并所有数据块
          if (totalSize === 0) {
            resolve(new ArrayBuffer(0));
            return;
          }
          const result = new ArrayBuffer(totalSize);
          const resultView = new Uint8Array(result);
          let offset = 0;

          for (const chunk of dataChunks) {
            const chunkView = new Uint8Array(chunk);
            resultView.set(chunkView, offset);
            offset += chunk.byteLength;
          }

          resolve(result);
        } catch (error) {
          console.error('[FTP] Error processing received data:', error);
          reject(new Error('Failed to process received data'));
        }
      });

      // 监听错误
      dataSocket.on('error', (error: Error) => {
        clearTimeout(timeoutId);
        console.error('[FTP] Socket error:', error);
        reject(new Error('Socket error during data transfer'));
      });
    });
  }

  private async handleDELE(filename: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      const filePath = `${this.connection.getCurrentDirectory()}/${filename}`;
      await this.fileSystem.deleteFile(filePath);
      this.connection.sendResponse(250, 'Requested file action okay, completed');
    } catch (error) {
      this.connection.sendResponse(550, 'Failed to delete file');
    }
  }

  private async handleMKD(directory: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      const dirPath = `${this.connection.getCurrentDirectory()}/${directory}`;
      await this.fileSystem.createDirectory(dirPath);
      this.connection.sendResponse(257, `"${dirPath}" created`);
    } catch (error) {
      this.connection.sendResponse(550, 'Failed to create directory');
    }
  }

  private async handleRMD(directory: string): Promise<void> {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    try {
      const dirPath = `${this.connection.getCurrentDirectory()}/${directory}`;
      await this.fileSystem.deleteDirectory(dirPath);
      this.connection.sendResponse(250, 'Requested file action okay, completed');
    } catch (error) {
      this.connection.sendResponse(550, 'Failed to delete directory');
    }
  }

  private handleCWD(path: string): void {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    // 实现切换目录逻辑
    this.connection.setCurrentDirectory(path);
    this.connection.sendResponse(250, 'Requested file action okay, completed');
  }

  private handlePWD(): void {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    this.connection.sendResponse(257, `"${this.connection.getCurrentDirectory()}" is the current directory`);
  }

  private handleCDUP(): void {
    if (!this.connection.isUserAuthenticated()) {
      this.connection.sendResponse(530, 'User not logged in');
      return;
    }

    // 实现切换到父目录逻辑
    const currentDir = this.connection.getCurrentDirectory();
    if (currentDir !== '/') {
      const parentDir = currentDir.substring(0, currentDir.lastIndexOf('/')) || '/';
      this.connection.setCurrentDirectory(parentDir);
    }
    this.connection.sendResponse(250, 'Requested file action okay, completed');
  }

  private handleTYPE(type: string): void {
    // 实现设置传输类型逻辑
    this.connection.sendResponse(200, 'Command okay');
  }

  private handlePORT(port: string): void {
    // 实现主动模式端口设置逻辑
    try {
      const parts = port.split(',');
      if (parts.length === 6) {
        const ip = parts.slice(0, 4).join('.');
        const p1 = parseInt(parts[4], 10);
        const p2 = parseInt(parts[5], 10);
        const portNumber = p1 * 256 + p2;
        
        this.connection.setActiveModeAddress(ip, portNumber);
        this.connection.sendResponse(200, 'Command okay');
      } else {
        this.connection.sendResponse(501, 'Syntax error in parameters or arguments');
      }
    } catch (error) {
      this.connection.sendResponse(501, 'Syntax error in parameters or arguments');
    }
  }

  private handlePASV(): void {
    // 实现被动模式逻辑
    // 打开数据连接获取实际端口
    console.info('[FTP] PASV command received, opening data connection...');
    this.connection.openDataConnection().then((dataSocket) => {
      // 监听成功后，服务器已就绪，等待客户端连接数据端口
      const port = this.connection.getPassiveModePort();
      console.info('[FTP] PASV data server started on port:', port);
      // 从配置中获取服务器IP地址
      const config = this.connection.getConfig();
      //const serverIp = config.serverIp || '127.0.0.1';
      const serverIp =  '127.0.0.1';
      // 将IP地址转换为逗号分隔格式
      const ipParts = serverIp.split('.');
      const ip = ipParts.join(',');
      
      // 将端口转换为两个字节
      const p1 = Math.floor(port / 256);
      const p2 = port % 256;
      
      console.info('[FTP] Sending PASV response with port:', port, 'p1:', p1, 'p2:', p2);
      this.connection.sendResponse(227, `Entering Passive Mode (${ip},${p1},${p2})`);
    }).catch(() => {
      this.connection.sendResponse(425, 'Can\'t open data connection');
    });
  }

  private handleQUIT(): void {
    this.connection.sendResponse(221, 'Service closing control connection');
    this.connection.close();
  }

  private handleSYST(): void {
    this.connection.sendResponse(215, 'UNIX Type: L8');
  }

  private handleFEAT(): void {
    // FTP多行响应格式：211-Features 然后是特性列表 最后以211 End结束
    this.connection.sendResponse(211, 'Features:');
    this.connection.sendResponseLine(' SIZE');
    this.connection.sendResponseLine(' UTF8');
    this.connection.sendResponse(211, 'End');
  }
}