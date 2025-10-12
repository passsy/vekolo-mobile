import 'package:flutter/material.dart';
import 'package:vekolo/models/user.dart';

/// Widget that displays a user's avatar with fallback to initials
class UserAvatar extends StatelessWidget {
  final User user;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const UserAvatar({super.key, required this.user, this.radius = 20, this.backgroundColor, this.foregroundColor});

  @override
  Widget build(BuildContext context) {
    final defaultBackgroundColor = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final defaultForegroundColor = foregroundColor ?? Colors.white;

    return CircleAvatar(
      radius: radius,
      backgroundColor: defaultBackgroundColor,
      backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
      child: user.avatar == null
          ? Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.bold, color: defaultForegroundColor),
            )
          : null,
    );
  }
}
