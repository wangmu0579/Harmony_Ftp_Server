# Harmony FTP Server

一个运行在鸿蒙（HarmonyOS）手机上的 FTP 服务器应用，使用 ArkTS 开发。

## 功能特性

- **完整 FTP 协议支持**：实现约 30 个标准 FTP 命令
  - 文件操作：`RETR`（下载）、`STOR`（上传）、`APPE`（追加）、`DELE`（删除）、`RNFR`/`RNTO`（重命名）
  - 目录操作：`LIST`、`NLST`、`MLSD`、`CWD`、`CDUP`、`MKD`、`RMD`、`PWD`
  - 传输控制：`PASV`、`EPSV`、`TYPE`、`REST`（断点续传）
  - 文件信息：`SIZE`、`MDTM`
  - 其他：`FEAT`、`OPTS`、`NOOP`、`ABOR`、`SYST`

- **被动模式（PASV）**：自动检测运行环境
  - 模拟器：返回 `127.0.0.1`，配合端口转发使用
  - 真机：返回 WiFi IP 地址

- **用户认证**：支持用户名/密码登录，可开启匿名访问

- **UTF-8 支持**：中文文件名正常显示

- **实时日志**：UI 界面实时显示服务器运行日志

## 截图

> 应用运行后显示服务器状态、连接地址、实时日志

## 环境要求

- DevEco Studio 5.0+
- HarmonyOS API 12+
- 设备：鸿蒙真机或模拟器

## 快速开始

### 真机使用

1. 用 DevEco Studio 编译安装到手机
2. 确保手机已连接 WiFi
3. 打开应用，配置端口（默认 2121）、用户名、密码
4. 点击「启动服务器」
5. 用 FTP 客户端连接：`ftp://<用户名>:<密码>@<WiFi IP>:2121`

### 模拟器使用

1. 安装到模拟器后，执行端口转发脚本：
   ```bash
   ./port_forward.sh
   ```
2. 启动服务器后，FTP 客户端连接：`ftp://admin:123456@127.0.0.1:2121`

## 项目结构

```
entry/src/main/ets/
├── ftp/
│   ├── FtpServer.ets          # TCP 服务器，管理连接
│   ├── FtpServerManager.ets   # 单例管理器
│   ├── FtpConnection.ets      # 单个客户端连接
│   ├── FtpCommandHandler.ets  # FTP 命令处理
│   ├── FtpFileSystem.ets      # 文件系统操作
│   ├── FtpConfig.ets          # 配置
│   ├── FtpLogger.ets          # 日志
│   └── EventEmitter.ts        # 事件系统
└── pages/
    └── Index.ets              # 主界面
```

## 权限说明

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | FTP 网络通信 |
| `ohos.permission.GET_WIFI_INFO` | 获取设备 IP 地址 |
| `ohos.permission.READ_MEDIA` | 读取文件 |
| `ohos.permission.WRITE_MEDIA` | 写入文件 |

## 注意事项

- 应用共享的是**应用沙箱目录**（`filesDir`），受鸿蒙沙箱机制限制，无法直接访问系统相册等目录
- 建议在局域网内使用，不要暴露到公网
- 默认被动端口范围：50000-50100

## License

MIT
