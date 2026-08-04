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
        color: Colors.blueGrey,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: const Center(
        child: Icon(Icons.block, color: Colors.white30),
      ),
    );
  }
}
