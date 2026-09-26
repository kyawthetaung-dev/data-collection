import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Roboto font that ships with the Flutter SDK.
///
/// Widget tests draw text with the "Ahem" font, in which every character is a
/// wide square. That is far wider than real text, so layout checks made with it
/// are not meaningful for anything about text fitting. Returns `false` if the
/// SDK fonts cannot be found, in which case tests that need them should skip.
Future<bool> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final directory = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!directory.existsSync()) return false;

  Future<ByteData> bytes(String name) async {
    final data = await File('${directory.path}/$name').readAsBytes();
    return ByteData.view(data.buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-medium.ttf'))
    ..addFont(bytes('roboto-bold.ttf'));
  await roboto.load();
  return true;
}
