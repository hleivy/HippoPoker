// lib/models/card_model.dart —— 与后端 deck.js 对齐的卡牌模型
//
// 后端一张牌 = { rank: 2..14 (11=J,12=Q,13=K,14=A), suit: 0..3 (0=♠,1=♥,2=♦,3=♣) }

class PokerCard {
  final int rank; // 2..14
  final int suit; // 0..3

  PokerCard(this.rank, this.suit);

  factory PokerCard.fromJson(Map<String, dynamic> j) =>
      PokerCard(j['rank'] as int, j['suit'] as int);

  String get rankLabel => _rankLabels[rank] ?? rank.toString();
  String get suitSymbol => _suitSymbols[suit] ?? '?';
  bool get isRed => suit == 1 || suit == 2;

  static const Map<int, String> _rankLabels = {
    2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7', 8: '8', 9: '9',
    10: '10', 11: 'J', 12: 'Q', 13: 'K', 14: 'A',
  };

  static const List<String> _suitSymbols = ['♠', '♥', '♦', '♣'];
}
