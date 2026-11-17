/// Defaults for the Hermes engine that lives inside this APK.
///
/// The runtime is downloaded once into the app's private storage and its
/// gateway listens on loopback only, so no other app or device can reach it.
class LocalHermes {
  static const host = '127.0.0.1';
  static const port = 8642;
  static const dashboardPort = 9119;

  static const label = 'Hermes Lokal';
  static const setupHint = 'Mesin berjalan di dalam aplikasi ini';
}
