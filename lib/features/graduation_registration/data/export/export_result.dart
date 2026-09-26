/// What an export or backup produced.
class ExportResult {
  const ExportResult({required this.fileName, required this.count});

  /// The name the downloaded file was given.
  final String fileName;

  /// How many registrations it contains.
  final int count;
}
