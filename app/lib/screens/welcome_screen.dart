import 'package:flutter/material.dart';

import '../app_session.dart';
import '../theme.dart';

/// The first screen. Purlnote works fully on its own, so starting without an
/// account is offered first and on equal footing; connecting Ravelry adds
/// projects, stash and purchased patterns from there, now or later.
///
/// Ravelry's own approval page opens in the system's secure browser sheet,
/// so Purlnote never sees the knitter's Ravelry password.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    await widget.session.signIn();
    if (mounted) setState(() => _signingIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final problem = widget.session.signInProblem;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            const _AppMark(),
            const SizedBox(height: 32),
            Semantics(
              header: true,
              child: Text('Your knitting and crochet notebook', style: text.headlineMedium),
            ),
            const SizedBox(height: 12),
            Text(
              'Read your pattern PDFs with notes, highlights and row counters that stay where you left them, '
              'and keep track of your projects.',
              style: text.bodyLarge?.copyWith(color: PurlnoteColors.plumMuted, height: 1.45),
            ),
            const SizedBox(height: 32),
            const _Point(icon: Icons.picture_as_pdf_outlined, text: 'Bring in pattern PDFs from Files'),
            const _Point(icon: Icons.format_list_numbered, text: 'Follow a pattern step by step, with counters'),
            const _Point(icon: Icons.cloud_off_outlined, text: 'Everything works offline and stays on this phone'),
            const SizedBox(height: 40),
            if (problem != null) ...[
              _Problem(message: problem),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: _signingIn ? null : widget.session.startWithoutRavelry,
              child: const Text('Start on this phone'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _signingIn ? null : _signIn,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: PurlnoteColors.moss, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              child: _signingIn
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Sign in with Ravelry'),
            ),
            const SizedBox(height: 16),
            Text(
              'Signing in brings your Ravelry projects, stash, queue and purchased patterns. '
              'You can connect Ravelry later from More, or never.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Purlnote is not made by or affiliated with Ravelry.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The app icon: a marigold "p" on a plum square.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: PurlnoteColors.plum, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: const ExcludeSemantics(
          child: Text(
            'p',
            style: TextStyle(color: PurlnoteColors.marigold, fontSize: 40, fontWeight: FontWeight.w700, height: 1),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PurlnoteColors.moss, size: 24),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35))),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: PurlnoteColors.blush, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: PurlnoteColors.plum, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 15, height: 1.4))),
          ],
        ),
      ),
    );
  }
}
