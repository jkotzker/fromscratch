@testable import FromScratch

/// App-layer tests make no sound: every suite's init calls this. A test that expects a beep
/// counts it with `beeps(during:)`.
@MainActor
func silenceFeedback() {
    Feedback.beep = {}
}

/// How many times `body` beeped. Synchronous, so no other test can beep in between.
@MainActor
func beeps(during body: () throws -> Void) rethrows -> Int {
    var count = 0
    Feedback.beep = { count += 1 }
    defer { silenceFeedback() }
    try body()
    return count
}
