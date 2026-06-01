import 'package:flutter/material.dart';

class ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const ControlButton({super.key, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, color: cs.onSurface),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: cs.surfaceContainerHighest,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}
