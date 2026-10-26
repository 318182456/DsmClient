# DsmClient

<img src="assets/logo.png" width="112" alt="DsmClient 图标" />

DsmClient 是面向群晖 Synology DSM 的 Flutter 移动客户端，计划基于现有代码重新开发，逐步梳理功能、更新界面并改善维护体验。

本项目以 [群晖助手 DSM helper](https://gitee.com/apaipai/dsm_helper) 为起点，保留原作者版权及开源许可。当前处于重新开发的初始阶段，现有实现及兼容性需要逐项验证。

## 项目状态

- 应用名称：`DsmClient`；Dart 包名：`dsm_client`。
- 已导入原项目代码，保留现有功能作为后续开发基础。
- 当前适配目标为 DSM 7.4.1；基础协议与套件发现已进行 NAS 只读验证，移动端完整功能仍需逐项验证。
- 已移除广告 SDK、广告展示、免广告付费及兑换入口，启动不再检查广告权益。
- Android 开发测试版通过 [GitHub Releases](https://github.com/318182456/DsmClient/releases) 分发。原项目渠道不作为本项目的发布渠道。

## 现有功能基础

以下是现有代码涵盖的模块，不代表已在 DsmClient 中验证通过。

| 模块 | 范围 |
| --- | --- |
| 登录与连接 | NAS 连接、账号管理与认证 |
| 控制台 | 系统状态、存储、资源监控、通知及快捷入口 |
| 文件管理 | File Station 浏览、上传下载、搜索、分享及文件操作 |
| 系统管理 | 控制面板、用户、共享文件夹、任务计划、日志及套件管理 |
| 套件 | Docker、Virtual Machine Manager、Download Station 等 |
| 媒体 | 照片浏览、音视频播放及本地播放器插件 |
| 工具与设置 | SSH 终端、主题设置及相册备份相关代码 |

## DSM 7 与 NAS 应用

- 登录前查询 `SYNO.API.Info`，使用 NAS 返回的认证路径及兼容版本；支持 OTP 和 CSRF 会话令牌。
- 请求按连接地址和会话 ID 隔离令牌，切换账号时恢复相应会话，上传与组合请求使用已发现的版本范围。
- 识别 `DSM 7.4.1-90080 Update 1` 等版本格式，DSM 7 小版本沿用对应界面资源。
- 主菜单新增“NAS 应用”：动态发现账号有权查看的全部已安装套件与容器，支持搜索、状态和版本查看。
- File Station、Photos、Container Manager 与存储管理器可进入现有原生页面；其他套件按 NAS 返回的桌面注册信息打开 DSM 网页界面。
- Drive 可分别打开文件、管理控制台和 ShareSync；Hyper Backup、Cloud Sync、Audio Station、Tailscale 等使用对应 DSM 入口。
- Node.js、Python、Git 等后台组件保留版本、状态和套件中心入口，不为它们创建虚构的网页功能。
- 所有容器均可进入详情页面；可按当前 NAS 保存各容器的网页地址，通过系统浏览器访问，网页应用自行认证。

网页入口复用与完整原生客户端属于不同支持范围。当前未为所有套件及容器重写独立的原生业务界面，也未验证全部业务操作。设备、账号权限和已安装套件会影响可用功能。

认证流程参考 [Synology DSM Login Web API Guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf)。

## 图标

应用使用深蓝背景、双盘位 NAS 和青绿色连接环的独立图标，主图为 `assets/logo.png`。Android 提供各密度图标、自适应图标及 Android 13 单色主题图标；iOS 提供完整 AppIcon 尺寸及启动图资源。

## 重新开发方向

以下为初步规划，均为待开展事项，可随开发调整。

- [ ] 复现开发环境，跑通 Android / iOS 基础构建。
- [ ] 梳理 NAS 登录、会话管理、网络请求和错误处理。
- [ ] 建立 DSM 6 / DSM 7 功能与接口兼容性清单。
- [ ] 优先验证登录、控制台、文件管理及下载等核心流程。
- [ ] 重新设计界面、导航和主题，统一交互风格。
- [ ] 评估 Flutter、Dart 和第三方依赖升级，分阶段迁移。
- [x] 移除穿山甲广告 SDK、开屏/激励视频、免广告付费及兑换服务。
- [x] 将更新源切换到本仓库 GitHub Releases，并接入应用内更新。
- [ ] 清理或替换继承的反馈服务配置。
- [ ] 补充核心测试、持续集成及发布流程。

## 开发环境

当前源码沿用的环境基线：

| 项目 | 配置 |
| --- | --- |
| Flutter | `3.7.12`，见 `.fvmrc` |
| Dart | 根目录 SDK 约束为 `>=2.10.0 <3.0.0` |
| JDK | 11（原项目要求） |
| Android | compileSdk / targetSdk 33，minSdk 21 |
| iOS | Podfile 最低版本 12.0；需 macOS、Xcode 和 CocoaPods |

当前包含旧版本插件、Git 依赖及本地 `fplayer` 插件，升级 SDK 前需评估依赖兼容性。

## 获取源码

仓库使用 Git LFS 管理 iOS 播放器框架二进制文件，需先安装 Git LFS。

```sh
git lfs install
git clone https://github.com/318182456/DsmClient.git
cd DsmClient
git lfs pull
flutter pub get
```

使用 Flutter 3.7.12。部分依赖从 GitHub 和 Gitee 拉取，开发环境需能够访问对应仓库。如使用 FVM，可通过 `fvm flutter` 执行 Flutter 命令。

## 运行与构建

### Android

安装 Android SDK，并配置本地 Flutter / Android SDK 路径。当前 `android/app/build.gradle` 会读取 `android/key.properties`，debug 与 release 均使用 release 签名；运行前需自行准备签名配置及密钥。

`android/key.properties` 示例，替换为自己的配置：

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=YOUR_KEYSTORE_PATH
```

`storeFile` 可使用绝对路径或相对于 `android/app` 的路径。签名配置和密钥文件不纳入版本控制。

```sh
flutter devices
flutter run
flutter build apk --release
```

### iOS

在 macOS 上准备 Xcode、CocoaPods 和自己的开发团队及签名配置。执行 `flutter pub get` 后，打开 `ios/Runner.xcworkspace`，检查 Runner 与 Share Extension 的签名配置，再运行或构建。

```sh
flutter build ios --release
```

Android applicationId、iOS Bundle ID、分享扩展关联配置及下载路径目前沿用原项目；后续独立发行时需统一规划应用标识与签名。

## 应用内更新

Android 在进入主页时检查本仓库的 GitHub Releases，也可通过“设置 → 关于 → 检查更新”手动检查。

- 更新从本仓库发布的 `update-arm64.json` 读取版本、安装包大小和 SHA-256，支持开发预发布。
- 只有更高的 Android build number 才会提示更新，手动检查也不会降级或重复安装当前版本。
- 应用内显示下载进度，支持暂停、继续和断点续传；已下载且通过校验的安装包直接复用。
- 安装前核对安装包大小和 SHA-256，然后调用 Android 系统安装器；无需手动前往 GitHub 下载。
- 发布使用固定签名，build number 按 `10000 + GitHub run number` 递增，以便后续覆盖安装。
- 旧的临时签名测试包首次需要卸载后换装固定签名版本，之后即可覆盖更新。Android 仍需用户确认安装，并允许 DsmClient 安装应用。

更新请求使用独立 HTTPS 客户端，不附带 NAS Cookie 或会话令牌。APK 与更新清单在同一个 Release 中就绪后才对外发布。当前未接入 iOS 应用内更新。

## GitHub Actions

[Android CI](https://github.com/318182456/DsmClient/actions/workflows/android.yml) 在推送到 `main`、向 `main` 提交 Pull Request 或手动运行时触发。

工作流使用 Flutter 3.7.12 和 JDK 11。`main` 构建固定签名的 ARM64 release APK，PR 构建隔离的临时签名 debug APK。成功后可在对应运行的 Artifacts 中下载 `DsmClient-arm64` 成果，保留 7 天。`main` 分支成功构建后还会自动创建 `dev-构建序号` 开发测试预发布并附上 APK；PR 构建不发布。

仓库已配置专用固定签名，保存在 Actions Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。不要替换这些密钥，否则新版本无法覆盖安装。PR 不使用这些密钥，也不会发版。iOS 构建尚未接入。

工作流复用 Flutter SDK 与 Pub 缓存，并缓存 Android SDK 平台、构建工具及 Gradle 依赖；Android SDK 安装成功后立即保存，编译失败也能保留该缓存。

协议回归测试不依赖 Flutter 或 NAS，可使用兼容的 Dart 2 SDK 运行：

```sh
dart --no-sound-null-safety test/dsm_compatibility_test.dart
```

另有更新清单和下载回归测试，覆盖版本比较、来源限制、SHA-256 校验、断点续传、暂停和缓存复用：

```sh
dart --no-sound-null-safety test/update_release_test.dart
dart --no-sound-null-safety test/update_download_test.dart
```

工作流执行这些测试和 APK 构建。它们不等同于移动设备上的完整功能测试。

## 代码结构

```text
lib/
  main.dart       应用入口
  pages/          登录、控制台、文件及各套件功能页面
  models/         数据模型
  providers/      状态管理
  themes/         主题
  util/           API、工具方法及通用配置
  widgets/        公共组件
android/          Android 原生工程
ios/              iOS 原生工程与分享扩展
fplayer/          本地播放器插件及原生依赖
assets/           图片、图标等资源
test/             DSM 协议与套件元数据回归测试
```

## 开发注意事项

继承的代码仍包含原项目的反馈等服务地址、品牌素材及第三方集成配置。重新开发时需逐项确认用途，替换为自己的配置并验证相关数据流；当前尚未完成这些迁移。

问题反馈和开发讨论使用本仓库的 [Issues](https://github.com/318182456/DsmClient/issues)。

## 来源与许可证

- 原项目：[群晖助手 DSM helper](https://gitee.com/apaipai/dsm_helper)。
- 当前仓库：[318182456/DsmClient](https://github.com/318182456/DsmClient)。
- 项目沿用 [Apache License 2.0](LICENSE)，保留原作者及贡献者版权声明。
- 第三方依赖、框架与素材遵循各自许可证，发布前需核对相关许可要求。
