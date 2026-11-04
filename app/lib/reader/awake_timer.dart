import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while the knitter reads, so the page doesn't go dark
/// between looking up and back down.
///
/// Each pattern has its own setting. The timer restarts on every touch;
/// leaving the reader or locking the phone always lets the screen sleep.
class AwakeTimer {
  AwakeTimer({Future<void> Function(bool on)? setScreenOn}) : _setScreenOn = setScreenOn ?? _setWakelock;

  final Future<void> Function(bool on) _setScreenOn;
  Timer? _timer;
  int _minutes = defaultMinutes;

  /// Minutes, or [off], or [whileOpen].
  static const off = 0;
  static const whileOpen = -1;
  static const defaultMinutes = 10;

  /// The choices offered, in order.
  static const choices = [off, 10, 30, 60, 120, whileOpen];

  int get minutes => _minutes;

  /// Starts (or changes) the timer with a pattern's setting.
  void start(int minutes) {
    _minutes = minutes;
    touched();
  }

  /// Call on every touch in the reader.
  void touched() {
    _timer?.cancel();
    if (_minutes == off) {
      _setScreenOn(false);
      return;
    }
    _setScreenOn(true);
    if (_minutes > 0) {
      _timer = Timer(Duration(minutes: _minutes), () => _setScreenOn(false));
    }
  }

  /// Lets the screen sleep again. Call when leaving the reader.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _setScreenOn(false);
  }

  /// How a setting is written on the reader's chip and in its menu.
  static String describe(int minutes) {
    return switch (minutes) {
      off => 'Off (phone setting)',
      whileOpen => 'While open',
      60 => '1 hour',
      120 => '2 hours',
      _ => '$minutes min',
    };
  }

  static Future<void> _setWakelock(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();
}
