import 'dart:typed_data';

import 'backup_file_picker_stub.dart'
    if (dart.library.js_interop) 'backup_file_picker_web.dart'
    as platform;

/// A file the user chose.
class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Lets the user choose a backup file from their computer.
///
/// An interface so importing can be tested without a browser.
abstract interface class BackupFilePicker {
  /// Opens the browser's file chooser and returns the chosen file, or `null`
  /// if the user cancelled.
  ///
  /// Throws `BackupFileException` if the file is too large to read.
  Future<PickedBackupFile?> pickBackupFile();
}

/// The picker for the current platform: the real one in a browser, and one
/// that throws [UnsupportedError] everywhere else.
BackupFilePicker createBackupFilePicker() => platform.createPlatformPicker();
