import { FtpServerManager } from '../main/ets/ftp/FtpServerManager';

// FTP服务器功能测试
class FtpServerTest {
  private serverManager = FtpServerManager.getInstance();

  async runTests(): Promise<void> {
    console.log('=== Starting FTP Server Tests ===');

    // 测试1: 服务器启动测试
    await this.testServerStart();

    // 测试2: 服务器状态测试
    await this.testServerStatus();

    // 测试3: 服务器停止测试
    await this.testServerStop();

    console.log('=== FTP Server Tests Completed ===');
  }

  private async testServerStart(): Promise<void> {
    console.log('Test 1: Server Start');
    try {
      const result = await this.serverManager.startServer({
        port: 2121,
        user: 'test',
        password: 'test123',
        allowAnonymous: true
      });
      if (result) {
        console.log('✓ Server started successfully');
      } else {
        console.log('✗ Failed to start server');
      }
    } catch (error) {
      console.log(`✗ Error starting server: ${error}`);
    }
  }

  private async testServerStatus(): Promise<void> {
    console.log('Test 2: Server Status');
    try {
      const status = this.serverManager.getServerStatus();
      console.log(`✓ Server status: ${JSON.stringify(status)}`);
    } catch (error) {
      console.log(`✗ Error getting server status: ${error}`);
    }
  }

  private async testServerStop(): Promise<void> {
    console.log('Test 3: Server Stop');
    try {
      await this.serverManager.stopServer();
      const status = this.serverManager.getServerStatus();
      if (!status.isRunning) {
        console.log('✓ Server stopped successfully');
      } else {
        console.log('✗ Server is still running');
      }
    } catch (error) {
      console.log(`✗ Error stopping server: ${error}`);
    }
  }
}

// 运行测试
const test = new FtpServerTest();
test.runTests();