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
