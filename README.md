# 德州扑克安卓客户端（虚拟积分娱乐场）

远程多人德州扑克安卓 App，连接已部署在**微信云托管**上的公网 WebSocket 后端。
纯虚拟积分娱乐，不涉及任何真实货币。

- 后端地址单一配置点：`lib/config.dart` 的 `SERVER_URL`
  （当前指向 `wss://express-b40d-290839-10-1462470907.sh.run.tcloudbase.com`；
   `uncle.ren` 备案完成后改成 `wss://poker.uncle.ren` 即可无缝切换）
- 协议与小程序 / 后端完全一致，服务器权威发牌。

---

## 怎么拿到能装的 APK（你不用装任何开发环境）

### 方式 A：GitHub Actions 自动出包（推荐，零本地安装）

GitHub 免费提供构建机器，你 push 一下代码，它自动帮你编译出 APK，下载即可。

**前置**：一个 GitHub 账号（免费，https://github.com ）。

**步骤**

1. 在 GitHub 网页新建一个**空仓库**（如 `poker-android`），不要勾选 README / .gitignore。
2. 在本目录下，编辑 `setup_push.sh`，把 `GITHUB_USER` 改成你的用户名、`REPO_NAME` 改成你的仓库名。
3. 用 **Git Bash**（装了 Git 就有）在本目录执行：
   ```bash
   bash setup_push.sh
   ```
   首次 push 会让你输入 GitHub 用户名 + **Personal Access Token**
   （不是登录密码；在 GitHub → Settings → Developer settings → PAT 生成一个，勾 `repo` 权限）。
4. push 成功后，打开你的 GitHub 仓库 → **Actions** 标签，等待 `Build Android APK` 跑完（约 3–6 分钟）。
5. 点进该次运行，在 **Artifacts** 区域下载 `poker-app-release`，里面就是 `app-release.apk`。

### 方式 B：本机用 Flutter 构建（如果你已装 Flutter SDK）

```bash
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

### 方式 C：在腾讯云轻量服务器（Ubuntu）上构建（买服务器后备用）

```bash
sudo apt update && sudo apt install -y curl git unzip xz-utils openjdk-17-jdk
# 安装 Flutter（略，按官网 stable 版），然后：
cd android_app
flutter pub get && flutter build apk --release
```

---

## 安装到手机

安卓默认禁止未知来源安装。在手机「设置 → 安全」里允许「未知来源 / 安装未知应用」，
把 `app-release.apk` 传过去点开即可安装。把 APK 发给朋友，他们同样允许未知来源后安装。

## 联调状态

后端已在云托管运行并通过测试（`/rooms` 返回 `{"rooms":[]}`，公网 wss 可建房 / 对局）。
App 装好后直接连，无需额外配置。

## 目录

```
lib/config.dart        服务器地址
lib/game_controller.dart  WebSocket 客户端 + 状态
lib/models/card_model.dart  卡牌模型
lib/widgets/poker_card.dart  卡牌 UI
lib/pages/lobby_page.dart    大厅
lib/pages/table_page.dart    牌桌
android/               原生构建骨架（Gradle / AGP）
.github/workflows/     GitHub Actions 自动构建
```
