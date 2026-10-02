"""Reject accidental source, credential and debug-data inclusion before release.

This is a limited packaging check, not a complete secret or vulnerability scan.
Only entry names and finding types are printed, never matching secret values.
"""

import argparse
from pathlib import PurePosixPath
import re
import zipfile


SECRET_PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "GitHub token": rb"\b(?:ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,})\b",
    "Google API key": rb"AIza[0-9A-Za-z_-]{35}",
    "Alibaba access key": rb"\bLTAI[A-Za-z0-9]{12,24}\b",
}


def inspect_apk(path):
    findings = []
    with zipfile.ZipFile(path) as apk:
        app_libraries = 0
        for entry in apk.infolist():
            if entry.is_dir():
                continue
            name = PurePosixPath(entry.filename.lower())
            if (
                name.suffix in {".dart", ".jks", ".keystore", ".pem", ".p12", ".pfx", ".symbols", ".map"}
                or name.name.endswith(".map.json")
                or name.name in {"key.properties", "kernel_blob.bin", "vm_snapshot_data", "isolate_snapshot_data"}
                or name.name == ".env"
                or name.name.startswith(".env.")
                or ".git" in name.parts
            ):
                findings.append((entry.filename, "source, signing, environment or debug file"))
            content = apk.read(entry)
            for label, pattern in SECRET_PATTERNS.items():
                if re.search(pattern, content):
                    findings.append((entry.filename, label))
            if name.parts[0] == "lib" and name.name == "libapp.so":
                app_libraries += 1
                if b"package:antkeep/" in content:
                    findings.append((entry.filename, "readable AntKeep source paths; check obfuscation and split-debug-info"))
        if not app_libraries:
            findings.append(("APK", "missing compiled Dart release library"))
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    args = parser.parse_args()
    findings = inspect_apk(args.apk)
    for entry, reason in findings:
        print(f"FAIL: {entry}: {reason}")
    if findings:
        raise SystemExit(1)
    print("APK packaging checks passed (not a complete security audit).")


if __name__ == "__main__":
    main()
