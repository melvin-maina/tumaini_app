import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppHomeAction extends StatelessWidget {
  const AppHomeAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.home_outlined),
      tooltip: 'Home',
      onPressed: () => context.go('/home'),
    );
  }
}
