import 'dart:async';
import 'dart:typed_data';

import 'package:ucss_data_collection/features/graduation_registration/data/import/backup_file_picker.dart';

/// Stands in for the browser's file chooser.
///
/// Set [next] to the file the "user" chooses, leave it `null` for a cancelled
/// chooser, set [error] to make choosing fail, or [gate] to keep the chooser
/// open until the test completes it.
class FakeBackupFilePicker implements BackupFilePicker {
  PickedBackupFile? next;
  Object? error;
  Completer<void>? gate;

  /// How many times the chooser was opened.
  var calls = 0;

  /// Makes the next chooser return a file with these contents.
  void choose(String name, Uint8List bytes) =>
      next = PickedBackupFile(name: name, bytes: bytes);

  @override
  Future<PickedBackupFile?> pickBackupFile() async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return next;
  }
}
