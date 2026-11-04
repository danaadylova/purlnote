import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../auth/auth_service.dart';
import '../ravelry/ravelry_client.dart';
import 'library_models.dart';
import 'library_store.dart';

/// Ravelry's daily limit of PDF downloads (100 a day) was reached.
class DownloadLimitReached implements Exception {
  const DownloadLimitReached();
}

/// The knitter hasn't allowed PDF downloads yet, or that permission ended.
class NeedsPdfPermission implements Exception {
  const NeedsPdfPermission();
}

/// The picked file can't be used. [message] is safe to show.
class ImportRefused implements Exception {
  const ImportRefused(this.message);
  final String message;
}

/// Picks a PDF from Files and returns its name and bytes, or null if the
/// knitter cancelled. Swapped out in tests.
typedef PickPdf = Future<({String name, Uint8List bytes})?> Function();

/// Gets PDFs onto the phone: purchases downloaded from Ravelry, and PDFs
/// imported from Files. Every file is stored once, named by its SHA-256.
class PdfFiles {
  PdfFiles({
    required this.library,
    required this.ravelry,
    required this.pdfRavelry,
    http.Client? httpClient,
    Future<Directory> Function()? folder,
    PickPdf? pickPdf,
  })  : _http = httpClient ?? http.Client(),
        _folder = folder ?? _defaultFolder,
        _pickPdf = pickPdf ?? _pickWithFilesApp;

  final LibraryStore library;

  /// For reading the list of files in a purchase.
  final RavelryClient ravelry;

  /// For download links. Uses the separate PDF-download sign-in.
  final RavelryClient pdfRavelry;
  final http.Client _http;
  final Future<Directory> Function() _folder;
  final PickPdf _pickPdf;

  /// Imported PDFs larger than this are refused.
  static const maxImportBytes = 100 * 1024 * 1024;

  /// Fetches the list of PDFs in a Ravelry purchase and remembers them.
  /// Doesn't download anything. Throws [RavelryUnreachable] offline.
  Future<List<PatternFile>> loadPurchaseFiles(int volumeId) async {
    final reply = await ravelry.get('/volumes/$volumeId.json');
    final volume = reply.body!['volume'] as Map<String, dynamic>;
    final attachments = (volume['volume_attachments'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((attachment) => attachment['product_attachment_id'] != null)
        .map((attachment) => (
              attachmentId: (attachment['product_attachment_id'] as num).toInt(),
              label: fileLabel(attachment['filename'] as String?),
            ))
        .toList();
    final key = LibraryPattern.volumeKey(volumeId);
    await library.rememberAttachments(key, attachments);
    return library.filesFor(key);
  }

  /// Downloads one purchased PDF. Each download uses one of the knitter's
  /// 100 daily download links, so a file is only ever downloaded once.
  Future<PatternFile> download(PatternFile file) async {
    if (file.isDownloaded) return file;
    final attachmentId = file.attachmentId;
    if (attachmentId == null) throw ArgumentError('Only Ravelry purchases can be downloaded.');

    final Map<String, dynamic> reply;
    try {
      reply = await pdfRavelry.post('/product_attachments/$attachmentId/generate_download_link.json', const {});
    } on SignInExpired {
      throw const NeedsPdfPermission();
    } on RavelryError catch (error) {
      if (error.statusCode == 429) throw const DownloadLimitReached();
      rethrow;
    }

    final url = (reply['download_link'] as Map<String, dynamic>?)?['url'] as String?;
    if (url == null) throw const RavelryError(500, 'download link');

    final http.Response response;
    try {
      response = await _http.get(Uri.parse(url));
    } on Exception {
      throw const RavelryUnreachable();
    }
    if (response.statusCode != 200) throw RavelryError(response.statusCode, 'PDF download');

    final saved = await _store(response.bodyBytes);
    await library.saveDownload(file.id, path: saved.path, sha256: saved.sha256, bytes: saved.bytes);
    return (await library.file(file.id))!;
  }

  /// Lets the knitter pick a PDF in Files and adds it to the library: as a
  /// new pattern, or as another file of [addToPattern].
  ///
  /// Returns the pattern's key, or null if they cancelled. If the same PDF is
  /// already on the phone, returns its pattern, so its notes come back.
  Future<String?> importFromFiles({String? addToPattern}) async {
    final picked = await _pickPdf();
    if (picked == null) return null;

    if (picked.bytes.length > maxImportBytes) {
      throw const ImportRefused('That PDF is over 100 MB, which is too large to import.');
    }
    if (!looksLikePdf(picked.bytes)) {
      throw const ImportRefused('That file isn\'t a PDF.');
    }

    final fingerprint = sha256.convert(picked.bytes).toString();
    final existing = await library.fileWithSha256(fingerprint);
    if (existing != null) return existing.patternKey;

    final saved = await _store(picked.bytes);
    return library.addImportedFile(
      label: fileLabel(picked.name),
      path: saved.path,
      sha256: saved.sha256,
      bytes: saved.bytes,
      patternKey: addToPattern,
    );
  }

  /// Writes a PDF to the app's private folder, named by its fingerprint.
  Future<({String path, String sha256, int bytes})> _store(Uint8List bytes) async {
    final fingerprint = sha256.convert(bytes).toString();
    final folder = await _folder();
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, '$fingerprint.pdf'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return (path: file.path, sha256: fingerprint, bytes: bytes.length);
  }

  static Future<Directory> _defaultFolder() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'patterns'));
  }

  static Future<({String name, Uint8List bytes})?> _pickWithFilesApp() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked == null) return null;
    final size = await picked.xFile.length();
    if (size > maxImportBytes) throw const ImportRefused('That PDF is over 100 MB, which is too large to import.');
    return (name: picked.name, bytes: await picked.xFile.readAsBytes());
  }
}

/// Real PDFs start with "%PDF". Checked so a renamed file can't get in.
bool looksLikePdf(Uint8List bytes) {
  return bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
}

/// A readable file label from a file name: "harbour_raglan-charts.pdf"
/// becomes "harbour raglan charts".
String fileLabel(String? fileName) {
  if (fileName == null || fileName.trim().isEmpty) return 'Pattern';
  final withoutExtension = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  final spaced = withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return spaced.isEmpty ? 'Pattern' : spaced;
}
