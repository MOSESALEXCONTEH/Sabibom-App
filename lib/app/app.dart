import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

/// Root widget that configures SabiBom's routed Material application.
class SabiBomApp extends StatelessWidget {
  /// Creates the application root.
  const SabiBomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SabiBom',
      debugShowCheckedModeBanner: false,
      theme: SabiBomTheme.light,
      routerConfig: appRouter,
    );
  }
}
