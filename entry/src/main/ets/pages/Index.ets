import { FtpServerManager } from '../ftp/FtpServerManager';
import { FtpConfigOptions } from '../ftp/FtpConfig';
import { LogLevel } from '../ftp/FtpLogger';
import wifiManager from '@ohos.wifiManager';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { fileShare, fileUri } from '@kit.CoreFileKit';

// 预设目录选项
interface DirOption {
  label: string;
  path: string;
}

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
  @State showDirPicker: boolean = false;
  @State dirOptions: DirOption[] = [];

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
    this.initDirOptions();
    this.startStatusTimer();
  }

  aboutToDisappear() {
    this.stopStatusTimer();
    this.manager.setLogCallback(null);
  }

  private initDirOptions(): void {
    const options: DirOption[] = [];
    try {
      const ctx = getContext();
      options.push({ label: '应用文件目录', path: ctx.filesDir });
      options.push({ label: '应用缓存目录', path: ctx.cacheDir });
      options.push({ label: '应用临时目录', path: ctx.tempDir });

      this.dirOptions = options;
      if (options.length > 0) {
        this.rootDirectory = options[0].path;
      }
    } catch (e) {
      this.rootDirectory = '/data/storage/el2/base/files';
      this.dirOptions = [{ label: '默认目录', path: this.rootDirectory }];
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

  private selectFolderViaPicker(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FOLDER;

      documentPicker.select(options).then((result: Array<string>) => {
        if (result && result.length > 0) {
          const uri = result[0];
          console.info('[FTP] Picker selected URI:', uri);

          // 持久化读写权限
          const policies: Array<fileShare.PolicyInfo> = [{
            uri: uri,
            operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
          }];

          fileShare.persistPermission(policies).then(() => {
            console.info('[FTP] Permission persisted');
            return fileShare.activatePermission(policies);
          }).then(() => {
            console.info('[FTP] Permission activated');
          }).catch((err: Error) => {
            console.error('[FTP] Permission error:', err.message);
          }).finally(() => {
            // 将 URI 转为真实沙箱路径
            try {
              const fuObj = new fileUri.FileUri(uri);
              const realPath = fuObj.path;
              console.info('[FTP] URI -> realPath:', realPath);
              this.rootDirectory = realPath;
            } catch (e) {
              console.error('[FTP] fileUri convert failed, using URI directly:', e);
              this.rootDirectory = uri;
            }
          });
        }
      }).catch((err: Error) => {
        console.error('[FTP] Folder picker error:', err.message);
      });
    } catch (e) {
      console.error('[FTP] Folder picker not supported:', e);
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

  // 获取目录的简短显示名
  private getDirDisplayName(): string {
    for (const opt of this.dirOptions) {
      if (opt.path === this.rootDirectory) {
        return opt.label;
      }
    }
    // 自定义路径，显示最后两级
    const parts = this.rootDirectory.split('/');
    if (parts.length >= 2) {
      return '.../' + parts.slice(-2).join('/');
    }
    return this.rootDirectory;
  }

  build() {
    Stack() {
      Column() {
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

          // 根目录选择
          Row() {
            Text('根目录').width('25%').fontSize(14)
            Row() {
              Text(this.getDirDisplayName())
                .fontSize(13)
                .fontColor('#333')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('▼')
                .fontSize(12)
                .fontColor('#999')
                .margin({ left: 4 })
            }
            .width('75%')
            .height(36)
            .padding({ left: 10, right: 10 })
            .backgroundColor('#FFF')
            .borderRadius(6)
            .border({ width: 1, color: '#DDD' })
            .onClick(() => {
              if (!this.isRunning) {
                this.showDirPicker = true;
              }
            })
          }

          // 显示完整路径
          Text(this.rootDirectory)
            .fontSize(11)
            .fontColor('#999')
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

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

      // 目录选择弹窗
      if (this.showDirPicker) {
        Column() {
          // 遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#00000060')
            .onClick(() => { this.showDirPicker = false; })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })

        Column() {
          Text('选择根目录')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 16 })

          // 预设目录列表
          List() {
            ForEach(this.dirOptions, (opt: DirOption) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(opt.label)
                      .fontSize(15)
                      .fontColor('#333')
                    Text(opt.path)
                      .fontSize(11)
                      .fontColor('#999')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.rootDirectory === opt.path) {
                    Text('✓')
                      .fontSize(18)
                      .fontColor('#52C41A')
                      .fontWeight(FontWeight.Bold)
                  }
                }
                .width('100%')
                .padding({ top: 12, bottom: 12, left: 16, right: 16 })
                .backgroundColor(this.rootDirectory === opt.path ? '#F6FFED' : '#FFF')
                .borderRadius(8)
                .onClick(() => {
                  this.rootDirectory = opt.path;
                  this.showDirPicker = false;
                })
              }
            })
          }
          .width('100%')
          .divider({ strokeWidth: 1, color: '#F0F0F0' })

          // 提示
          Text('以下目录需要通过系统授权才能访问：')
            .fontSize(12)
            .fontColor('#999')
            .margin({ top: 14, bottom: 6 })
            .alignSelf(ItemAlign.Start)

          // 快捷授权按钮：Download
          Button('📥 授权 Download 目录')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#E6F7FF')
            .fontColor('#1890FF')
            .borderRadius(8)
            .onClick(() => {
              this.showDirPicker = false;
              this.selectFolderViaPicker();
            })

          // 快捷授权按钮：图片
          Button('🖼 授权 图片/相册 目录')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#FFF7E6')
            .fontColor('#FA8C16')
            .borderRadius(8)
            .margin({ top: 6 })
            .onClick(() => {
              this.showDirPicker = false;
              this.selectFolderViaPicker();
            })

          // 通用文件夹选择
          Button('📁 选择其他文件夹...')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#F0F0F0')
            .fontColor('#333')
            .borderRadius(8)
            .margin({ top: 6 })
            .onClick(() => {
              this.showDirPicker = false;
              this.selectFolderViaPicker();
            })

          Button('取消')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .borderRadius(8)
            .margin({ top: 8 })
            .onClick(() => { this.showDirPicker = false; })
        }
        .width('85%')
        .padding(20)
        .backgroundColor('#FFF')
        .borderRadius(16)
        .shadow({ radius: 20, color: '#00000030' })
        .position({ x: '7.5%', y: '20%' })
      }
    }
    .width('100%')
    .height('100%')
  }
}
