import 'backup_file_picker.dart';

/// Used off the web, where there is no browser file chooser. It exists so the
/// code still compiles and runs in VM tests.
BackupFilePicker createPlatformPicker() => const _UnsupportedBackupFilePicker();

class _UnsupportedBackupFilePicker implements BackupFilePicker {
  const _UnsupportedBackupFilePicker();

  @override
  Future<PickedBackupFile?> pickBackupFile() {
    throw UnsupportedError('Choosing a file is only supported on the web.');
  }
}
