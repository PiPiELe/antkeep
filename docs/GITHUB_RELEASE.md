# GitHub APK 发布

Android 正式包由 GitHub Actions 生成并附加到 GitHub Release。成功发布后，用户可始终使用下面这个链接下载最新稳定版：

```text
https://github.com/PiPiELe/antkeep/releases/latest/download/AntKeep.apk
```

对应的 SHA-256 校验文件：

```text
https://github.com/PiPiELe/antkeep/releases/latest/download/AntKeep.apk.sha256
```

## 版本约定

版本仅使用 `major.minor.patch`，例如 `1.0.3`、`1.0.4`，`pubspec.yaml` 不再添加 `+x`。
Android 自动按每段两位生成内部 `versionCode`：`major * 10000 + minor * 100 + patch`，
例如 `1.0.3 → 010003 → 10003`、`1.1.0 → 010100 → 10100`；各段范围为 0–99，
某段达到 99 后向前一段进位。新包必须提高版本号，不单独维护构建号。
主线本地 APK 命名为 `AntKeep-1.0.3.apk`，本地标签为 `antkeep-1.0.3-main`。
本地打包不自动推送标签或发布 GitHub Release。

## 正式环境更新接口

主线正式 APK 必须配置 `ANTKEEP_API_BASE_URL=https://pipiele.xyz`：

```bash
flutter build apk --release --dart-define=ANTKEEP_API_BASE_URL=https://pipiele.xyz
```

App 通过 `https://pipiele.xyz/api/public/app-update/android` 匿名检查更新，在线版与离线版均适用。
后台必须发布更新策略后才会返回可用更新；未发布时返回 `APP_UPDATE_NOT_PUBLISHED`。
此参数也用于公开资料接口，不启用账号与签到功能。不要将 APK 下载站 `pipicbb.xyz` 当作 API 地址。
构建验收应确认 APK 内包含正式域名；未带此参数的构建不能作为主线正式包交付。

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

1. 将 `pubspec.yaml` 的 `version` 更新为要发布的版本号，例如 `1.0.3`，并合入 `main`。
2. 在该提交创建并推送对应的不可变标签，例如 `v1.0.3`。
3. 标签推送会自动执行 **Release Android APK**；它构建已签名的 release APK、生成 SHA-256，然后创建或更新同标签的 GitHub Release。
4. 在 Release 页面下载并安装 `AntKeep.apk` 做真机验证后，再对外公布上面的固定下载链接。

如果需要重试已存在的标签，在 Actions 页面手动运行 **Release Android APK**，并填写该标签名。工作流只接受已经存在的标签，避免把任意工作分支误发布为正式包。

GitHub Release 的直接下载只提供文件分发；Android 安装时仍应核对签名与 SHA-256，且真机安装验证、商店发布是独立步骤。
