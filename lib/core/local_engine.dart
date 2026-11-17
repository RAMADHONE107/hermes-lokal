import 'dart:async';

import 'package:flutter/services.dart';

/// Runtime states reported by the native engine controller.
enum LocalEngineState {
  absent,
  downloading,
  extracting,
  configuring,
  ready,
  running,
  stopping,
  error,
}

extension LocalEngineStateX on LocalEngineState {
  bool get isBusy => switch (this) {
    LocalEngineState.downloading ||
    LocalEngineState.extracting ||
    LocalEngineState.configuring ||
    LocalEngineState.stopping => true,
    _ => false,
  };

  String get label => switch (this) {
    LocalEngineState.absent => 'Belum disiapkan',
    LocalEngineState.downloading => 'Mengunduh runtime',
    LocalEngineState.extracting => 'Mengekstrak runtime',
    LocalEngineState.configuring => 'Menyiapkan mesin',
    LocalEngineState.ready => 'Siap',
    LocalEngineState.running => 'Berjalan',
    LocalEngineState.stopping => 'Menghentikan',
    LocalEngineState.error => 'Error',
  };
}

class LocalEngineStatus {
  final LocalEngineState state;
  final int progress;
  final String message;
  final String? version;

  const LocalEngineStatus({
    required this.state,
    required this.progress,
    required this.message,
    this.version,
  });

  factory LocalEngineStatus.fromMap(Object? raw) {
    final map = raw as Map;
    return LocalEngineStatus(
      state: LocalEngineState.values.firstWhere(
        (candidate) => candidate.name == map['state'],
        orElse: () => LocalEngineState.error,
      ),
      progress: (map['progress'] as num?)?.toInt() ?? 0,
      message: map['message'] as String? ?? '',
      version: map['version'] as String?,
    );
  }
}

class LocalEngineException implements Exception {
  final String message;

  const LocalEngineException(this.message);

  @override
  String toString() => 'LocalEngineException: $message';
}

/// Dart side of the embedded Hermes engine.
class LocalEngineClient {
  static const methodChannelName =
      'com.hermesagent.hermes_android/hermes_engine';
  static const eventChannelName =
      'com.hermesagent.hermes_android/hermes_engine_events';

  LocalEngineClient({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _method = methodChannel ?? const MethodChannel(methodChannelName),
      _events = eventChannel ?? const EventChannel(eventChannelName) {
    _status = _events
        .receiveBroadcastStream()
        .map((event) => LocalEngineStatus.fromMap(event))
        .asBroadcastStream();
  }

  static final instance = LocalEngineClient();

  final MethodChannel _method;
  final EventChannel _events;
  late final Stream<LocalEngineStatus> _status;

  Stream<LocalEngineStatus> get status => _status;

  Future<LocalEngineStatus> currentStatus() async {
    final raw = await _call<Map<dynamic, dynamic>>('status');
    return LocalEngineStatus.fromMap(raw);
  }

  Future<String> apiKey() async {
    final value = await _call<String>('apiKey');
    if (value.isEmpty) {
      throw const LocalEngineException('API key belum tersedia');
    }
    return value;
  }

  Future<void> prepare() => _callVoid('prepare');

  Future<void> start() => _callVoid('start');

  Future<void> stop() => _callVoid('stop');

  Future<String> logTail({int maxLines = 200}) =>
      _call<String>('logTail', <String, Object>{'maxLines': maxLines});

  Future<void> _callVoid(String method, [Object? arguments]) async {
    try {
      await _method.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      throw const LocalEngineException('Mesin tidak tersedia di build ini');
    } on PlatformException catch (error) {
      throw LocalEngineException(error.message ?? error.code);
    }
  }

  Future<T> _call<T>(String method, [Object? arguments]) async {
    try {
      final value = await _method.invokeMethod<T>(method, arguments);
      final result = value;
      if (result == null)
        throw const LocalEngineException('Respons kosong dari mesin');
      return result;
    } on MissingPluginException {
      throw const LocalEngineException('Mesin tidak tersedia di build ini');
    } on PlatformException catch (error) {
      throw LocalEngineException(error.message ?? error.code);
    }
  }
}
