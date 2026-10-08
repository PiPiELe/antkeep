# 蓝奏云快速上传

脚本使用蓝奏云网页上传指定 APK，默认进入根目录下的 `antKeep` 文件夹。
需要本机安装 Google Chrome 和 [uv](https://docs.astral.sh/uv/)。
在 AntKeep 仓库根目录运行以下命令。

首次登录（依赖会由 uv 自动安装）：

```sh
uv run tool/upload_lanzou.py --login
```

在脚本新开的 Chrome 窗口手动登录蓝奏云，看到“我的文件”后回终端按回车。
该窗口独立于日常 Chrome，因此首次需要重新登录。
登录信息保存在本机 `~/.local/share/antkeep/lanzou-browser`，权限仅限当前用户；
不会读取日常 Chrome 的 Cookie，也不需要把密码或 Cookie 复制给脚本。
不要分享或提交此目录。登录失效时重新运行 `--login`。

每次更新后上传：

```sh
uv run tool/upload_lanzou.py "/完整路径/AntKeep-1.0.9.apk"
```

其他用法：

```sh
# 仅核实登录与目标目录
uv run tool/upload_lanzou.py --check
# 上传前预检：登录、目录、全部分页中的同名文件；不会选择文件或上传
uv run tool/upload_lanzou.py "/完整路径/AntKeep-1.0.9.apk" --check
# 不启动浏览器，只检查本地 APK 并输出大小和 SHA-256
python3 tool/upload_lanzou.py "/完整路径/AntKeep-1.0.9.apk" --dry-run
# 更换根目录下的目标文件夹 / 调整等待时间
uv run tool/upload_lanzou.py "/完整路径/AntKeep-1.0.9.apk" --folder "其他目录" --timeout 1200
```

文件名沿用本地 APK 文件名。建议使用包含版本号的名称；存在同名文件时脚本停止，
不覆盖或删除旧包。不自动选择“最新 APK”，避免误传诊断包或渠道包。
上传成功要求蓝奏云返回成功及文件 ID，并且刷新目标目录后找到相同 ID 和完整文件名。
输出的 SHA-256 是本地文件哈希，不能替代远端内容校验。APK 检查仅验证基本结构，
不替代正式打包时的签名、版本和配置验收。

本脚本不更改分享密码、目录权限、应用更新配置，也不自动发布 GitHub Release。
超时/断线后不自动重传：先在网页核实是否已上传。验证码、账号验证需手动完成；
上传大小限制由账号和蓝奏云网页决定。不要同时运行多个脚本进程。

维护依据：页面元素来自蓝奏云文件管理页；响应结构参考
[OpenList 蓝奏云驱动](https://github.com/OpenListTeam/openlist-lanzou-plugin/blob/main/driver.go)
和 [文件列表接口](https://github.com/OpenListTeam/openlist-lanzou-plugin/blob/main/file_api.go)。
浏览器登录持久化采用 [Playwright persistent context](https://playwright.dev/python/docs/api/class-browsertype#browser-type-launch-persistent-context)。
网页结构或响应格式改变时脚本会停止，需要重新核实后调整。

验证记录：8 项离线测试通过，覆盖手动/自动开始上传、第二页重名、只检查、登录失效、
服务端拒绝、响应成功但刷新未找到文件，以及无效 APK。浏览器测试拦截全部网页请求，
不会连接真实账号。另已对本地现有 APK 执行 `--dry-run`；真实账号登录和上传仍待首次运行验收。

复跑测试（需要 Chrome）：

```sh
uv run --python 3.11 --with playwright==1.63.0 python -m unittest discover -s tool -p test_upload_lanzou.py -v
```
