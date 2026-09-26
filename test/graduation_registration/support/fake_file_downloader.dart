import 'dart:async';
import 'dart:typed_data';

import 'package:ucss_data_collection/features/graduation_registration/data/export/file_downloader.dart';

/// One file that the code under test asked to download.
class DownloadedFile {
  const DownloadedFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

/// Records downloads instead of starting them in a browser.
///
/// Set [error] to make `download` fail, or [gate] to hold it open until the
/// test completes it.
class FakeFileDownloader implements FileDownloader {
  final List<DownloadedFile> downloads = [];
  Object? error;
  Completer<void>? gate;

  @override
  Future<void> download({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await gate?.future;
    if (error != null) throw error!;
    downloads.add(
      DownloadedFile(fileName: fileName, bytes: bytes, mimeType: mimeType),
    );
  }
}
