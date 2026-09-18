import 'package:flutter/material.dart';

class AnimatedCardEntry extends StatefulWidget {
  final int index;
  final Widget child;

  /// Quando false, o card já nasce visível (sem fade/slide). Use nos itens que
  /// podem ser reciclados pelo ListView — evita a foto "sumir e voltar".
  final bool animate;

  const AnimatedCardEntry({
    super.key,
    required this.index,
    required this.child,
    this.animate = true,
  });

  @override
  State<AnimatedCardEntry> createState() => _AnimatedCardEntryState();
}

class _AnimatedCardEntryState extends State<AnimatedCardEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (!widget.animate) {
      _controller.value = 1;
      return;
    }

    final delay = Duration(
      milliseconds: (widget.index * 80).clamp(0, 400),
    );
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
