"""Offline tests: all browser requests are intercepted, no LanZou account is used."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit
import zipfile

from upload_lanzou import HOME_URL, UploadError, inspect_apk, run

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    sync_playwright = None


class ApkTest(unittest.TestCase):
    def test_rejects_non_apk_and_invalid_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.apk"
            path.write_bytes(b"not an apk")
            with self.assertRaises(UploadError):
                inspect_apk(path)
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("unrelated.txt", "test")
            with self.assertRaises(UploadError):
                inspect_apk(path)


@unittest.skipIf(sync_playwright is None, "Install Playwright to run offline browser tests")
class BrowserTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch(channel="chrome", headless=True, chromium_sandbox=True)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / "AntKeep-测试 1.0.9.apk"
        with zipfile.ZipFile(self.apk, "w") as archive:
            archive.writestr("AndroidManifest.xml", b"test manifest")
        self.files = [{"id": "11", "name_all": "older.apk"}]
        self.upload_count = 0
        self.persist = True
        self.status = 1
        self.list_status = 1
        self.auto_start = False
        self.args = argparse.Namespace(login=False, check=False, folder="antKeep", timeout=3)
        self.context = self.browser.new_context(service_workers="block")
        self.addCleanup(self.context.close)
        self.context.route("**/*", self.route)
        self.page = self.context.new_page()
        self.page.set_default_timeout(2000)

    def route(self, route):
        path = urlsplit(route.request.url).path
        if route.request.url == HOME_URL:
            route.fulfill(content_type="text/html", body='<iframe id="mainframe" src="/fixture"></iframe>')
        elif path == "/fixture":
            self.fixture(route)
        elif path == "/doupload.php":
            pg = int(parse_qs(route.request.post_data)["pg"][0])
            entries = self.files[pg - 1:pg]
            code = self.list_status if entries else 2
            route.fulfill(json={"zt": code, "text": entries})
        elif path == "/html5up.php":
            self.upload_count += 1
            body = route.request.post_data_buffer
            self.assertIn(self.apk.name.encode(), body)
            # Chromium omits file bytes from intercepted post_data_buffer.
            # The fixture hashes the selected File in the browser instead.
            self.assertIn(inspect_apk(self.apk)[2].encode(), body)
            entry = {"id": "99", "name_all": self.apk.name}
            if self.persist and self.status == 1:
                self.files.append(entry)
            route.fulfill(json={"zt": self.status, "text": [entry]})
        else:
            # No real network traffic is allowed, including third-party requests.
            route.abort()

    def fixture(self, route):
        body = r'''<!doctype html><meta charset="utf-8">
<div id="sub_folder_list"><span onclick="enter()">antKeep</span></div>
<div id="f_tp"></div><div id="files"></div>
<span id="more" onclick="listFiles()" hidden>显示更多文件</span>
<a href="javascript:void(0)" onclick="document.querySelector('#picker').hidden=false">上传文件</a>
<div id="picker"><div id="filePicker">点击选择文件<input type="file" onchange="selected()"></div></div>
<button id="start" hidden onclick="send()">开始上传</button>
<script>
let pg = 0;
async function enter() {
  await listFiles();
  document.querySelector('#sub_folder_list').hidden = true;
  document.querySelector('#f_tp').innerHTML = '<span>antKeep</span>';
}
async function listFiles() {
  const response = await fetch('/doupload.php', {method:'POST',
    body:new URLSearchParams({task:'5', folder_id:'123', pg:String(++pg)})});
  const data = await response.json();
  for (const entry of data.text) {
    const name = document.createElement('span'); name.textContent = entry.name_all;
    document.querySelector('#files').append(name);
  }
  document.querySelector('#more').hidden = data.text.length === 0;
}
function selected() {
  if (AUTO_START) send(); else document.querySelector('#start').hidden = false;
}
async function send() {
  document.querySelector('#start').hidden = true;
  const form = new FormData();
  const file = document.querySelector('input').files[0];
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  form.append('fixture_sha256', Array.from(new Uint8Array(digest), x => x.toString(16).padStart(2,'0')).join(''));
  form.append('upload_file', file);
  await fetch('/html5up.php', {method:'POST', body:form});
}
</script>'''.replace("AUTO_START", json.dumps(self.auto_start))
        route.fulfill(content_type="text/html", body=body)

    def execute(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            run(self.page, self.args, inspect_apk(self.apk))
        return output.getvalue()

    def test_upload_then_verify_persisted_file(self):
        self.assertIn("刷新目录已确认", self.execute())
        self.assertEqual(self.upload_count, 1)

    def test_auto_start_variant(self):
        self.auto_start = True
        self.assertIn("刷新目录已确认", self.execute())
        self.assertEqual(self.upload_count, 1)

    def test_duplicate_on_second_page_never_uploads(self):
        self.files.append({"id": "12", "name_all": self.apk.name})
        with self.assertRaisesRegex(UploadError, "同名文件"):
            self.execute()
        self.assertEqual(self.upload_count, 0)

    def test_preflight_never_uploads(self):
        self.args.check = True
        self.assertIn("本次未上传", self.execute())
        self.assertEqual(self.upload_count, 0)

    def test_expired_login_never_uploads(self):
        self.list_status = 9
        with self.assertRaisesRegex(UploadError, "登录已失效"):
            self.execute()
        self.assertEqual(self.upload_count, 0)

    def test_server_rejection_is_not_success(self):
        self.status = 4
        with self.assertRaisesRegex(UploadError, "没有确认成功"):
            self.execute()
        self.assertEqual(self.upload_count, 1)

    def test_success_response_without_persistence_is_not_success(self):
        self.persist = False
        with self.assertRaisesRegex(UploadError, "刷新后未找到"):
            self.execute()
        self.assertEqual(self.upload_count, 1)


if __name__ == "__main__":
    unittest.main()
