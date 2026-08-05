#!/usr/bin/env python3
"""自动递增应用版本号：pubspec.yaml + lib/config.dart + web/index.html 缓存戳。"""
import re
from pathlib import Path

ROOT = Path(__file__).parent.parent  # android_app


def main():
    pubspec = ROOT / 'pubspec.yaml'
    config = ROOT / 'lib' / 'config.dart'
    index_html = ROOT / 'web' / 'index.html'

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

    # 同步更新 web/index.html 的缓存戳，避免 CDN/浏览器回退到旧版本
    if index_html.exists():
        html = index_html.read_text(encoding='utf-8')
        html = re.sub(r"(href=\"manifest\.json|href=\"favicon\.png|href=\"icons/Icon-192\.png|src=\"flutter_bootstrap\.js)\?v=\d+\.\d+\.\d+",
                      rf"\1?v={new_ver}", html)
        index_html.write_text(html, encoding='utf-8')

    print(f'Bumped version to {new_ver}+{build}')


if __name__ == '__main__':
    main()
