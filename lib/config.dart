// lib/config.dart —— 服务器地址单一配置点
//
// 当前指向微信云托管的公网后端（wss）。注意：
//   - 安卓原生 App 不受微信「socket 合法域名白名单」限制，可直接连此地址。
//   - 等你 uncle.ren 备案完成后，可把地址改为 wss://poker.uncle.ren 即可无缝切换。
const String SERVER_URL =
    'wss://express-b40d-290839-10-1462470907.sh.run.tcloudbase.com';

/// 应用版本号（与 pubspec.yaml 保持一致，仅供界面展示）
const String kAppVersion = '0.0.12';
