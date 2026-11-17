import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/local_engine.dart';

void main() {
  test('channel names are stable across native and Dart', () {
    expect(
      LocalEngineClient.methodChannelName,
      'com.hermesagent.hermes_android/hermes_engine',
    );
    expect(
      LocalEngineClient.eventChannelName,
      'com.hermesagent.hermes_android/hermes_engine_events',
    );
  });

  test('status maps are parsed defensively', () {
    final status = LocalEngineStatus.fromMap({
      'state': 'downloading',
      'progress': 42,
      'message': 'Mengunduh runtime',
      'version': 'local-1',
    });
    expect(status.state, LocalEngineState.downloading);
    expect(status.progress, 42);
    expect(status.message, 'Mengunduh runtime');
    expect(status.version, 'local-1');

    final unknown = LocalEngineStatus.fromMap({'state': 'future-state'});
    expect(unknown.state, LocalEngineState.error);
    expect(unknown.progress, 0);
  });

  test('busy states cover transitional phases only', () {
    expect(LocalEngineState.downloading.isBusy, true);
    expect(LocalEngineState.extracting.isBusy, true);
    expect(LocalEngineState.configuring.isBusy, true);
    expect(LocalEngineState.stopping.isBusy, true);
    expect(LocalEngineState.ready.isBusy, false);
    expect(LocalEngineState.running.isBusy, false);
    expect(LocalEngineState.error.isBusy, false);
  });
}
