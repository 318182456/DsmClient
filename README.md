# DsmClient

DsmClient 是面向群晖 Synology DSM 的 Flutter 移动客户端，计划基于现有代码重新开发，逐步梳理功能、更新界面并改善维护体验。

本项目以 [群晖助手 DSM helper](https://gitee.com/apaipai/dsm_helper) 为起点，保留原作者版权及开源许可。当前处于重新开发的初始阶段，现有实现及兼容性需要逐项验证。

## 项目状态

- 应用名称：`DsmClient`；Dart 包名：`dsm_client`。
- 已导入原项目代码，保留现有功能作为后续开发基础。
- 尚未完成完整编译、设备验证及 DSM 版本兼容性测试。
- 已移除广告 SDK、广告展示、免广告付费及兑换入口，启动不再检查广告权益。
- 暂未发布 DsmClient 安装包；原项目的安装包、交流群和商业服务不作为本项目的发布渠道。

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

## 重新开发方向

以下为初步规划，均为待开展事项，可随开发调整。

- [ ] 复现开发环境，跑通 Android / iOS 基础构建。
- [ ] 梳理 NAS 登录、会话管理、网络请求和错误处理。
- [ ] 建立 DSM 6 / DSM 7 功能与接口兼容性清单。
- [ ] 优先验证登录、控制台、文件管理及下载等核心流程。
- [ ] 重新设计界面、导航和主题，统一交互风格。
- [ ] 评估 Flutter、Dart 和第三方依赖升级，分阶段迁移。
- [x] 移除穿山甲广告 SDK、开屏/激励视频、免广告付费及兑换服务。
- [ ] 清理或替换继承的反馈及更新服务配置。
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

## GitHub Actions

[Android CI](https://github.com/318182456/DsmClient/actions/workflows/android.yml) 在推送到 `main`、向 `main` 提交 Pull Request 或手动运行时触发。

工作流使用 Flutter 3.7.12 和 JDK 11，安装依赖后构建 ARM64 debug APK。成功后可在对应运行的 Artifacts 中下载 `DsmClient-debug-arm64` 成果，保留 7 天。

CI 自动生成临时测试签名，无需配置签名 Secrets。每次运行的签名不同，安装时可能需要先卸载旧测试包；该成果用于开发验证。正式签名、Release 发布及 iOS 构建尚未接入。

当前测试目录仅有占位入口，工作流以 APK 构建作为检查，尚未覆盖设备上的功能测试。

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
test/             测试目录（当前仅有占位入口）
```

## 开发注意事项

继承的代码仍包含原项目的服务地址、品牌素材及第三方集成配置。重新开发时需逐项确认用途，替换为自己的配置并验证相关数据流；当前尚未完成这些迁移。

问题反馈和开发讨论使用本仓库的 [Issues](https://github.com/318182456/DsmClient/issues)。

## 来源与许可证

- 原项目：[群晖助手 DSM helper](https://gitee.com/apaipai/dsm_helper)。
- 当前仓库：[318182456/DsmClient](https://github.com/318182456/DsmClient)。
- 项目沿用 [Apache License 2.0](LICENSE)，保留原作者及贡献者版权声明。
- 第三方依赖、框架与素材遵循各自许可证，发布前需核对相关许可要求。
