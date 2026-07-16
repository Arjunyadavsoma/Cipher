import 'dart:io';
import 'dart:typed_data';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Result of trying to extract text from an uploaded file.
///
/// Always check [error] first - [text] is empty when extraction failed.
/// [truncated] is true when the file's text was longer than
/// [FileParserService.maxCharacters] and got cut down to fit the model's
/// context budget; the caller should mention that to the user/LLM rather
/// than silently passing a partial document as if it were the whole thing.
class ParsedFile {
  final String fileName;
  final String extension;
  final String text;
  final bool truncated;
  final String? error;

  const ParsedFile({
    required this.fileName,
    required this.extension,
    required this.text,
    this.truncated = false,
    this.error,
  });

  bool get hasError => error != null;
}

/// Extracts plain text from user-uploaded files so it can be fed into the
/// chat pipeline as context, the same way a typed message would be.
///
/// Supported today: pdf, docx, txt, md, csv, json, log.
/// Anything else returns a [ParsedFile] with [ParsedFile.error] set -
/// callers should surface that to the user rather than silently drop the
/// attachment, so they know why "summarize this" didn't work.
///
/// IMPORTANT: accepts EITHER a file path OR raw bytes. On Android,
/// PlatformFile.path can be null when the file was picked from a cloud
/// provider (Google Drive, Downloads via Storage Access Framework, etc.) -
/// in that case bytes must be used instead, or extraction silently never
/// runs. Always pass both when available; this prioritizes path (cheaper,
/// no double-read) but falls back to bytes automatically.
class FileParserService {
  FileParserService._internal();

  static final FileParserService instance = FileParserService._internal();

  /// Hard cap on how much extracted text we forward to the LLM. Keeps a
  /// huge PDF from blowing the model's context window or the request
  /// payload - a truncated summary is more useful than a failed request.
  static const int maxCharacters = 15000;

  /// Reject anything bigger than this before even attempting to parse -
  /// protects the device from hanging or running out of memory on a
  /// multi-hundred-MB file picked by mistake.
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  static const Set<String> _plainTextExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'log',
  };

  Future<ParsedFile> extractText({
    String? filePath,
    Uint8List? bytes,
    required String fileName,
  }) async {
    final extension = _extensionOf(fileName);

    Uint8List? resolvedBytes = bytes;

    if (resolvedBytes == null && filePath != null) {
      final file = File(filePath);
      if (!await file.exists()) {
        return ParsedFile(
          fileName: fileName,
          extension: extension,
          text: '',
          error: "File not found on device.",
        );
      }
      resolvedBytes = await file.readAsBytes();
    }

    if (resolvedBytes == null) {
      return ParsedFile(
        fileName: fileName,
        extension: extension,
        text: '',
        error: "Couldn't read this file - no path or data was available "
            "for it. Try picking it again.",
      );
    }

    if (resolvedBytes.lengthInBytes > maxFileSizeBytes) {
      final mb = (resolvedBytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
      return ParsedFile(
        fileName: fileName,
        extension: extension,
        text: '',
        error: "File is too large to read ($mb MB, limit is "
            "${maxFileSizeBytes ~/ (1024 * 1024)} MB).",
      );
    }

    try {
      switch (extension) {
        case 'pdf':
          return _extractPdf(resolvedBytes, fileName, extension);
        case 'docx':
          return _extractDocx(resolvedBytes, fileName, extension);
        default:
          if (_plainTextExtensions.contains(extension)) {
            return _extractPlainText(resolvedBytes, fileName, extension);
          }
          return ParsedFile(
            fileName: fileName,
            extension: extension,
            text: '',
            error: "I can't read .$extension files yet - PDF, Word (.docx), "
                "and plain text (.txt/.md/.csv/.json) are supported.",
          );
      }
    } catch (e) {
      return ParsedFile(
        fileName: fileName,
        extension: extension,
        text: '',
        error: "Couldn't extract text from this file — $e",
      );
    }
  }

  ParsedFile _extractPdf(Uint8List bytes, String fileName, String extension) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final text = PdfTextExtractor(document).extractText();
      return _buildResult(fileName, extension, text);
    } finally {
      document.dispose();
    }
  }

  ParsedFile _extractDocx(Uint8List bytes, String fileName, String extension) {
    final text = docxToText(bytes);
    return _buildResult(fileName, extension, text);
  }

  ParsedFile _extractPlainText(
    Uint8List bytes,
    String fileName,
    String extension,
  ) {
    final text = String.fromCharCodes(bytes);
    return _buildResult(fileName, extension, text);
  }

  ParsedFile _buildResult(String fileName, String extension, String rawText) {
    final trimmed = rawText.trim();

    if (trimmed.isEmpty) {
      return ParsedFile(
        fileName: fileName,
        extension: extension,
        text: '',
        error: "This file doesn't seem to contain any readable text "
            "(it may be a scanned/image-only document).",
      );
    }

    if (trimmed.length > maxCharacters) {
      return ParsedFile(
        fileName: fileName,
        extension: extension,
        text: trimmed.substring(0, maxCharacters),
        truncated: true,
      );
    }

    return ParsedFile(fileName: fileName, extension: extension, text: trimmed);
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
}