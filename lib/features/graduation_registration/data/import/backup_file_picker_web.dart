import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'backup_file_picker.dart';
import 'registration_backup_parser.dart';

BackupFilePicker createPlatformPicker() => _WebBackupFilePicker();

/// Opens the browser's file chooser through a temporary `<input type=file>`.
class _WebBackupFilePicker implements BackupFilePicker {
  @override
  Future<PickedBackupFile?> pickBackupFile() {
    final completer = Completer<PickedBackupFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.json,application/json'
      ..style.display = 'none';
    web.document.body!.append(input);

    void finish(PickedBackupFile? file) {
      if (!completer.isCompleted) completer.complete(file);
      input.remove();
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      input.remove();
    }

    Future<void> read() async {
      try {
        final file = input.files?.item(0);
        if (file == null) return finish(null);
        if (file.size > RegistrationBackupParser.maxFileBytes) {
          throw const BackupFileException(
            'The file is too large to be a backup (over 20 MB).',
          );
        }
        final buffer = await file.arrayBuffer().toDart;
        finish(
          PickedBackupFile(name: file.name, bytes: buffer.toDart.asUint8List()),
        );
      } catch (error, stackTrace) {
        fail(error, stackTrace);
      }
    }

    input.addEventListener('change', ((web.Event _) => unawaited(read())).toJS);
    // Fired when the chooser is dismissed without a file. Browsers that do not
    // send it simply leave this future pending, which is harmless.
    input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
    input.click();
    return completer.future;
  }
}
