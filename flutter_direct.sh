#!/usr/bin/env bash
# 直接调用 dart.exe 运行 flutter_tools.snapshot，绕过 Windows .bat 包装
# （Git Bash 下运行 .bat 会丢失 stdout 且以 exit 1 结束，导致 flutter 命令静默失败）
# 注意：dart.exe 是 Windows 程序，必须喂 Windows 原生路径（C:/... 正斜杠格式）。
set -e
unset CDPATH

FLUTTER_WIN="C:/Users/hleiv/WorkBuddy/2026-08-02-19-05-12/_tools/flutter"
export FLUTTER_ROOT="$FLUTTER_WIN"
export FLUTTER_SUPPRESS_ANALYTICS="true"
export PUB_SUMMARY_ONLY="1"

DART="$FLUTTER_WIN/bin/cache/dart-sdk/bin/dart.exe"
PACKAGES="$FLUTTER_WIN/packages/flutter_tools/.dart_tool/package_config.json"
SNAP="$FLUTTER_WIN/bin/cache/flutter_tools.snapshot"

exec "$DART" --packages="$PACKAGES" "$SNAP" "$@"
