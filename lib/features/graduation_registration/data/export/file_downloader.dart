import 'dart:typed_data';

import 'file_downloader_stub.dart'
    if (dart.library.js_interop) 'file_downloader_web.dart'
    as platform;

/// Hands a generated file to the user, as a browser download.
///
/// An interface so exports can be tested without a browser.
abstract interface class FileDownloader {
  Future<void> download({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}

/// The downloader for the current platform: the real one in a browser, and one
/// that throws [UnsupportedError] everywhere else.
FileDownloader createFileDownloader() => platform.createPlatformDownloader();
