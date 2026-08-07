// AI 牌手真实头像映射（照片取自 Wikimedia / Wikipedia / 赛事直播截图，仅供界面展示）。
// key 必须与 server/src/roomManager.js 中 FAMOUS_PROS 的真名完全一致（不含 " (AI)" 后缀）。
const Map<String, String> kAiAvatarAssets = {
  'Doyle Brunson': 'images/avatars/doyle_brunson.jpg',
  'Phil Ivey': 'images/avatars/phil_ivey.jpg',
  'Daniel Negreanu': 'images/avatars/daniel_negreanu.jpg',
  'Tom Dwan': 'images/avatars/tom_dwan.jpg',
  'Linus Loeliger': 'images/avatars/linus_loeliger.jpg',
  'Phil Hellmuth': 'images/avatars/phil_hellmuth.jpg',
  'Johnny Chan': 'images/avatars/johnny_chan.jpg',
  'Chris Moneymaker': 'images/avatars/chris_moneymaker.jpg',
  'Fedor Holz': 'images/avatars/fedor_holz.jpg',
  'Antonio Esfandiari': 'images/avatars/antonio_esfandiari.jpg',
  'Gus Hansen': 'images/avatars/gus_hansen.jpg',
  'Patrik Antonius': 'images/avatars/patrik_antonius.jpg',
  'Sam Farha': 'images/avatars/sam_farha.jpg',
  'Erik Seidel': 'images/avatars/erik_seidel.jpg',
  'Vanessa Selbst': 'images/avatars/vanessa_selbst.jpg',
  'Liv Boeree': 'images/avatars/liv_boeree.jpg',
  'Kristen Bicknell': 'images/avatars/kristen_bicknell.jpg',
  'Jason Koon': 'images/avatars/jason_koon.jpg',
  'Doug Polk': 'images/avatars/doug_polk.jpg',
};

/// 所有可用 AI 牌手真名列表（与 server/src/roomManager.js 的 FAMOUS_PROS 保持一致）。
final List<String> kAiNames = kAiAvatarAssets.keys.toList();

/// 根据显示的玩家名（可能带 " (AI)" 后缀）返回头像资源路径，找不到则返回 null。
String? aiAvatarFor(String displayName) {
  final base = displayName.replaceAll(' (AI)', '').trim();
  return kAiAvatarAssets[base];
}
