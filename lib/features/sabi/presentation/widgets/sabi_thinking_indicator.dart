import 'package:flutter/material.dart';

class SabiThinkingIndicator extends StatelessWidget {
  const SabiThinkingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text('Sabi is thinking…'),
        ],
      ),
    );
  }
}
