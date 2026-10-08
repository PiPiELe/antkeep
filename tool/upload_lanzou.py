#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["playwright==1.63.0"]
# ///
"""Upload one APK to an existing LanZou folder using a dedicated Chrome profile."""

import argparse
import hashlib
import os
from pathlib import Path
import sys
import time
from urllib.parse import parse_qs, urlsplit
import zipfile

HOME_URL = "https://pc.woozooo.com/mydisk.php"
PROFILE = Path.home() / ".local/share/antkeep/lanzou-browser"


class UploadError(Exception):
    pass


def inspect_apk(path):
    path = path.expanduser().resolve()
    if not path.is_file() or path.suffix.lower() != ".apk":
        raise UploadError("请指定一个存在的 .apk 文件。")
    if any(ord(c) < 32 for c in path.name):
        raise UploadError("文件名不能包含控制字符。")
    try:
        with zipfile.ZipFile(path) as archive:
            if "AndroidManifest.xml" not in archive.namelist():
                raise UploadError("文件缺少 AndroidManifest.xml，不是有效 APK。")
    except zipfile.BadZipFile as exc:
        raise UploadError("文件不是有效的 APK/ZIP。") from exc
    with path.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    return path, path.stat().st_size, digest


def is_response(response, endpoint, task=None):
    url = urlsplit(response.url)
    if url.scheme != "https" or url.hostname != "pc.woozooo.com":
        return False
    if url.path != endpoint or response.request.method != "POST":
        return False
    return task is None or parse_qs(response.request.post_data or "").get("task") == [task]


def response_data(response, *, listing=False):
    if response.status != 200:
        raise UploadError(f"蓝奏云返回 HTTP {response.status}，请在网页检查登录状态。")
    try:
        data = response.json()
    except Exception as exc:
        raise UploadError("蓝奏云未返回预期数据；请在网页完成登录或验证后重试。") from exc
    if not isinstance(data, dict):
        raise UploadError("蓝奏云响应格式发生变化。")
    status = str(data.get("zt", ""))
    if status == "9":
        raise UploadError("登录已失效，请重新运行 --login。")
    if listing and status == "2" and data.get("text") in (None, [], ""):
        return []
    if status != "1":
        raise UploadError("蓝奏云没有确认成功，请查看网页提示；脚本不会自动重传。")
    entries = data.get("text")
    if not isinstance(entries, list) or any(not isinstance(x, dict) for x in entries):
        raise UploadError("蓝奏云文件列表格式发生变化。")
    return entries


def open_folder(page, folder):
    page.goto(HOME_URL, wait_until="domcontentloaded")
    frame = page.frame_locator("iframe#mainframe")
    target = frame.locator("#sub_folder_list").get_by_text(folder, exact=True)
    try:
        target.wait_for(state="visible", timeout=15000)
    except Exception as exc:
        raise UploadError(f"未找到根目录下的文件夹 {folder}；请先运行 --login 并检查目录。") from exc
    if target.count() != 1:
        raise UploadError(f"存在多个同名文件夹 {folder}，请在网页先消除歧义。")
    with page.expect_response(lambda r: is_response(r, "/doupload.php", "5")) as pending:
        target.click()
    entries = response_data(pending.value, listing=True)
    frame.locator("#f_tp").get_by_text(folder, exact=True).wait_for(state="visible")
    return frame, entries


def all_entries(page, frame, entries):
    """Scan every page: an older release can be beyond the initial file list."""
    seen = set()
    for _ in range(1000):
        if not entries:
            return
        for entry in entries:
            file_id = str(entry.get("id", ""))
            if not file_id or file_id in seen:
                raise UploadError("文件列表分页异常，已停止以避免重复上传。")
            seen.add(file_id)
            yield entry
        more = frame.get_by_text("显示更多文件", exact=True)
        if not more.is_visible():
            return
        with page.expect_response(lambda r: is_response(r, "/doupload.php", "5")) as pending:
            more.click()
        entries = response_data(pending.value, listing=True)
    raise UploadError("文件列表超过扫描上限，已停止。")


def find_file(page, frame, entries, name, file_id=None):
    for entry in all_entries(page, frame, entries):
        if entry.get("name_all", entry.get("name")) == name:
            if file_id is None or str(entry.get("id")) == file_id:
                return entry
    return None


def upload(page, frame, apk, timeout):
    responses = []

    def collect(response):
        if is_response(response, "/html5up.php"):
            responses.append(response)

    page.on("response", collect)
    try:
        picker = frame.locator('#filePicker input[type="file"]')
        if not frame.get_by_text("点击选择文件", exact=True).is_visible():
            frame.get_by_role("link", name="上传文件", exact=True).click()
        picker.set_input_files(str(apk))
        deadline = time.monotonic() + timeout
        next_status = time.monotonic() + 30
        started = False
        while time.monotonic() < deadline:
            if responses:
                entries = response_data(responses[0])
                if len(entries) != 1 or not entries[0].get("id"):
                    raise UploadError("上传响应缺少唯一文件 ID，请在网页检查结果。")
                return str(entries[0]["id"])
            # Some versions start automatically; others expose a start button.
            start = frame.get_by_text("开始上传", exact=True)
            if not started and start.is_visible():
                start.click()
                started = True
            if time.monotonic() >= next_status:
                print("正在等待蓝奏云确认上传结果…", flush=True)
                next_status = time.monotonic() + 30
            page.wait_for_timeout(250)
        raise UploadError("等待上传结果超时。文件可能已经上传，请先检查网页，再决定是否重试。")
    finally:
        page.remove_listener("response", collect)


def run(page, args, apk_info):
    if args.login:
        page.goto(HOME_URL, wait_until="domcontentloaded")
        print("请在新打开的 Chrome 窗口登录蓝奏云；验证码由你手动完成。")
        input("看到“我的文件”后，回到这里按回车：")
    frame, entries = open_folder(page, args.folder)
    if apk_info is None:
        print(f"登录和目标目录检查通过：{args.folder}")
        return
    apk, _, digest = apk_info
    duplicate = find_file(page, frame, entries, apk.name)
    if duplicate:
        raise UploadError(f"目标目录已有同名文件 {apk.name}，未上传。请核对版本或修改本地文件名。")
    if args.check:
        print(f"预检查通过：可上传到 {args.folder}；本次未上传。")
        return
    print(f"上传到 {args.folder}：{apk.name}", flush=True)
    file_id = upload(page, frame, apk, args.timeout)
    # A successful response alone is insufficient: read the persisted directory again.
    frame, entries = open_folder(page, args.folder)
    if not find_file(page, frame, entries, apk.name, file_id):
        raise UploadError("服务端已响应上传，但刷新后未找到对应文件 ID 和完整文件名。请检查网页，不要盲目重传。")
    print(f"上传成功，刷新目录已确认：{apk.name}（文件 ID：{file_id}）")
    print(f"本地 SHA-256：{digest}（蓝奏云未提供远端哈希校验）")


def main():
    parser = argparse.ArgumentParser(description="将指定 APK 上传到蓝奏云 antKeep 文件夹。")
    parser.add_argument("apk", nargs="?", type=Path, help="APK 文件路径，含空格时加引号")
    parser.add_argument("--folder", default="antKeep", help="根目录下的现有文件夹，默认 antKeep")
    parser.add_argument("--login", action="store_true", help="打开独立浏览器手动登录，仅登录，不上传")
    parser.add_argument("--check", action="store_true", help="检查登录、目录和重名文件，不上传")
    parser.add_argument("--dry-run", action="store_true", help="仅检查本地 APK，不启动浏览器")
    parser.add_argument("--timeout", type=int, default=900, help="等待上传结果的秒数，默认 900")
    args = parser.parse_args()
    if args.login and (args.apk or args.check or args.dry_run):
        parser.error("--login 请单独使用，不接受 APK、--check 或 --dry-run。")
    if not args.login and not args.check and args.apk is None:
        parser.error("请提供 APK 路径，或使用 --login / --check。")
    if args.dry_run and args.apk is None:
        parser.error("--dry-run 需要 APK 路径。")
    if args.timeout <= 0 or not args.folder.strip():
        parser.error("timeout 必须大于 0，folder 不能为空。")
    try:
        apk_info = inspect_apk(args.apk) if args.apk else None
        if apk_info:
            apk, size, digest = apk_info
            print(f"APK：{apk}\n大小：{size / 1024 / 1024:.1f} MiB\nSHA-256：{digest}")
        if args.dry_run:
            print("本地检查通过，未连接蓝奏云。")
            return 0
        try:
            from playwright.sync_api import sync_playwright, Error as BrowserError
        except ImportError as exc:
            raise UploadError("缺少 Playwright。请用 uv run tool/upload_lanzou.py 运行（会自动安装依赖）。") from exc
        os.umask(0o077)
        PROFILE.mkdir(parents=True, exist_ok=True, mode=0o700)
        PROFILE.chmod(0o700)
        with sync_playwright() as playwright:
            try:
                context = playwright.chromium.launch_persistent_context(
                    str(PROFILE), channel="chrome", headless=False,
                    accept_downloads=False, chromium_sandbox=True,
                    ignore_default_args=["--password-store=basic", "--use-mock-keychain"],
                )
                try:
                    page = context.pages[0] if context.pages else context.new_page()
                    page.set_default_timeout(20000)
                    run(page, args, apk_info)
                finally:
                    context.close()
            except BrowserError as exc:
                # Raw browser logs can contain page data; keep diagnostics scoped.
                raise UploadError("浏览器操作失败。请确认已安装 Chrome、没有另一份上传脚本正在运行；登录失效用 --login。若已开始上传，先在网页核对结果。") from exc
        return 0
    except (UploadError, OSError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("已中止；若已开始上传，请在网页核对结果。", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
