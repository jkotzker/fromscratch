import AppKit

/// The alert sound for a refused or invalid action. Every beep goes through here so tests can
/// count it instead of playing it.
@MainActor
enum Feedback {
    static var beep: () -> Void = { NSSound.beep() }
}
