import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'rule_splitter.dart';
import 'size_text.dart';
import 'step_models.dart';
import 'steps_store.dart';

/// Reads the text of each page of a PDF, first page first. Pages without a
/// text layer (scans, image-only charts) come back empty.
typedef PageTextReader = Future<List<String>> Function(String pdfPath);

/// Apple's on-device model, reached through a small Swift bridge in the iOS
/// app (see ios/Runner/AppDelegate.swift). Only the on-device model is used,
/// never Apple's cloud, so the pattern's text never leaves the phone.
class OnDeviceModel {
  const OnDeviceModel();

  static const _channel = MethodChannel('purlnote/steps');

  /// True on iPhones with Apple Intelligence turned on and its model ready.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Steps for one page (or part of a page). [section] is the heading the
  /// page continues, so the model knows where it is.
  Future<List<PatternStep>> readPage({required String text, required int page, String? section}) async {
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'readPage',
      {'text': text, 'section': section},
    );
    return [
      for (final step in result ?? const <Map<Object?, Object?>>[])
        if (_blankToNull(step['text']) != null)
          PatternStep(
            section: _blankToNull(step['section']) ?? section,
            label: _blankToNull(step['label']),
            side: _blankToNull(step['side'])?.toUpperCase(),
            text: _blankToNull(step['text'])!,
            sourcePage: page,
            madeBy: StepMaker.model,
          ),
    ];
  }

  static String? _blankToNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// How building steps went.
class BuildResult {
  const BuildResult({required this.madeBy, required this.stepCount, required this.pagesWithoutText});

  /// [StepMaker.model] or [StepMaker.rules].
  final StepMaker madeBy;
  final int stepCount;

  /// Pages that had no text to read, such as scans.
  final List<int> pagesWithoutText;
}

/// Makes a PDF's steps, once per file, and stores them.
class StepBuilder {
  StepBuilder({required this.store, OnDeviceModel? model, PageTextReader? readText})
      : _model = model ?? const OnDeviceModel(),
        _readText = readText ?? readPdfText;

  final StepsStore store;
  final OnDeviceModel _model;
  final PageTextReader _readText;

  /// The model's context is small (about 4,000 tokens for prompt and reply),
  /// so each request carries at most this many characters.
  static const maxCharactersPerRequest = 3500;

  /// Builds steps for the PDF at [pdfPath]. [onPage] reports progress after
  /// each page; steps are stored as they're made, so the first ones can be
  /// used before the rest are done.
  Future<BuildResult> build({
    required String fileSha256,
    required String pdfPath,
    void Function(int page, int pageCount)? onPage,
  }) async {
    final pages = await _readText(pdfPath);
    // Sizes come from the PDF's own text, not the steps, so every size the
    // pattern lists is offered even if a step was shortened.
    await store.saveSizeNames(fileSha256, sizeNamesFor(pages.join('\n')));
    final withoutText = [
      for (var i = 0; i < pages.length; i++)
        if (pages[i].trim().isEmpty) i + 1,
    ];

    if (!await _model.isAvailable()) {
      final steps = const RuleSplitter().split(pages);
      await store.replaceSteps(fileSha256, steps);
      onPage?.call(pages.length, pages.length);
      return BuildResult(madeBy: StepMaker.rules, stepCount: steps.length, pagesWithoutText: withoutText);
    }

    await store.replaceSteps(fileSha256, const []);
    final all = <PatternStep>[];
    String? section;
    for (var index = 0; index < pages.length; index++) {
      final page = index + 1;
      final pageSteps = <PatternStep>[];
      for (final chunk in chunksOf(pages[index], maxCharactersPerRequest)) {
        try {
          pageSteps.addAll(await _model.readPage(text: chunk, page: page, section: section));
        } on PlatformException {
          // The model couldn't read this part; fall back to the rules for it.
          pageSteps.addAll(const RuleSplitter().split([chunk]).map((step) => _onPage(step, page)));
        }
      }
      if (pageSteps.isNotEmpty) section = pageSteps.last.section ?? section;
      all.addAll(pageSteps);
      await store.appendSteps(fileSha256, pageSteps);
      onPage?.call(page, pages.length);
    }

    // Repeats can span pages, so they're written out once everything is read.
    final steps = RuleSplitter.expandRepeats(all);
    await store.replaceSteps(fileSha256, steps);
    return BuildResult(madeBy: StepMaker.model, stepCount: steps.length, pagesWithoutText: withoutText);
  }

  /// The sizes a file offers, worked out from its text once and then kept.
  Future<List<String>> sizeNames({required String fileSha256, required String pdfPath}) async {
    final saved = await store.sizeNames(fileSha256);
    if (saved != null) return saved;
    final names = sizeNamesFor((await _readText(pdfPath)).join('\n'));
    await store.saveSizeNames(fileSha256, names);
    return names;
  }

  static PatternStep _onPage(PatternStep step, int page) => PatternStep(
        section: step.section,
        label: step.label,
        side: step.side,
        text: step.text,
        sourcePage: page,
        madeBy: StepMaker.rules,
      );
}

/// Splits [text] into pieces of at most [limit] characters, breaking only
/// between lines (a single overlong line is cut).
List<String> chunksOf(String text, int limit) {
  if (text.trim().isEmpty) return const [];
  final chunks = <String>[];
  final current = StringBuffer();
  for (final line in text.split('\n')) {
    if (current.length + line.length + 1 > limit && current.isNotEmpty) {
      chunks.add(current.toString());
      current.clear();
    }
    var rest = line;
    while (rest.length > limit) {
      chunks.add(rest.substring(0, limit));
      rest = rest.substring(limit);
    }
    if (current.isNotEmpty) current.write('\n');
    current.write(rest);
  }
  if (current.toString().trim().isNotEmpty) chunks.add(current.toString());
  return chunks;
}

/// Reads each page's text with the same PDF engine the reader uses.
Future<List<String>> readPdfText(String pdfPath) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openFile(pdfPath);
  try {
    return [
      for (final page in document.pages)
        ((await page.loadText())?.fullText ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    ];
  } finally {
    await document.dispose();
  }
}
