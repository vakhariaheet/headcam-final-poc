import 'dart:developer' as developer;

/// Roughly follows `dart:developer`'s own level scale (info ~800,
/// warning ~900, severe/error ~1000) so log output sorts/filters sensibly
/// in DevTools and IDE debug consoles.
abstract class _LogLevel {
  static const int debug = 500;
  static const int info = 800;
  static const int warning = 900;
  static const int error = 1000;
}

/// The one logging entry point for this app. Every catch block that would
/// otherwise swallow an exception silently should log through here instead
/// — `dart:developer`'s `log()`, not `print()`, since it carries a level
/// and an optional error/stack trace, shows up structured in DevTools, and
/// is what Effective Dart recommends over `print()` for anything beyond a
/// one-off debug statement.
class AppLogger {
  const AppLogger._();

  static void debug(String message, {String name = 'app'}) {
    _log(message, name: name, level: _LogLevel.debug);
  }

  static void info(String message, {String name = 'app'}) {
    _log(message, name: name, level: _LogLevel.info);
  }

  static void warning(
    String message, {
    String name = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      message,
      name: name,
      level: _LogLevel.warning,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String message, {
    String name = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      message,
      name: name,
      level: _LogLevel.error,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _log(
    String message, {
    required String name,
    required int level,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: name,
      level: level,
      error: error,
      stackTrace: stackTrace,
      time: DateTime.now(),
    );
  }
}
