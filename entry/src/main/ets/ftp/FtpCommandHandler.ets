import { FtpConnection } from './FtpConnection';
import { FtpFileSystem } from './FtpFileSystem';

export class FtpCommandHandler {
  private connection: FtpConnection;
  private fs: FtpFileSystem;

  constructor(connection: FtpConnection) {
    this.connection = connection;
    this.fs = new FtpFileSystem(connection);
  }

  async handleCommand(raw: string): Promise<void> {
    const spaceIdx = raw.indexOf(' ');
    const cmd = (spaceIdx === -1 ? raw : raw.substring(0, spaceIdx)).toUpperCase();
    const args = spaceIdx === -1 ? '' : raw.substring(spaceIdx + 1);

    try {
      switch (cmd) {
        case 'USER': return this.handleUSER(args);
        case 'PASS': return this.handlePASS(args);
        case 'QUIT': return this.handleQUIT();
        case 'AUTH': return this.connection.sendResponse(502, 'Security extensions not implemented');
        case 'FEAT': return this.handleFEAT();
        case 'OPTS': return this.handleOPTS(args);
        case 'SYST': return this.connection.sendResponse(215, 'UNIX Type: L8');
        case 'NOOP': return this.connection.sendResponse(200, 'NOOP ok');
      }

      if (!this.connection.isUserAuthenticated()) {
        return this.connection.sendResponse(530, 'Please login with USER and PASS');
      }

      switch (cmd) {
        case 'PWD': case 'XPWD': return this.handlePWD();
        case 'CWD': return await this.handleCWD(args);
        case 'CDUP': case 'XCUP': return this.handleCDUP();
        case 'TYPE': return this.handleTYPE(args);
        case 'PASV': return await this.handlePASV();
        case 'EPSV': return await this.handleEPSV();
        case 'PORT': return this.handlePORT(args);
        case 'LIST': return await this.handleLIST(args);
        case 'NLST': return await this.handleNLST(args);
        case 'MLSD': return await this.handleMLSD(args);
        case 'RETR': return await this.handleRETR(args);
        case 'STOR': return await this.handleSTOR(args);
        case 'APPE': return await this.handleAPPE(args);
        case 'DELE': return await this.handleDELE(args);
        case 'MKD': case 'XMKD': return await this.handleMKD(args);
        case 'RMD': case 'XRMD': return await this.handleRMD(args);
        case 'RNFR': return this.handleRNFR(args);
        case 'RNTO': return await this.handleRNTO(args);
        case 'SIZE': return await this.handleSIZE(args);
        case 'MDTM': return await this.handleMDTM(args);
        case 'REST': return this.handleREST(args);
        case 'ABOR': return await this.handleABOR();
        case 'STAT': return this.connection.sendResponse(211, `Connected as ${this.connection.getCurrentUser()}`);
        case 'SITE': return this.connection.sendResponse(202, 'No SITE commands implemented');
        case 'HELP': return this.connection.sendResponse(214, 'Help not available');
        default: return this.connection.sendResponse(502, `Command ${cmd} not implemented`);
      }
    } catch (error) {
      this.connection.getLogger().error(`Command ${cmd} error: ${error}`);
      this.connection.sendResponse(500, 'Internal server error');
    }
  }

  private handleUSER(username: string): void {
    this.connection.setCurrentUser(username);
    this.connection.setAuthenticated(false);
    this.connection.sendResponse(331, 'User name okay, need password');
  }

  private handlePASS(password: string): void {
    if (this.connection.getConfig().validateCredentials(this.connection.getCurrentUser(), password)) {
      this.connection.setAuthenticated(true);
      this.connection.sendResponse(230, 'User logged in');
    } else {
      this.connection.sendResponse(530, 'Login incorrect');
    }
  }

  private handleQUIT(): void {
    this.connection.sendResponse(221, 'Goodbye');
    this.connection.close();
  }

  private handleFEAT(): void {
    this.connection.sendMultiLineBegin(211, 'Features:');
    this.connection.sendMultiLineLine('PASV');
    this.connection.sendMultiLineLine('EPSV');
    this.connection.sendMultiLineLine('SIZE');
    this.connection.sendMultiLineLine('MDTM');
    this.connection.sendMultiLineLine('REST STREAM');
    this.connection.sendMultiLineLine('UTF8');
    this.connection.sendMultiLineLine('MLSD');
    this.connection.sendMultiLineEnd(211, 'End');
  }

  private handleOPTS(args: string): void {
    if (args.toUpperCase().startsWith('UTF8')) {
      this.connection.sendResponse(200, 'UTF8 set to on');
    } else {
      this.connection.sendResponse(501, 'Option not understood');
    }
  }

  private handlePWD(): void {
    this.connection.sendResponse(257, `"${this.connection.getCurrentDirectory()}" is current directory`);
  }

  private async handleCWD(path: string): Promise<void> {
    const newPath = this.resolveVirtualPath(path);
    if (await this.fs.isDirectory(newPath)) {
      this.connection.setCurrentDirectory(newPath);
      this.connection.sendResponse(250, 'Directory changed');
    } else {
      this.connection.sendResponse(550, 'Directory not found');
    }
  }

  private handleCDUP(): void {
    const cwd = this.connection.getCurrentDirectory();
    if (cwd !== '/') {
      this.connection.setCurrentDirectory(cwd.substring(0, cwd.lastIndexOf('/')) || '/');
    }
    this.connection.sendResponse(250, 'Directory changed');
  }

  private handleTYPE(type: string): void {
    const t = type.toUpperCase().charAt(0);
    if (t === 'A' || t === 'I') {
      this.connection.setTransferType(t);
      this.connection.sendResponse(200, `Type set to ${t}`);
    } else {
      this.connection.sendResponse(504, 'Type not supported');
    }
  }

  private async handlePASV(): Promise<void> {
    try {
      const port = await this.connection.openPassiveDataServer();
      const config = this.connection.getConfig();
      // 模拟器：返回 127.0.0.1（通过端口转发连接）
      // 真机：返回 WiFi IP
      const isEmulator = config.serverIp.startsWith('192.168.76.') || config.serverIp.startsWith('10.0.2.');
      const ip = isEmulator ? '127,0,0,1' : config.serverIp.split('.').join(',');
      const p1 = Math.floor(port / 256);
      const p2 = port % 256;
      this.connection.sendResponse(227, `Entering Passive Mode (${ip},${p1},${p2})`);
    } catch (error) {
      this.connection.sendResponse(425, 'Cannot open passive connection');
    }
  }

  private async handleEPSV(): Promise<void> {
    try {
      const port = await this.connection.openPassiveDataServer();
      this.connection.sendResponse(229, `Entering Extended Passive Mode (|||${port}|)`);
    } catch (error) {
      this.connection.sendResponse(425, 'Cannot open passive connection');
    }
  }

  private handlePORT(args: string): void {
    const parts = args.split(',');
    if (parts.length !== 6) {
      this.connection.sendResponse(501, 'Syntax error');
    } else {
      this.connection.sendResponse(200, 'PORT command successful');
    }
  }

  private handleREST(args: string): void {
    const offset = parseInt(args, 10);
    if (isNaN(offset) || offset < 0) {
      this.connection.sendResponse(501, 'Invalid restart offset');
    } else {
      this.connection.setRestOffset(offset);
      this.connection.sendResponse(350, `Restart position accepted (${offset})`);
    }
  }

  // ========== 数据传输命令：不再重新 openPassiveDataServer ==========
  // PASV/EPSV 已经开好端口，这里只需等待客户端连上来

  private async handleLIST(path: string): Promise<void> {
    try {
      let listPath = path;
      if (listPath.startsWith('-')) {
        const si = listPath.indexOf(' ');
        listPath = si === -1 ? '' : listPath.substring(si + 1);
      }
      const target = listPath || this.connection.getCurrentDirectory();
      this.connection.getLogger().info(`LIST target=${target} realPath=${this.fs.resolvePath(target)}`);

      this.connection.sendResponse(150, 'Opening data connection for directory listing');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      const listing = await this.fs.listFiles(target);
      await this.connection.sendData(listing);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      this.connection.getLogger().error(`LIST error: ${error}`);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'Failed to list directory');
    }
  }

  private async handleNLST(path: string): Promise<void> {
    try {
      const target = path || this.connection.getCurrentDirectory();
      this.connection.sendResponse(150, 'Opening data connection for name list');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      const listing = await this.fs.listFileNames(target);
      await this.connection.sendData(listing);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'Failed to list directory');
    }
  }

  private async handleMLSD(path: string): Promise<void> {
    try {
      const target = path || this.connection.getCurrentDirectory();
      const realPath = this.fs.resolvePath(target);
      this.connection.getLogger().info(`MLSD target=${target} realPath=${realPath}`);
      const entries = await this.fs.getFilesInDirectory(realPath);

      this.connection.sendResponse(150, 'Opening data connection for MLSD');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      let result = '';
      for (const entry of entries) {
        const info = await this.fs.getFileInfo(entry);
        const type = info.type === 'directory' ? 'dir' : 'file';
        const modify = this.formatMDTM(info.modifiedTime);
        result += `type=${type};size=${info.size};modify=${modify}; ${info.name}\r\n`;
      }

      await this.connection.sendData(result);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      this.connection.getLogger().error(`MLSD error: ${error}`);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'Failed to list directory');
    }
  }

  private async handleRETR(filename: string): Promise<void> {
    try {
      const ftpPath = this.resolveVirtualPath(filename);
      this.connection.sendResponse(150, 'Opening data connection for file transfer');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      const offset = this.connection.getRestOffset();
      this.connection.setRestOffset(0);

      const data = offset > 0
        ? await this.fs.readFileFrom(ftpPath, offset)
        : await this.fs.readFile(ftpPath);

      await this.connection.sendData(data);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      this.connection.getLogger().error(`RETR error: ${error}`);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'File not found or access denied');
    }
  }

  private async handleSTOR(filename: string): Promise<void> {
    try {
      const ftpPath = this.resolveVirtualPath(filename);
      this.connection.sendResponse(150, 'Opening data connection for file upload');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      const data = await this.connection.readAllDataFromSocket();
      await this.fs.writeFile(ftpPath, data);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, `Transfer complete (${data.byteLength} bytes)`);
    } catch (error) {
      this.connection.getLogger().error(`STOR error: ${error}`);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'Failed to store file');
    }
  }

  private async handleAPPE(filename: string): Promise<void> {
    try {
      const ftpPath = this.resolveVirtualPath(filename);
      this.connection.sendResponse(150, 'Opening data connection for append');

      if (!await this.connection.waitForDataConnection()) {
        this.connection.sendResponse(425, 'No data connection');
        return;
      }

      const data = await this.connection.readAllDataFromSocket();
      await this.fs.appendFile(ftpPath, data);
      await this.connection.closeDataConnection();
      this.connection.sendResponse(226, 'Transfer complete');
    } catch (error) {
      await this.connection.closeDataConnection();
      this.connection.sendResponse(550, 'Failed to append file');
    }
  }

  // ========== 文件操作 ==========

  private async handleDELE(filename: string): Promise<void> {
    try {
      await this.fs.deleteFile(this.resolveVirtualPath(filename));
      this.connection.sendResponse(250, 'File deleted');
    } catch (error) {
      this.connection.sendResponse(550, 'Delete failed');
    }
  }

  private async handleMKD(dirname: string): Promise<void> {
    try {
      const ftpPath = this.resolveVirtualPath(dirname);
      await this.fs.createDirectory(ftpPath);
      this.connection.sendResponse(257, `"${ftpPath}" created`);
    } catch (error) {
      this.connection.sendResponse(550, 'Create directory failed');
    }
  }

  private async handleRMD(dirname: string): Promise<void> {
    try {
      await this.fs.deleteDirectory(this.resolveVirtualPath(dirname));
      this.connection.sendResponse(250, 'Directory removed');
    } catch (error) {
      this.connection.sendResponse(550, 'Remove directory failed');
    }
  }

  private handleRNFR(path: string): void {
    this.connection.setRenameFrom(this.resolveVirtualPath(path));
    this.connection.sendResponse(350, 'Ready for RNTO');
  }

  private async handleRNTO(path: string): Promise<void> {
    const from = this.connection.getRenameFrom();
    if (!from) {
      this.connection.sendResponse(503, 'RNFR required first');
      return;
    }
    try {
      await this.fs.rename(from, this.resolveVirtualPath(path));
      this.connection.setRenameFrom('');
      this.connection.sendResponse(250, 'Rename successful');
    } catch (error) {
      this.connection.sendResponse(550, 'Rename failed');
    }
  }

  private async handleSIZE(path: string): Promise<void> {
    try {
      const size = await this.fs.getFileSize(this.resolveVirtualPath(path));
      this.connection.sendResponse(213, size.toString());
    } catch (error) {
      this.connection.sendResponse(550, 'Could not get file size');
    }
  }

  private async handleMDTM(path: string): Promise<void> {
    try {
      const mtime = await this.fs.getModifiedTime(this.resolveVirtualPath(path));
      this.connection.sendResponse(213, this.formatMDTM(mtime));
    } catch (error) {
      this.connection.sendResponse(550, 'Could not get modification time');
    }
  }

  private async handleABOR(): Promise<void> {
    await this.connection.closeDataConnection();
    this.connection.sendResponse(226, 'ABOR command successful');
  }

  private resolveVirtualPath(path: string): string {
    if (!path) return this.connection.getCurrentDirectory();
    if (path.startsWith('/')) return path;
    const cwd = this.connection.getCurrentDirectory();
    return cwd === '/' ? `/${path}` : `${cwd}/${path}`;
  }

  private formatMDTM(date: Date): string {
    const y = date.getFullYear().toString();
    const M = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    const h = date.getHours().toString().padStart(2, '0');
    const m = date.getMinutes().toString().padStart(2, '0');
    const s = date.getSeconds().toString().padStart(2, '0');
    return `${y}${M}${d}${h}${m}${s}`;
  }
}
