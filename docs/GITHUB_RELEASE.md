# GitHub APK 发布

Android 正式包由 GitHub Actions 生成并附加到 GitHub Release。成功发布后，用户可始终使用下面这个链接下载最新稳定版：

```text
https://github.com/PiPiELe/antkeep/releases/latest/download/AntKeep.apk
```

对应的 SHA-256 校验文件：

```text
https://github.com/PiPiELe/antkeep/releases/latest/download/AntKeep.apk.sha256
```

## 首次配置

在仓库 **Settings → Secrets and variables → Actions** 中添加以下 repository secrets。不要提交 keystore、`android/key.properties` 或任何密码。

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 发布 keystore 的 Base64 单行文本 |
| `ANDROID_KEY_ALIAS` | keystore 中的 key alias |
| `ANDROID_KEY_PASSWORD` | key 的密码 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 文件密码 |

在 macOS 上可用下列命令生成 `ANDROID_KEYSTORE_BASE64` 的值；只将输出粘贴到 GitHub Secret，不要保存到仓库：

```bash
base64 -i /absolute/path/to/antkeep-release.jks | tr -d '\n'
```

仓库还需要允许 Actions 写入 Releases：**Settings → Actions → General → Workflow permissions → Read and write permissions**。

## 发布一个版本

1. 将 `pubspec.yaml` 的 `version` 更新为要发布的版本号，例如 `1.0.0+2`，并合入 `main`。
2. 在该提交创建并推送对应的不可变标签，例如 `v1.0.0`。
3. 标签推送会自动执行 **Release Android APK**；它构建已签名的 release APK、生成 SHA-256，然后创建或更新同标签的 GitHub Release。
4. 在 Release 页面下载并安装 `AntKeep.apk` 做真机验证后，再对外公布上面的固定下载链接。

如果需要重试已存在的标签，在 Actions 页面手动运行 **Release Android APK**，并填写该标签名。工作流只接受已经存在的标签，避免把任意工作分支误发布为正式包。

GitHub Release 的直接下载只提供文件分发；Android 安装时仍应核对签名与 SHA-256，且真机安装验证、商店发布是独立步骤。

## 混淆与发布检查

Android release 构建必须同时开启 Dart 混淆与调试信息分离；漏传参数时 Gradle 会拒绝构建，debug 构建不受影响。本地构建示例（符号目录放在仓库外，按版本和源码提交隔离）：

```bash
flutter build apk --release --obfuscate \
  --split-debug-info=/absolute/private/path/version-commit/android-symbols
python3 tool/check_release_apk.py build/app/outputs/flutter-apk/app-release.apk
```

需要在线服务的渠道继续添加该渠道原有的 `--dart-define`；它只适合传服务地址等公开配置，不能用来隐藏私钥、管理员密码或服务端密钥。iOS release 同样应添加 `--obfuscate --split-debug-info=...`，本项目暂未加入 iOS CI 强制检查。

检查器会拒绝误打包的 Dart 源文件、常见签名/环境/符号文件、常见格式的密钥，以及仍带 `package:antkeep/` 路径的 Dart 二进制。它不是完整的密钥检测或安全审计。物种 JSON、图片、接口地址仍可提取；混淆提高逆向分析成本，不能保证源码保密。用户的 ZIP 备份格式和导入导出操作保持不变。

本地生成的符号文件应与对应源码 SHA、版本、APK SHA256 一起保存到私有长期存储；不提交 Git、不附加到公开 Release，也不放进 APK。排查崩溃时选择对应版本和设备 ABI：

```bash
flutter symbolize -i crash.txt -d /absolute/private/path/version-commit/android-symbols/app.android-arm64.symbols
```

CI 当前仅在临时 runner 的 `build/release-symbols` 生成符号，**尚未配置持久保存，任务结束后无法依赖它恢复崩溃栈**。正式采用 CI 混淆发布前，应先确定符号保存方式。拟采用独立高强度密码加密后存入 Actions artifact，仅保存密文，包含源码 SHA 与 APK SHA256；该上传方案待明确授权，不上传明文符号。

公开源码仓库本身可直接提供源码，APK 混淆不改变仓库可见性；如需闭源，应单独核实并处理仓库访问权限。
