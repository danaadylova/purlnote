import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/ravelry/models.dart';

void main() {
  test('a project reads its name, status, progress, dates and photo', () {
    final project = Project.fromJson({
      'id': 10,
      'name': 'Harbour Raglan',
      'pattern_name': 'Harbour Raglan Pullover',
      'status_name': 'In progress',
      'progress': 40,
      'started': '2026/09/14',
      'completed': '',
      'first_photo': {'small_url': 'https://images.example/small.jpg'},
    });

    expect(project.name, 'Harbour Raglan');
    expect(project.patternName, 'Harbour Raglan Pullover');
    expect(project.isOnTheNeedles, isTrue);
    expect(project.progressPercent, 40);
    expect(project.started, DateTime(2026, 9, 14));
    expect(project.completed, isNull, reason: 'Ravelry sends empty strings for unset fields');
    expect(project.photoUrl, 'https://images.example/small.jpg');
  });

  test('a project with almost nothing set still works', () {
    final project = Project.fromJson({'id': 1, 'name': '  '});
    expect(project.name, 'Untitled project');
    expect(project.isOnTheNeedles, isFalse);
    expect(project.progressPercent, isNull);
    expect(project.photoUrl, isNull);
  });

  test('dates with a time and offset keep just the day', () {
    final project = Project.fromJson({'id': 1, 'name': 'Socks', 'updated_at': '2026/11/04 13:37:23 -0500'});
    expect(project.updatedAt, DateTime(2026, 11, 4));
  });

  test('a stash yarn prefers the catalogue name and company', () {
    final yarn = StashYarn.fromJson({
      'id': 30,
      'name': 'my label',
      'colorway_name': 'Azul Profundo',
      'yarn_weight_name': 'Worsted',
      'yarn': {'name': 'Rios', 'yarn_company_name': 'Malabrigo Yarn'},
    });
    expect(yarn.name, 'Rios');
    expect(yarn.companyName, 'Malabrigo Yarn');
    expect(yarn.colorway, 'Azul Profundo');
    expect(yarn.weightName, 'Worsted');
  });

  test('a queued project uses the short pattern name', () {
    final item = QueuedProject.fromJson({'id': 20, 'short_pattern_name': 'Fennel Socks', 'position_in_queue': 2});
    expect(item.patternName, 'Fennel Socks');
    expect(item.position, 2);
  });

  test('the user is greeted by first name when there is one', () {
    expect(RavelryUser.fromJson({'id': 1, 'username': 'unraveled-makes', 'first_name': 'Dana'}).displayName, 'Dana');
    expect(RavelryUser.fromJson({'id': 1, 'username': 'unraveled-makes'}).displayName, 'unraveled-makes');
  });
}
