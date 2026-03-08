
import { FtpServerManager } from '../ftp/FtpServerManager';
import wifiManager from '@ohos.wifiManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { FtpConfig } from '../ftp/FtpConfig';
import picker from '@ohos.file.picker';
import bundleManager from '@ohos.bundle.bundleManager';
import common from '@ohos.app.ability.common';

// 定义接口
export interface ServerConfig {
  port: number;
  user: string;
  password: string;
  allowAnonymous: boolean;
  rootDirectory: string;
  serverIp: string;
}

interface PermissionInfo {
  name: string;
  desc: string;
}

// WiFi信息接口
export interface WifiInfo {
  ipAddress?: number;
}

@Entry
@Component
struct Index {
  @State isServerRunning: boolean = false;
  @State serverPort: number = 2121;
  @State serverUser: string = 'anonymous';
  @State serverPassword: string = '';
  @State allowAnonymous: boolean = true;
  @State rootDirectory: string = '';
  @State connectionCount: number = 0;
  @State statusMessage: string = 'FTP Server is stopped';
  @State isLoading: boolean = false;
  @State deviceIpAddress: string = 'Getting IP address...';

  private serverManager = FtpServerManager.getInstance();

  private updateTimer: number = -1;

  aboutToAppear() {
    this.serverManager.setLogLevel("debug");
    //serverManager.setLogLevel('debug');
    this.requestPermissions();
    this.checkServerStatus();
    this.getDeviceIpAddress();
    this.startStatusUpdateTimer();
    this.selectRootDirectory();
  }

  aboutToDisappear() {
    this.stopStatusUpdateTimer();
  }

  // 请求存储权限
  private async requestPermissions(): Promise<void> {
    try {
      console.info('[Permission] Requesting storage permissions...');
      
      // 获取应用的abilityAccessCtrl管理器
      const atManager = abilityAccessCtrl.createAtManager();
      
      // 获取应用bundle信息
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const appInfo = bundleInfo.appInfo;
      const tokenId = appInfo.accessTokenId;
      
      console.info('[Permission] TokenId:', tokenId);
      
      // 定义权限列表
      const permissions: PermissionInfo[] = [
        { name: 'ohos.permission.READ_MEDIA', desc: 'read media' },
        { name: 'ohos.permission.WRITE_MEDIA', desc: 'write media' }
      ];
      
      // 检查并请求权限
      for (let i = 0; i < permissions.length; i++) {
        const perm = permissions[i];
        try {
          // 检查权限状态
          const permName: Permissions = perm.name as Permissions;
          const granted = atManager.checkAccessTokenSync(tokenId, permName);
          console.info('[Permission]', perm.name, 'granted:', granted === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
          
          if (granted !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
            console.info('[Permission] Requesting:', perm.name);
            // 请求权限
            await atManager.requestPermissionsFromUser(
              globalThis.AbilityContext as common.UIAbilityContext,
              [permName]
            );
          }
        } catch (err) {
          console.error('[Permission] Error with', perm.name, ':', (err as Error).message);
        }
      }
      
      console.info('[Permission] Permissions check complete');
    } catch (error) {
      console.error('[Permission] Error requesting permissions:', (error as Error).message);
    }
  }

  // 启动定时器定期更新服务器状态
  private startStatusUpdateTimer() {
    if (this.updateTimer !== -1) {
      return;
    }
    // 每2秒更新一次连接数
    this.updateTimer = setInterval(() => {
      this.checkServerStatus();
    }, 2000);
  }

  // 停止定时器
  private stopStatusUpdateTimer() {
    if (this.updateTimer !== -1) {
      clearInterval(this.updateTimer);
      this.updateTimer = -1;
    }
  }

  // 选择根目录 - 弹出文件夹选择器
  private selectRootDirectory(): void {
    try {
      // 使用picker选择目录，设置选项以允许选择文件夹
      const documentPicker = new picker.DocumentViewPicker();
      
      // 选择文件，然后获取其父目录作为FTP根目录
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['*']; // 允许选择所有文件
      
      documentPicker.select(options, (err: Error, result: string[]) => {
        if (err) {
          // 如果失败，使用默认路径
          const context = getContext();
          this.rootDirectory = "/storage/media/100/local/files/Docs";
          return;
        }
        if (result && result.length > 0) {
          // 获取选中文件的父目录
          const selectedPath = result[0];
          const lastSlash = selectedPath.lastIndexOf('/');
          if (lastSlash > 0) {
            this.rootDirectory = selectedPath.substring(0, lastSlash);
          } else {
            this.rootDirectory = selectedPath;
          }
        }
      });
    } catch (e) {
      // 如果出错，使用默认路径
      const context = getContext();
      this.rootDirectory = "/storage/media/100/local/files/Docs";
    }
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
      const err: Error = error as Error;
      console.error('Failed to get IP address:', err.message);
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
      const err: Error = error as Error;
      console.error('Failed to get WiFi info:', err.message);
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
        allowAnonymous: this.allowAnonymous,
        rootDirectory: this.rootDirectory,
        serverIp: this.deviceIpAddress
      };
      
      const result = await this.serverManager.startServer(config);
      if (result) {
        this.statusMessage = `FTP Server started on port ${this.serverPort}`;
        this.isServerRunning = true;
      } else {
        this.statusMessage = 'Failed to start FTP Server';
      }
    } catch (error) {
      const err: Error = error as Error;
      this.statusMessage = `Error starting server: ${err.message}`;
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
      const err: Error = error as Error;
      this.statusMessage = `Error stopping server: ${err.message}`;
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

        // Root Directory Configuration
        Row({
          space: 10
        }) {
          Text('Root Dir:')
            .width('30%')
            .fontSize(16)
            .alignSelf(ItemAlign.Center)
          
          Button(this.rootDirectory || 'Select Folder')
            .width('70%')
            .height(40)
            .fontSize(14)
            .borderRadius(8)
            .border({ width: 1, color: '#DDDDDD' })
            .backgroundColor('#FFFFFF')
            .onClick(() => {
              this.selectRootDirectory();
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

      Text(`Root Directory: ${this.rootDirectory}`)
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