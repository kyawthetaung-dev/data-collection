import 'dart:typed_data';

import 'file_downloader.dart';

/// Used off the web, where there is no browser download to trigger. It exists
/// so the code still compiles and runs in VM tests.
FileDownloader createPlatformDownloader() => const _UnsupportedFileDownloader();

class _UnsupportedFileDownloader implements FileDownloader {
  const _UnsupportedFileDownloader();

  @override
  Future<void> download({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    throw UnsupportedError('Downloading files is only supported on the web.');
  }
}
