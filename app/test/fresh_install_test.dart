import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // iOS keeps the Keychain (and so the Ravelry sign-in) when the app is
  // deleted. The app tells a fresh install by its database being new, and
  // signs out then.
  test('a new database says it was just created; reopening it does not', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('purlnote_install_').path}/purlnote.db';

    final firstLaunch = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(firstLaunch.createdNow, isTrue);
    await firstLaunch.close();

    final nextLaunch = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(nextLaunch.createdNow, isFalse);
    await nextLaunch.close();
  });
}
