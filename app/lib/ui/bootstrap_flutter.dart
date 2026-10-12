import 'package:flutter/material.dart';

import 'app.dart';

/// App launcher when dart:ui is available (Flutter engine).
Future<void> launchNpApp() async {
  runApp(const NpApp());
}
