import Foundation

/// content.txt, the scratchpad text. Bytes in equal bytes out: no normalisation, no trailing newline.
/// Mirrors readContent/writeContent/flushContent in src/main/storage.js: the first change starts the
/// timer and later changes only replace the pending text.
@MainActor
public final class ContentStore {
    public static let fileName = "content.txt"

    /// What the editor starts with. For an undecodable file this is a lossy rendering for display only.
    public let initialText: String
    /// True when content.txt exists but is not valid UTF-8 (or cannot be read). It is never written.
    public let isReadOnly: Bool

    private let directory: URL
    private let debounce: Duration
    private let retryDelay: Duration
    private var pending: String?
    private var timer: Task<Void, Never>?
    // Sudden termination is a counted system resource, so it is disabled exactly once per
    // no-pending -> pending transition and re-enabled exactly once when pending is cleared.
    // `suddenTerminationDisabled` is the single source of truth for that pairing.
    private var suddenTerminationDisabled = false
    /// Calls to disableSuddenTermination minus calls to enableSuddenTermination; 0 when balanced.
    private(set) var suddenTerminationBalance = 0

    public var hasPendingWrite: Bool { pending != nil }
    /// Why the most recent write failed; nil once a write succeeds. For telling the user on quit.
    public private(set) var lastWriteError: (any Error)?
    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    /// The armed debounce or retry timer. Tests await it rather than poll the clock: the timer
    /// runs on the main actor, which other work can hold for longer than any fixed deadline.
    var pendingTimer: Task<Void, Never>? { timer }

    /// `retryDelay` is how long a failed write waits before trying again on its own.
    public init(directory: URL, debounce: Duration = .milliseconds(250), retryDelay: Duration = .seconds(2)) {
        self.directory = directory
        self.debounce = debounce
        self.retryDelay = retryDelay
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            initialText = ""
            isReadOnly = false
            return
        }
        do {
            let bytes = try Data(contentsOf: url)
            if let text = String(data: bytes, encoding: .utf8) {
                initialText = text
                isReadOnly = false
            } else {
                // Show what can be shown, but never let it replace the original bytes.
                initialText = String(decoding: bytes, as: UTF8.self)
                isReadOnly = true
            }
        } catch {
            // Present but unreadable: writing would destroy data we could not see.
            NSLog("%@", "Could not read content: \(error)")
            initialText = ""
            isReadOnly = true
        }
    }

    public func scheduleWrite(_ text: String) {
        guard !isReadOnly else { return }
        pending = text
        beginPending()
        guard timer == nil else { return }
        arm(after: debounce)
    }

    // As in v2, a change arriving while a timer is armed rides on it; after a failed write the
    // retry timer plays the same part.
    private func arm(after delay: Duration) {
        timer = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.timer = nil
            self.writePending()
        }
    }

    /// Writes any pending text now and cancels the timer.
    public func flush() {
        timer?.cancel()
        timer = nil
        writePending()
    }

    private func writePending() {
        guard let text = pending else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // v2's writeFileSync followed a symlinked content.txt; an atomic write to the link's
            // own path would replace the link with a regular file, so write to its target.
            try Data(text.utf8).write(to: fileURL.resolvingSymlinksInPath(), options: .atomic)
        } catch {
            // Keep the text pending and try again on our own: with no further typing, nothing
            // else would write it before quit. Sudden termination stays disabled meanwhile.
            NSLog("%@", "Could not write content: \(error)")
            lastWriteError = error
            if timer == nil { arm(after: retryDelay) }
            return
        }
        lastWriteError = nil
        pending = nil
        endPending()
    }

    // So the system must ask the app to quit (letting applicationShouldTerminate flush) while text
    // is unsaved, instead of killing the process outright.
    private func beginPending() {
        guard !suddenTerminationDisabled else { return }
        suddenTerminationDisabled = true
        suddenTerminationBalance += 1
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    private func endPending() {
        guard suddenTerminationDisabled else { return }
        suddenTerminationDisabled = false
        suddenTerminationBalance -= 1
        ProcessInfo.processInfo.enableSuddenTermination()
    }
}
