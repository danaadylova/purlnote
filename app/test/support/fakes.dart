import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/auth/auth_service.dart';
import 'package:purlnote/auth/tokens.dart';
import 'package:purlnote/config.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/data/outbox.dart';
import 'package:purlnote/data/sync_engine.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testConfig = AppConfig(
  ravelryClientId: 'test-client-id',
  signInFunctionUrl: 'https://signin.test',
  ravelryApiUrl: 'https://api.test',
);

/// A fixed clock for tests.
final testNow = DateTime(2026, 11, 4, 10, 0);

/// Tokens that are good for another hour.
Tokens freshTokens({String access = 'access-1', String refresh = 'refresh-1'}) {
  return Tokens(accessToken: access, refreshToken: refresh, expiresAt: testNow.add(const Duration(hours: 1)));
}

http.Response jsonReply(Object body, {int status = 200, Map<String, String> headers = const {}}) {
  return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});
}

/// An AuthService whose token is always valid, for tests about other parts.
Future<AuthService> signedInAuth({http.Client? signInFunction}) async {
  final store = MemoryTokenStore();
  await store.write(freshTokens());
  return AuthService(
    config: testConfig,
    tokenStore: store,
    httpClient: signInFunction ?? MockClient((request) async => http.Response('unexpected', 500)),
    clock: () => testNow,
  );
}

/// A fresh, empty database in its own temporary file, so tests never share
/// data.
Future<LocalDatabase> emptyDatabase() {
  sqfliteFfiInit();
  final folder = Directory.systemTemp.createTempSync('purlnote_test_');
  return LocalDatabase.open(factory: databaseFactoryFfi, path: '${folder.path}/test.db');
}

/// A sync engine (with its outbox) talking to [ravelryHttp] on the test clock.
SyncEngine syncEngineFor({
  required http.Client ravelryHttp,
  required LocalDatabase database,
  required AuthService auth,
  DateTime Function()? clock,
}) {
  final ravelry = RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: auth, httpClient: ravelryHttp);
  final now = clock ?? () => testNow;
  return SyncEngine(
    ravelry: ravelry,
    database: database,
    outbox: Outbox(ravelry: ravelry, database: database, clock: now),
    clock: now,
  );
}

/// Makes the test screen [size] logical pixels, as a phone or iPad of that
/// size would report it, until the test ends. Layouts that depend on the
/// screen width (the iPad's side rail and two columns) read this size.
void useScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
