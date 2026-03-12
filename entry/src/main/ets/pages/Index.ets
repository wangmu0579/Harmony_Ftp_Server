import { FtpServerManager } from '../ftp/FtpServerManager';
import { FtpConfigOptions } from '../ftp/FtpConfig';
import { LogLevel } from '../ftp/FtpLogger';
import wifiManager from '@ohos.wifiManager';

@Entry
@Component
struct Index {
  @State isRunning: boolean = false;
  @State serverPort: string = '2121';
  @State serverUser: string = 'admin';
  @State serverPassword: string = '123456';
  @State allowAnonymous: boolean = true;
  @State rootDirectory: string = '';
  @State connectionCount: number = 0;
  @State statusMessage: string = 'FTP 服务器已停止';
  @State isLoading: boolean = false;
  @State deviceIp: string = '获取中...';
  @State logs: string[] = [];

  private manager = FtpServerManager.getInstance();
  private updateTimer: number = -1;

  aboutToAppear() {
    this.manager.setLogLevel('debug');
    this.manager.setLogCallback((level: LogLevel, msg: string) => {
      const ts = new Date();
      const time = `${ts.getHours().toString().padStart(2, '0')}:${ts.getMinutes().toString().padStart(2, '0')}:${ts.getSeconds().toString().padStart(2, '0')}`;
      this.logs.push(`[${time}] ${level.toUpperCase()} ${msg}`);
      if (this.logs.length > 200) {
        this.logs = this.logs.slice(-200);
      }
    });
    this.getDeviceIp();
    this.initRootDirectory();
    this.startStatusTimer();
  }

  aboutToDisappear() {
    this.stopStatusTimer();
    this.manager.setLogCallback(null);
  }

  private initRootDirectory(): void {
    try {
      this.rootDirectory = getContext().filesDir;
    } catch (e) {
      this.rootDirectory = '/data/storage/el2/base/files';
    }
  }

  private getDeviceIp(): void {
    try {
      if (wifiManager.isWifiActive()) {
        const info = wifiManager.getIpInfo();
        if (info && info.ipAddress) {
          const ip = info.ipAddress;
          this.deviceIp = `${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}`;
          return;
        }
      }
      this.deviceIp = '未连接WiFi';
    } catch (e) {
      this.deviceIp = '获取失败';
    }
  }

  private startStatusTimer(): void {
    if (this.updateTimer !== -1) return;
    this.updateTimer = setInterval(() => {
      const s = this.manager.getServerStatus();
      this.isRunning = s.isRunning;
      this.connectionCount = s.connectionCount;
    }, 2000);
  }

  private stopStatusTimer(): void {
    if (this.updateTimer !== -1) {
      clearInterval(this.updateTimer);
      this.updateTimer = -1;
    }
  }

  private async startServer(): Promise<void> {
    if (this.isLoading) return;
    this.isLoading = true;
    this.statusMessage = '正在启动...';
    this.logs = [];

    try {
      const port = parseInt(this.serverPort) || 2121;
      const config: FtpConfigOptions = {
        port: port,
        user: this.serverUser,
        password: this.serverPassword,
        allowAnonymous: this.allowAnonymous,
        rootDirectory: this.rootDirectory,
        serverIp: this.deviceIp
      };
      const ok = await this.manager.startServer(config);
      this.isRunning = ok;
      this.statusMessage = ok ? `FTP 服务器运行中 - 端口 ${port}` : '启动失败';
    } catch (error) {
      this.statusMessage = `启动出错: ${(error as Error).message}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async stopServer(): Promise<void> {
    if (this.isLoading) return;
    this.isLoading = true;
    try {
      await this.manager.stopServer();
      this.isRunning = false;
      this.connectionCount = 0;
      this.statusMessage = 'FTP 服务器已停止';
    } catch (error) {
      this.statusMessage = `停止出错: ${(error as Error).message}`;
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 标题
      Text('FTP Server')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 10 })

      // 状态卡片
      Column({ space: 6 }) {
        Row() {
          Circle({ width: 12, height: 12 })
            .fill(this.isRunning ? '#52C41A' : '#FF4D4F')
          Text(this.statusMessage)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 8 })
        }

        Text(`IP: ${this.deviceIp}`)
          .fontSize(14)
          .fontColor('#666')

        if (this.isRunning) {
          Text(`ftp://${this.serverUser}:${this.serverPassword}@${this.deviceIp}:${this.serverPort}`)
            .fontSize(13)
            .fontColor('#1890FF')
            .copyOption(CopyOptions.LocalDevice)

          Text(`活跃连接: ${this.connectionCount}`)
            .fontSize(14)
            .fontColor('#666')
        }
      }
      .width('92%')
      .padding(16)
      .backgroundColor(this.isRunning ? '#F6FFED' : '#FFF7E6')
      .borderRadius(12)

      // 启动/停止按钮
      Button(this.isRunning ? '停止服务器' : '启动服务器')
        .width('60%')
        .height(44)
        .fontSize(16)
        .backgroundColor(this.isRunning ? '#FF4D4F' : '#52C41A')
        .fontColor('#FFF')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ top: 12 })
        .onClick(() => {
          if (this.isRunning) {
            this.stopServer();
          } else {
            this.startServer();
          }
        })

      // 配置区域
      Column({ space: 10 }) {
        Text('服务器配置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)

        Row() {
          Text('端口').width('25%').fontSize(14)
          TextInput({ text: this.serverPort })
            .width('75%').height(36).fontSize(14).borderRadius(6)
            .enabled(!this.isRunning)
            .onChange((v: string) => { this.serverPort = v; })
        }
        Row() {
          Text('用户名').width('25%').fontSize(14)
          TextInput({ text: this.serverUser })
            .width('75%').height(36).fontSize(14).borderRadius(6)
            .enabled(!this.isRunning)
            .onChange((v: string) => { this.serverUser = v; })
        }
        Row() {
          Text('密码').width('25%').fontSize(14)
          TextInput({ text: this.serverPassword })
            .width('75%').height(36).fontSize(14).borderRadius(6)
            .type(InputType.Password)
            .enabled(!this.isRunning)
            .onChange((v: string) => { this.serverPassword = v; })
        }
        Row() {
          Text('根目录').width('25%').fontSize(14)
          Text(this.rootDirectory)
            .width('75%').fontSize(12).fontColor('#666')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row() {
          Text('允许匿名').fontSize(14).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.allowAnonymous })
            .onChange((isOn: boolean) => { this.allowAnonymous = isOn; })
        }
      }
      .width('92%')
      .padding(14)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)
      .margin({ top: 12 })

      // 日志区域
      Column() {
        Row() {
          Text('运行日志').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('清除')
            .fontSize(12).height(28).backgroundColor('#EEE').fontColor('#333')
            .onClick(() => { this.logs = []; })
        }
        .width('100%')
        .margin({ bottom: 6 })

        List() {
          ForEach(this.logs, (log: string) => {
            ListItem() {
              Text(log)
                .fontSize(11)
                .fontColor(log.includes('ERROR') ? '#FF4D4F' : (log.includes('WARN') ? '#FAAD14' : '#333'))
                .fontFamily('monospace')
                .width('100%')
            }
          })
        }
        .layoutWeight(1)
        .backgroundColor('#FAFAFA')
        .borderRadius(6)
        .padding(6)
      }
      .width('92%')
      .layoutWeight(1)
      .margin({ top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF')
  }
}
