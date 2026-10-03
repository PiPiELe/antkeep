# GitHub 上传 APK 到服务器

Actions → **Deliver Android APK to server**，在 `main` 上手动运行。

- `operation=check` 是默认值，只验证 SSH 账号、主机密钥与目标目录，不构建、不上传。
- `operation=upload` 需要已有不可变 tag；主线要求 tag 属于 `release`，渠道要求属于 `release-xiaomi` / `release-vivo`。缺分支会失败，不回退到开发分支。
- 构建前执行 analyze/test，锁文件必须不变；使用仓库签名 Secrets，校验包名、版本、非 debug 和 APK 签名，再上传并通过 HTTPS 下载核对 SHA-256。
- 主线名 `AntKeep-1.0.0-3.apk`，渠道名 `AntKeep-1.0.0-3-xiaomi.apk` / `...-vivo.apk`。同名文件拒绝覆盖；已上传但公网验证失败时先核查现有文件，不盲目重新发布。
- 此工作流只上传版本化文件；不修改下载首页、后台更新策略或 GitHub latest，也不提交商店。

Repository Actions Secrets：`SERVER_SSH_KEY`（专用 `antkeep-apk-ci` 私钥）、`SERVER_KNOWN_HOSTS`（经管理员可信 SSH 会话确认的主机公钥）。Android 另需已有发布证书的 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEYSTORE_PASSWORD`。勿生成另一套 Android 签名。

专用 SSH 账号只能调用服务端强制命令 `check` / `upload`；不能登录交互 shell、转发端口或读取后台数据库配置。服务器接收器由后台仓库 `scripts/ci/server_receive.py` 维护，root 安装，修改它需要独立运维发布。

现有 **Release Android APK** 工作流保持原行为，推送 `v*` 仍会发布 GitHub Release；它不会自动调用此手动上传工作流。服务器 TCP 22 必须允许所用 GitHub runner 网络到达；若受安全组限制，使用有固定出口的 runner，不自动扩大安全组。
