import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_downloader.dart';

FileDownloader createPlatformDownloader() => _WebFileDownloader();

/// Downloads a file by clicking a temporary link to an in-memory Blob.
class _WebFileDownloader implements FileDownloader {
  @override
  Future<void> download({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body!.append(link);
    link.click();
    link.remove();
    // Give the browser time to start reading the Blob before releasing it.
    Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
  }
}
