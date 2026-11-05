import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_session.dart';
import '../layout.dart';
import '../theme.dart';
import 'tutorial_screen.dart';

/// Where feedback emails go.
const feedbackEmail = 'unraveled.makes@gmail.com';

/// Purlnote's website pages.
const privacyPolicyUrl = 'https://danaadylova.github.io/purlnote/privacy.html';
const supportUrl = 'https://danaadylova.github.io/purlnote/support.html';

/// Everything that isn't the Notebook or Library: sending feedback, the
/// Ravelry account and backup, the tour, and signing out.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final user = session.user;
        final waiting = session.pendingEdits.length;
        return Scaffold(
          appBar: AppBar(title: Semantics(header: true, child: const Text('More'))),
          body: ListView(
            padding: readablePadding(context, const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline),
                title: const Text('Send feedback'),
                subtitle: const Text('Ideas, bugs, or just hello. Goes to the person who makes Purlnote.'),
                onTap: () => _sendFeedback(context),
              ),
              const Divider(),
              if (session.connected) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: PurlnoteColors.plum,
                    foregroundColor: PurlnoteColors.marigold,
                    child: Icon(Icons.person),
                  ),
                  title: Text(user?.displayName ?? 'Ravelry account'),
                  subtitle: user == null ? null : Text('Ravelry: ${user.username}'),
                ),
                const Divider(),
                _Row(
                  icon: Icons.sync,
                  title: 'Changes waiting to send',
                  value: waiting == 0 ? 'None' : '$waiting',
                ),
                _Row(
                  icon: Icons.schedule,
                  title: 'Last updated from Ravelry',
                  value: session.lastSyncedAt == null
                      ? 'Not yet'
                      : TimeOfDay.fromDateTime(session.lastSyncedAt!).format(context),
                ),
                const Divider(),
                _BackupSwitch(session: session),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out of Ravelry'),
                  onTap: () => _confirmSignOut(context),
                ),
              ] else ...[
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_iphone),
                  title: Text('Using Purlnote on this phone'),
                  subtitle: Text('Your projects, PDFs, notes and counters are kept here.'),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: const Text('Connect a Ravelry account'),
                  subtitle: const Text(
                    'Optional. Adds your Ravelry projects, stash, queue and purchased patterns, '
                    'and lets notes go to project comments. Nothing on this phone is removed.',
                  ),
                  onTap: () => _connect(context),
                ),
              ],
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('How Purlnote works'),
                subtitle: const Text('A short tour of patterns, notes, the row ruler and Steps.'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (tour) => TutorialScreen(doneLabel: 'Done', onDone: () => Navigator.of(tour).pop()),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _openWebPage(context, privacyPolicyUrl),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('Help and support'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _openWebPage(context, supportUrl),
              ),
              const SizedBox(height: 16),
              const Text(
                'Purlnote is not made by or affiliated with Ravelry. PDFs and your notes on them stay on this device.',
                style: TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Opens Mail with the app version and iOS version filled in, which helps
  /// with bug reports. The knitter sees and can change all of it before
  /// sending.
  Future<void> _sendFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final app = await PackageInfo.fromPlatform();
    final details = 'Purlnote ${app.version} (${app.buildNumber}), ${Platform.operatingSystemVersion}';
    final mail = Uri(
      scheme: 'mailto',
      path: feedbackEmail,
      // Encoded by hand: Uri's queryParameters turns spaces into "+", which
      // Mail shows as is.
      query: 'subject=${Uri.encodeComponent('Purlnote feedback')}&body=${Uri.encodeComponent('\n\n\n$details')}',
    );
    if (!await launchUrl(mail)) {
      messenger.showSnackBar(const SnackBar(content: Text('No mail app found. You can write to $feedbackEmail.')));
    }
  }

  /// Opens one of Purlnote's web pages in Safari.
  Future<void> _openWebPage(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t open $url')));
    }
  }

  Future<void> _connect(BuildContext context) async {
    await session.signIn();
    final problem = session.signInProblem;
    if (problem != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final waiting = session.pendingEdits.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Ravelry?'),
        content: Text(
          'Your Ravelry projects, queue and stash are removed from this phone and come back when you sign in. '
          'Projects kept on this phone, PDFs, notes and counters stay, and Purlnote keeps working.'
          '${waiting == 0 ? '' : ' $waiting changes that haven\'t reached Ravelry yet will be lost.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await session.signOut();
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value, style: const TextStyle(color: PurlnoteColors.plumMuted)),
    );
  }
}

/// The notes-backup switch. On by default; turning it off deletes the copy
/// kept in the knitter's Ravelry account.
class _BackupSwitch extends StatefulWidget {
  const _BackupSwitch({required this.session});

  final AppSession session;

  @override
  State<_BackupSwitch> createState() => _BackupSwitchState();
}

class _BackupSwitchState extends State<_BackupSwitch> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    widget.session.isBackupEnabled().then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  Future<void> _change(bool enabled) async {
    setState(() => _enabled = enabled);
    final problem = await widget.session.setBackupEnabled(enabled);
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.backup_outlined),
      title: const Text('Back up notes to Ravelry'),
      subtitle: const Text(
        'Notes, highlights, counters and reading spots, kept privately in your Ravelry account. '
        'PDFs and pen drawings stay on this phone.',
      ),
      value: _enabled ?? true,
      onChanged: _enabled == null ? null : _change,
    );
  }
}
