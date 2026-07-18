import 'package:flutter/material.dart';

class SabiAssistantButton extends StatefulWidget {
  const SabiAssistantButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<SabiAssistantButton> createState() => _SabiAssistantButtonState();
}

class _SabiAssistantButtonState extends State<SabiAssistantButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    )..forward();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1).animate(_animation),
      child: FadeTransition(
        opacity: _animation,
        child: Semantics(
          button: true,
          label: 'Ask Sabi',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x405B3DF5),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF5B3DF5), Color(0xFF7B55F6)],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(28),
                child: const SizedBox(
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Ask Sabi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
