// lib/widgets/poker_card.dart —— 卡牌 UI 组件
import 'package:flutter/material.dart';
import '../models/card_model.dart';

class PokerCardView extends StatelessWidget {
  final PokerCard? card;
  final double width;
  final double height;

  const PokerCardView({
    super.key,
    required this.card,
    this.width = 44,
    this.height = 62,
  });

  @override
  Widget build(BuildContext context) {
    final color = (card?.isRed ?? false) ? Colors.red : Colors.black;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))
        ],
      ),
      child: card == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  card!.rankLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: height * 0.3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  card!.suitSymbol,
                  style: TextStyle(color: color, fontSize: height * 0.26),
                ),
              ],
            ),
    );
  }
}

class CardBack extends StatelessWidget {
  final double width;
  final double height;
  const CardBack({super.key, this.width = 44, this.height = 62});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white70, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          painter: _CardBackPainter(),
          child: Center(
            child: Container(
              width: width * 0.42,
              height: width * 0.42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
              ),
              child: Center(
                child: Icon(
                  Icons.auto_awesome,
                  size: width * 0.24,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 专业扑克牌背：深蓝底 + 交叉菱形格纹（经典 lattice 图案）
class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // 背景渐变
    final bg = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF15346B), const Color(0xFF0B1E45)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // 交叉菱形格纹
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;
    const step = 7.0;
    for (double d = -size.height; d < size.width; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), line);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), line);
    }

    // 内描边
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      inner,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
