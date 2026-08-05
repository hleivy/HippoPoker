#!/usr/bin/env python3
"""从产品 logo JPG 生成 Flutter/Web/Android 各尺寸图标。"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent.parent  # android_app
SRC = Path(r'C:/Users/hleiv/.workbuddy/clipboard-images/clipboard-2026-08-03T13-04-44-598Z-e392ffb0.jpg')

TARGETS = {
    # Flutter assets
    'images/app_icon.png': 512,
    # Web
    'web/favicon.png': 128,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
    # Android launcher
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    # APK download page
    '../apk_host/assets/app_icon.png': 192,
}


def main():
    src = Image.open(SRC)
    if src.mode not in ('RGB', 'RGBA'):
        src = src.convert('RGB')

    for rel, size in TARGETS.items():
        out = (ROOT / rel).resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        im = src.resize((size, size), Image.LANCZOS)
        im.save(out, 'PNG', optimize=True)
        print(f'{rel} -> {size}x{size}')

    print('Done.')


if __name__ == '__main__':
    main()
