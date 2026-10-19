import Foundation
import CoreGraphics

public struct FontSetting: Equatable, Sendable {
    /// nil means the bundled face (v2 stores the literal family "FiraCode" for it).
    public var family: String?
    public var size: Int
    /// PostScript name of a non-Regular face. Stored in its own key so v2's `font` stays readable.
    public var face: String?

    public static let bundledFamily = "FiraCode"
    public static let defaultSize = 16
    public static let sizeRange = 8...72

    public init(family: String? = nil, size: Int = FontSetting.defaultSize, face: String? = nil) {
        self.family = family == Self.bundledFamily ? nil : family
        self.size = Self.clamp(Double(size))
        self.face = face
    }

    /// Mirrors clampFontSize in the v2 renderer: round, then clamp to 8...72.
    public static func clamp(_ size: Double) -> Int {
        guard size.isFinite else { return defaultSize }
        let r = size.rounded(.toNearestOrAwayFromZero)
        return Int(min(max(r, Double(sizeRange.lowerBound)), Double(sizeRange.upperBound)))
    }
}

public struct WindowState: Equatable, Sendable {
    /// Electron coordinates (the same convention v2 wrote), so a v2 reinstall can read them back.
    public var bounds: CGRect?
    public var isMaximized: Bool

    public init(bounds: CGRect? = nil, isMaximized: Bool = false) {
        self.bounds = bounds
        self.isMaximized = isMaximized
    }
}

/// settings.json, shared with the Electron v2 app. The whole document is kept as JSON values and
/// typed accessors read and write into it: unknown keys are never dropped, and a wrongly typed
/// value falls back to its default without being altered until that property is set.
@MainActor
public final class SettingsStore {
    public static let fileName = "settings.json"
    static let version = 1
    // The per-key files node-localstorage left behind (see LEGACY_KEYS in src/main/storage.js).
    static let legacyKeys = ["windowstate", "folds2", "fontSize", "lightTheme", "hideUpdateMessage"]
    static let remBasePx = 16.0
    public static let defaultScheme = "built-in:dark"

    private let directory: URL
    private let debounce: Duration
    private var data: [String: JSONValue] = [:]
    private var timer: Task<Void, Never>?
    private var fileWritesEnabled = true

    public var raw: [String: JSONValue] { data }
    private var settingsURL: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL, debounce: Duration = .milliseconds(250)) {
        self.directory = directory
        self.debounce = debounce
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let existing = Self.readJSON(settingsURL), case .object(let obj) = existing {
            data = obj
            return
        }
        // Present but unparseable: keep it rather than overwrite it, so it can be recovered by hand.
        // An earlier backup is never replaced, and if the original cannot be moved aside the file is
        // left alone for the rest of this run (settings stay in memory only).
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = Self.backupURL(in: directory)
            do {
                try FileManager.default.moveItem(at: settingsURL, to: backup)
            } catch {
                fileWritesEnabled = false
                NSLog("Could not preserve the unreadable settings file; not writing settings this run: \(error)")
            }
        }
        data = Self.migrateLegacy(directory)
        write()
    }

    // MARK: Typed accessors

    public var font: FontSetting {
        get {
            let obj = data["font"]?.objectValue
            var family = obj?["family"]?.stringValue
            if family == FontSetting.bundledFamily { family = nil }
            let size = obj?["size"]?.numberValue.map(FontSetting.clamp) ?? FontSetting.defaultSize
            return FontSetting(family: family, size: size, face: data["fontFace"]?.stringValue)
        }
        set {
            // Merge into the existing object so unknown sub-keys written by another version survive.
            var obj = data["font"]?.objectValue ?? [:]
            let family = newValue.family == FontSetting.bundledFamily ? nil : newValue.family
            obj["family"] = family.map(JSONValue.string) ?? .null
            obj["size"] = .number(Double(FontSetting.clamp(Double(newValue.size))))
            data["font"] = .object(obj)
            if let face = newValue.face { data["fontFace"] = .string(face) } else { data["fontFace"] = nil }
            schedule()
        }
    }

    public var colorSchemeId: String {
        get { data["colorScheme"]?.stringValue ?? Self.defaultScheme }
        set { data["colorScheme"] = .string(newValue); schedule() }
    }

    public var highlightCurrentLine: Bool {
        get { data["highlightCurrentLine"]?.boolValue ?? true }
        set { data["highlightCurrentLine"] = .bool(newValue); schedule() }
    }

    public var windowState: WindowState {
        get {
            let obj = data["windowstate"]?.objectValue
            var rect: CGRect?
            if let b = obj?["bounds"]?.objectValue,
               let x = b["x"]?.numberValue, let y = b["y"]?.numberValue,
               let w = b["width"]?.numberValue, let h = b["height"]?.numberValue {
                rect = CGRect(x: x, y: y, width: w, height: h)
            }
            return WindowState(bounds: rect, isMaximized: obj?["isMaximized"]?.boolValue ?? false)
        }
        set {
            var obj = data["windowstate"]?.objectValue ?? [:]
            if let r = newValue.bounds {
                obj["bounds"] = .object([
                    "x": .number(r.origin.x), "y": .number(r.origin.y),
                    "width": .number(r.size.width), "height": .number(r.size.height),
                ])
            } else {
                obj["bounds"] = nil
            }
            obj["isMaximized"] = .bool(newValue.isMaximized)
            data["windowstate"] = .object(obj)
            schedule()
        }
    }

    public var hiddenUpdateVersion: String? {
        get { data["hideUpdateMessage"]?.objectValue?["version"]?.stringValue }
        set {
            if let v = newValue { data["hideUpdateMessage"] = .object(["version": .string(v)]) }
            else { data["hideUpdateMessage"] = nil }
            schedule()
        }
    }

    // MARK: Writing

    /// Writes immediately and cancels any pending debounced write.
    public func flush() {
        timer?.cancel()
        timer = nil
        write()
    }

    // Like v2, the first change starts the timer and later changes ride on it.
    private func schedule() {
        guard timer == nil else { return }
        timer = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.timer = nil
            self.write()
        }
    }

    /// settings.json.corrupt, or a timestamped variant when that name is taken.
    private static func backupURL(in directory: URL) -> URL {
        let base = directory.appendingPathComponent(fileName + ".corrupt")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        var candidate = directory.appendingPathComponent("\(fileName).corrupt-\(stamp)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(fileName).corrupt-\(stamp)-\(n)")
            n += 1
        }
        return candidate
    }

    private func write() {
        guard fileWritesEnabled else { return }
        var doc = ["version": JSONValue.number(Double(Self.version))]
        doc.merge(data) { _, stored in stored }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            // prettyPrinted uses 2 spaces, matching JSON.stringify(_, null, 2).
            try encoder.encode(doc).write(to: settingsURL, options: .atomic)
        } catch {
            NSLog("Could not write settings: \(error)")
        }
    }

    // MARK: Reading

    private static func readJSON(_ url: URL) -> JSONValue? {
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: bytes)
    }

    /// Build a document from the per-key files v1/v2 left behind. They are never deleted.
    private static func migrateLegacy(_ directory: URL) -> [String: JSONValue] {
        var migrated: [String: JSONValue] = ["version": .number(Double(version))]
        for key in legacyKeys {
            guard let value = readJSON(directory.appendingPathComponent(key)) else { continue }
            switch key {
            case "fontSize":
                // A 0.5-2.5 rem multiplier becomes an absolute pixel size.
                if let m = value.numberValue {
                    migrated["font"] = .object([
                        "family": .null,
                        "size": .number((m * remBasePx).rounded(.toNearestOrAwayFromZero)),
                    ])
                }
            case "lightTheme":
                migrated["colorScheme"] = .string(value.boolValue == true || (value.numberValue ?? 0) != 0
                    ? "built-in:light" : "built-in:dark")
            default:
                migrated[key] = value
            }
        }
        return migrated
    }
}
