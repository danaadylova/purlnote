import 'package:path/path.dart' as p;

/// Where the app's own files (PDFs, project photos) live on this phone.
///
/// iOS can move an app's folder when the app is updated, so a full path saved
/// earlier may no longer exist. Files are always kept as
/// `<app support folder>/<kind>/<file>`, so a saved path is re-anchored to
/// the current folder when it's read.
abstract final class AppPaths {
  /// The app support folder for this launch. Set once at startup; left unset
  /// in tests, where saved paths are used as they are.
  static String? supportFolder;

  /// [saved] re-anchored to this launch's app support folder.
  static String resolve(String saved) {
    final support = supportFolder;
    if (support == null) return saved;
    return p.join(support, p.basename(p.dirname(saved)), p.basename(saved));
  }
}
