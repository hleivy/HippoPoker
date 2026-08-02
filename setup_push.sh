#!/usr/bin/env bash
# 把 android_app 推到你自己的 GitHub 仓库，触发 Actions 自动构建 APK。
# 用法：
#   1) 把下面 GITHUB_USER 改成你的 GitHub 用户名
#   2) 把 REPO_NAME 改成你在 GitHub 新建的空仓库名
#   3) 在 Git Bash 里执行：  bash setup_push.sh
#   4) push 时输入 GitHub 用户名 + Personal Access Token（不是登录密码）
set -e

GITHUB_USER="你的GitHub用户名"
REPO_NAME="poker-android"

cd "$(dirname "$0")"

git init -q 2>/dev/null || true
git add .
git commit -m "init poker android app (CI build ready)" || echo "（无新提交，继续）"
git branch -M main 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
git push -u origin main

echo ""
echo "✅ 已推送。打开 https://github.com/$GITHUB_USER/$REPO_NAME/actions"
echo "   等 Build Android APK 跑完，在 Artifacts 下载 poker-app-release / app-release.apk"
