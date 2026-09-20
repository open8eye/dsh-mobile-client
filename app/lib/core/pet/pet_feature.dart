/// Whether the floating companion is offered anywhere in the UI.
///
/// The feature works, but it is on hold: a character floating over the launcher
/// is the first thing a new user would see, and it is not good enough yet to be
/// that. Nothing was deleted — the platform channel, the Android overlay
/// service, the settings fields and the whole preferences section are still
/// here and still compiled — so bringing it back is a one-line change.
///
/// Deliberately a getter and not a \`const\`: the analyzer folds \`if (false)\`
/// into dead code, and a section the analyzer stops checking is a section that
/// rots.
abstract final class PetFeature {
  static bool get available => false;
}
