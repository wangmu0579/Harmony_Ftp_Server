
import { FtpServerManager } from '../ftp/FtpServerManager';
import wifiManager from '@ohos.wifiManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { FtpConfig } from '../ftp/FtpConfig';
// 定义接口
export interface ServerConfig {
  port: number;
  user: string;
  password: string;
  allowAnonymous: boolean;
}

// WiFi信息接口
export interface WifiInfo {
  ipAddress?: number;
}

@Entry
@Component
struct Index {
  @State isServerRunning: boolean = false;
  @State serverPort: number = 21;
  @State serverUser: string = 'anonymous';
  @State serverPassword: string = '';
  @State allowAnonymous: boolean = true;
  @State connectionCount: number = 0;
  @State statusMessage: string = 'FTP Server is stopped';
  @State isLoading: boolean = false;
  @State deviceIpAddress: string = 'Getting IP address...';

  private serverManager = FtpServerManager.getInstance();

  aboutToAppear() {
    this.checkServerStatus();
    this.getDeviceIpAddress();
  }
  async getDeviceIpAddress() {
    try {
      // 获取WiFi信息 - 使用鸿蒙系统API
      const wifiInfo = await this.getWifiInfoFromSystem();
      if (wifiInfo && wifiInfo.ipAddress) {
        // 将整数IP地址转换为字符串格式
        const ip = this.intToIp(wifiInfo.ipAddress);
        this.deviceIpAddress = ip;
      } else {
        this.deviceIpAddress = 'No IP address found';
      }
    } catch (error) {
      console.error('Failed to get IP address:', error);
      this.deviceIpAddress = 'Failed to get IP address';
    }
  }
  // 使用真实的鸿蒙系统API获取WiFi信息
  private async getWifiInfoFromSystem(): Promise<WifiInfo> {
    try {

      //console.log(wifiManager.isWifiActive());
      if (!wifiManager.isWifiActive()) {
        console.warn('WiFi is not enabled');
        return {};
      }
     const wifiInfo =  wifiManager.getIpInfo();
      if (wifiInfo) {
        return {
          ipAddress: wifiInfo.ipAddress
        };
      }
      return {};
    } catch (error) {
      console.error('Failed to get WiFi info:', error);
      // 如果API不可用，返回空对象
      return {};
    }
  }

  // 将整数IP地址转换为字符串格式
  private intToIp(ipInt: number): string {
    return `${(ipInt >> 24) & 0xFF}.${(ipInt >> 16) & 0xFF}.${(ipInt >> 8) & 0xFF}.${ipInt & 0xFF}`;
  }

  async checkServerStatus() {
    const status = this.serverManager.getServerStatus();
    this.isServerRunning = status.isRunning;
    this.serverPort = status.port;
    this.connectionCount = status.connectionCount;
    this.statusMessage = this.isServerRunning 
      ? `FTP Server is running on port ${this.serverPort}` 
      : 'FTP Server is stopped';
  }

  async startServer() {if (this.isLoading) return;
    
    this.isLoading = true;
    this.statusMessage = 'Starting FTP Server...';
    
    try {
      const config: ServerConfig = {
        port: this.serverPort,
        user: this.serverUser,
        password: this.serverPassword,
        allowAnonymous: this.allowAnonymous
      };
      
      const result = await this.serverManager.startServer(config);
      if (result) {
        this.statusMessage = `FTP Server started on port ${this.serverPort}`;
        this.isServerRunning = true;
      } else {
        this.statusMessage = 'Failed to start FTP Server';
      }
    } catch (error) {
      this.statusMessage = `Error starting server: ${error}`;
    } finally {
      this.isLoading = false;
    }
  }

  async stopServer() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    this.statusMessage = 'Stopping FTP Server...';
    
    try {
      await this.serverManager.stopServer();
      this.statusMessage = 'FTP Server stopped';
      this.isServerRunning = false;
      this.connectionCount = 0;
    } catch (error) {
      this.statusMessage = `Error stopping server: ${error}`;
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column({
      space: 20
    }) {
      // Header
      Text('FTP Server Control')
        .fontSize(30)
        .fontWeight(700)
        .margin({ top: 40 })

      // Status Card
      Column({
        space: 10
      }) {
        Text(this.statusMessage)
          .fontSize(18)
          .fontWeight(500)
        
        if (this.isServerRunning) {
          Text(`Active connections: ${this.connectionCount}`)
            .fontSize(16)
            .fontColor('#666666')
        }
        
        Text(`Device IP Address: ${this.deviceIpAddress}`)
          .fontSize(16)
          .fontColor('#666666')
      }
      .width('90%')
      .padding(20)
      .backgroundColor(this.isServerRunning ? '#E6F7EF' : '#FFF2E8')
      .borderRadius(12)
      .shadow({
        color: '#00000010',
        offsetX: 0,
        offsetY: 2,
        radius: 4
      })

      // Control Buttons
      Row({
        space: 20
      }) {
        Button('Start Server')
          .width('45%')
          .height(48)
          .fontSize(16)
          .fontWeight(500)
          .backgroundColor('#52C41A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .enabled(!this.isServerRunning && !this.isLoading)
          .onClick(() => this.startServer())

        Button('Stop Server')
          .width('45%')
          .height(48)
          .fontSize(16)
          .fontWeight(500)
          .backgroundColor('#FF4D4F')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .enabled(this.isServerRunning && !this.isLoading)
          .onClick(() => this.stopServer())
      }
      .width('90%')

      // Configuration Section
      Column({
        space: 15
      }) {
        Text('Server Configuration')
          .fontSize(20)
          .fontWeight(700)
          .alignSelf(ItemAlign.Start)

        // Port Configuration
        Row({
          space: 10
        }) {
          Text('Port:')
            .width('30%')
            .fontSize(16)
            .alignSelf(ItemAlign.Center)
          
          TextInput({
            text: this.serverPort.toString(),
            placeholder: 'Enter port number'
          })
            .width('70%')
            .height(40)
            .fontSize(16)
            .borderRadius(8)
            .border({ width: 1, color: '#DDDDDD' })
            .onChange((value: string) => {
              const port = parseInt(value);
              if (!isNaN(port) && port > 0 && port < 65536) {
                this.serverPort = port;
              }
            })
        }

        // User Configuration
        Row({
          space: 10
        }) {
          Text('User:')
            .width('30%')
            .fontSize(16)
            .alignSelf(ItemAlign.Center)
          
          TextInput({
            text: this.serverUser,
            placeholder: 'Enter username'
          })
            .width('70%')
            .height(40)
            .fontSize(16)
            .borderRadius(8)
            .border({ width: 1, color: '#DDDDDD' })
            .onChange((value: string) => {
              this.serverUser = value;
            })
        }

        // Password Configuration
        Row({
          space: 10
        }) {
          Text('Password:')
            .width('30%')
            .fontSize(16)
            .alignSelf(ItemAlign.Center)
          
          TextInput({
            text: this.serverPassword,
            placeholder: 'Enter password'
          })
            .width('70%')
            .height(40)
            .fontSize(16)
            .borderRadius(8)
            .border({ width: 1, color: '#DDDDDD' })
            .type(InputType.Password)
            .onChange((value: string) => {
              this.serverPassword = value;
            })
        }

        // Allow Anonymous
        Row({
          space: 10
        }) {
          Text('Allow Anonymous:')
            .width('70%')
            .fontSize(16)
            .alignSelf(ItemAlign.Center)
          
          Toggle({
            type: ToggleType.Switch,
            isOn: this.allowAnonymous
          })
            .width('30%')
            .height(40)
            .onChange((isOn: boolean) => {
              this.allowAnonymous = isOn;
            })
        }
      }
      .width('90%')
      .padding(20)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)

      // Info Section
      Text('FTP Server Information')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 20, bottom: 40 })
        .textAlign(TextAlign.Center)

      Text('Root Directory: App Sandbox')
        .fontSize(14)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
  }
}