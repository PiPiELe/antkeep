import tempfile
import unittest
from pathlib import Path
import zipfile

from check_release_apk import inspect_apk


class ApkPackagingTest(unittest.TestCase):
    def inspect(self, entries):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / "test.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("lib/arm64-v8a/libapp.so", b"compiled-code")
                for name, data in entries.items():
                    archive.writestr(name, data)
            return inspect_apk(apk)

    def test_public_resources_are_allowed(self):
        self.assertEqual(self.inspect({
            "assets/flutter_assets/species.json": b'{"source":"https://antden.net"}',
            "assets/flutter_assets/NOTICES.Z": b"license notices",
            "META-INF/CERT.RSA": b"public signing certificate",
        }), [])

    def test_sensitive_files_are_rejected(self):
        for name in ["key.properties", "release.jks", ".env.production", "lib/main.dart", "app.android-arm64.symbols", "app.map.json", "kernel_blob.bin"]:
            with self.subTest(name=name):
                self.assertTrue(self.inspect({f"assets/{name}": b"data"}))

    def test_secret_in_unexpected_file_is_rejected_without_value(self):
        marker = b"-----BEGIN " + b"PRIVATE KEY-----"
        findings = self.inspect({"assets/innocent.txt": marker})
        self.assertEqual(findings, [("assets/innocent.txt", "private key")])

    def test_checks_each_abi_for_unstripped_app_paths(self):
        findings = self.inspect({"lib/x86_64/libapp.so": b"package:antkeep/main.dart"})
        self.assertTrue(any(entry == "lib/x86_64/libapp.so" for entry, _ in findings))

    def test_debug_only_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / "debug.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("classes.dex", b"dex")
            self.assertEqual(inspect_apk(apk), [("APK", "missing compiled Dart release library")])


if __name__ == "__main__":
    unittest.main()
