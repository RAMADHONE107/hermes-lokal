/// Defaults for a Hermes engine running on the same Android device.
///
/// The engine lives in a proot Ubuntu rootfs started from Termux. proot uses
/// the host network namespace, so its gateway is reachable from this app on
/// loopback without exposing any port to the LAN.
class LocalHermes {
  static const host = '127.0.0.1';
  static const port = 8642;
  static const dashboardPort = 9119;

  static const label = 'Hermes Lokal';
  static const setupHint =
      'Termux: bash ~/hermes-lokal/scripts/install-local-hermes.sh';
}
