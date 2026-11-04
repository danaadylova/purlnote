import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/library/library_models.dart';
import 'package:purlnote/library/library_store.dart';
import 'package:purlnote/library/pdf_files.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';

import 'support/fakes.dart';

/// Bytes that start like a real PDF.
Uint8List pdfBytes(String body) => Uint8List.fromList('%PDF-1.7 $body'.codeUnits);

void main() {
  late LocalDatabase database;
  late LibraryStore library;
  late Directory folder;

  setUp(() async {
    database = await emptyDatabase();
    library = LibraryStore(database);
    folder = Directory.systemTemp.createTempSync('purlnote_pdfs_');
    await database.replaceRecords(RecordType.libraryVolume, [
      {'id': 70, 'title': 'Harbour Raglan', 'author_name': 'A. Designer', 'pattern_id': 500, 'has_downloads': true},
    ], testNow);
  });

  tearDown(() => database.close());

  /// PdfFiles talking to a fake Ravelry. [downloads] counts download links.
  Future<PdfFiles> pdfFiles({
    ({String name, Uint8List bytes})? picked,
    int linkStatus = 200,
    List<String>? downloads,
  }) async {
    final ravelryHttp = MockClient((request) async {
      final path = request.url.path;
      if (path == '/volumes/70.json') {
        return jsonReply({
          'volume': {
            'id': 70,
            'volume_attachments': [
              {'product_attachment_id': 900, 'filename': 'harbour_raglan-pattern.pdf'},
              {'product_attachment_id': 901, 'filename': 'Charts.pdf'},
            ],
          },
        });
      }
      if (path.endsWith('/generate_download_link.json')) {
        downloads?.add(path);
        if (linkStatus != 200) return http.Response('limit', linkStatus);
        return jsonReply({
          'download_link': {'url': 'https://files.test/${path.split('/')[2]}.pdf'},
        });
      }
      if (request.url.host == 'files.test') {
        return http.Response.bytes(pdfBytes(request.url.path), 200);
      }
      return http.Response('not found', 404);
    });
    final auth = await signedInAuth();
    final ravelry = RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: auth, httpClient: ravelryHttp);
    return PdfFiles(
      library: library,
      ravelry: ravelry,
      pdfRavelry: ravelry,
      httpClient: ravelryHttp,
      folder: () async => folder,
      pickPdf: () async => picked,
    );
  }

  test('the library lists purchases and imports together', () async {
    final files = await pdfFiles(picked: (name: 'my_socks.pdf', bytes: pdfBytes('socks')));
    await files.importFromFiles();

    final patterns = await library.patterns();
    expect(patterns.map((p) => p.title), ['Harbour Raglan', 'my socks']);
    expect(patterns.first.source, PatternSource.ravelry);
    expect(patterns.first.ravelryPatternId, 500);
    expect(patterns.last.source, PatternSource.imported);
    expect(patterns.last.isOnPhone, isTrue);
  });

  test('a purchase\'s files are listed from Ravelry, then each is downloaded once', () async {
    final downloads = <String>[];
    final files = await pdfFiles(downloads: downloads);

    final listed = await files.loadPurchaseFiles(70);
    expect(listed.map((f) => f.label), ['harbour raglan pattern', 'Charts']);
    expect(listed.every((f) => !f.isDownloaded), isTrue);

    final charts = await files.download(listed[1]);
    expect(charts.isDownloaded, isTrue);
    expect(File(charts.localPath!).readAsBytesSync().take(4), '%PDF'.codeUnits);

    await files.download(charts);
    expect(downloads, hasLength(1), reason: 'a file already on the phone uses no download link');

    // Listing again keeps the download.
    final again = await files.loadPurchaseFiles(70);
    expect(again[1].isDownloaded, isTrue);
  });

  test('the daily download limit is reported as such', () async {
    final files = await pdfFiles(linkStatus: 429);
    final listed = await files.loadPurchaseFiles(70);
    await expectLater(files.download(listed.first), throwsA(isA<DownloadLimitReached>()));
  });

  test('a file that isn\'t a PDF is refused', () async {
    final files = await pdfFiles(picked: (name: 'photo.pdf', bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1])));
    await expectLater(files.importFromFiles(), throwsA(isA<ImportRefused>()));
    expect(await library.patterns(), hasLength(1));
  });

  test('importing the same PDF again returns the pattern it already belongs to', () async {
    final files = await pdfFiles(picked: (name: 'socks.pdf', bytes: pdfBytes('socks')));
    final first = await files.importFromFiles();
    final second = await files.importFromFiles();

    expect(second, first);
    expect((await library.patterns()).where((p) => p.source == PatternSource.imported), hasLength(1));
  });

  test('another PDF can be added to an imported pattern', () async {
    final first = await (await pdfFiles(picked: (name: 'socks.pdf', bytes: pdfBytes('socks')))).importFromFiles();
    await (await pdfFiles(picked: (name: 'socks_charts.pdf', bytes: pdfBytes('charts'))))
        .importFromFiles(addToPattern: first);

    final files = await library.filesFor(first!);
    expect(files.map((f) => f.label), ['Pattern', 'socks charts']);
  });

  test('cancelling the picker imports nothing', () async {
    final files = await pdfFiles(picked: null);
    expect(await files.importFromFiles(), isNull);
  });

  test('file labels are readable', () {
    expect(fileLabel('harbour_raglan-charts.PDF'), 'harbour raglan charts');
    expect(fileLabel(null), 'Pattern');
    expect(fileLabel('.pdf'), 'Pattern');
  });

  test('each pattern keeps its own screen-awake setting and project link', () async {
    expect(await library.awakeMinutes('volume:70'), isNull);
    await library.setAwakeMinutes('volume:70', 30);
    expect(await library.awakeMinutes('volume:70'), 30);

    await library.linkProject(10, 'import:1');
    expect(await library.linkedPatternKey(10), 'import:1');
  });
}
