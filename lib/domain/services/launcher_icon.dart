/// The home-screen icon follows the chosen mascot ("Pilih maskot").
abstract interface class LauncherIcon {
  /// Switches the launcher icon to the mascot with this `MascotKind.id`; a
  /// no-op when it already is. False where unsupported or refused.
  Future<bool> apply(String mascotId);
}
