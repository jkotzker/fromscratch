import Foundation

/// Waits until `condition` holds, checking every 10 ms, and gives up after `timeout`. The stores'
/// debounce timers run on the main actor, which every app-layer test also uses, so a fixed sleep
/// can end before a timer has had its turn; this waits for the effect instead.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}
