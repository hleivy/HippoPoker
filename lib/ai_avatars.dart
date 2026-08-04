// AI 牌手真实头像映射（照片取自 Wikimedia / Wikipedia，CC 授权）。
// key 必须与 server/src/roomManager.js 中 FAMOUS_PROS 的真名完全一致（不含 " (AI)" 后缀）。
// 名单中的 Linus Loeliger 暂无自由授权照片，未列入；客户端会回退为字母头像。
const Map<String, String> kAiAvatarAssets = {
  'Doyle Brunson': 'assets/avatars/doyle_brunson.jpg',
  'Phil Ivey': 'assets/avatars/phil_ivey.jpg',
  'Daniel Negreanu': 'assets/avatars/daniel_negreanu.jpg',
  'Tom Dwan': 'assets/avatars/tom_dwan.jpg',
  'Phil Hellmuth': 'assets/avatars/phil_hellmuth.jpg',
  'Johnny Chan': 'assets/avatars/johnny_chan.jpg',
  'Chris Moneymaker': 'assets/avatars/chris_moneymaker.jpg',
  'Fedor Holz': 'assets/avatars/fedor_holz.jpg',
  'Antonio Esfandiari': 'assets/avatars/antonio_esfandiari.jpg',
  'Gus Hansen': 'assets/avatars/gus_hansen.jpg',
  'Patrik Antonius': 'assets/avatars/patrik_antonius.jpg',
  'Sam Farha': 'assets/avatars/sam_farha.jpg',
  'Erik Seidel': 'assets/avatars/erik_seidel.jpg',
  'Vanessa Selbst': 'assets/avatars/vanessa_selbst.jpg',
  'Liv Boeree': 'assets/avatars/liv_boeree.jpg',
  'Kristen Bicknell': 'assets/avatars/kristen_bicknell.jpg',
  'Jason Koon': 'assets/avatars/jason_koon.jpg',
  'Doug Polk': 'assets/avatars/doug_polk.jpg',
};

/// 根据显示的玩家名（可能带 " (AI)" 后缀）返回头像资源路径，找不到则返回 null。
String? aiAvatarFor(String displayName) {
  final base = displayName.replaceAll(' (AI)', '').trim();
  return kAiAvatarAssets[base];
}
