import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/local_hermes.dart';

void main() {
  test('on-device defaults stay on loopback and use the stock ports', () {
    expect(LocalHermes.host, '127.0.0.1');
    expect(LocalHermes.port, 8642);
    expect(LocalHermes.dashboardPort, 9119);
    expect(LocalHermes.label, 'Hermes Lokal');
  });
}
