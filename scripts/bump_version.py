#!/usr/bin/env python3
"""自动递增应用版本号：pubspec.yaml + lib/config.dart。"""
import re
from pathlib import Path

ROOT = Path(__file__).parent.parent  # android_app


def main():
    pubspec = ROOT / 'pubspec.yaml'
    config = ROOT / 'lib' / 'config.dart'

    text = pubspec.read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', text, re.M)
    if not m:
        raise SystemExit('pubspec.yaml 中未找到 version 行')
    major, minor, patch, build = map(int, m.groups())
    patch += 1
    build += 1
    new_ver = f'{major}.{minor}.{patch}'
    text = text[:m.start()] + f'version: {new_ver}+{build}' + text[m.end():]
    pubspec.write_text(text, encoding='utf-8')

    cfg = config.read_text(encoding='utf-8')
    cm = re.search(r"const String kAppVersion = '(\d+\.\d+\.\d+)';", cfg)
    if not cm:
        raise SystemExit('config.dart 中未找到 kAppVersion')
    cfg = cfg[:cm.start()] + f"const String kAppVersion = '{new_ver}';" + cfg[cm.end():]
    config.write_text(cfg, encoding='utf-8')

    print(f'Bumped version to {new_ver}+{build}')


if __name__ == '__main__':
    main()
