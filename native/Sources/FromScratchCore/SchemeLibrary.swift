import Foundation

// Port of discoverSchemes (src/main/themes.js) and resolveScheme (src/main/index.js).

public struct Scheme: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let colors: ParsedScheme

    public init(id: String, name: String, colors: ParsedScheme) {
        self.id = id
        self.name = name
        self.colors = colors
    }

    /// Built-ins are expressed as sRGB declared colours so every scheme has one colour type.
    init(builtIn: BuiltInScheme) {
        func declared(_ c: RGB) -> DeclaredColor {
            DeclaredColor(space: .sRGB, r: Double(c.r) / 255, g: Double(c.g) / 255, b: Double(c.b) / 255)
        }
        self.init(
            id: builtIn.id, name: builtIn.name,
            colors: ParsedScheme(
                background: declared(builtIn.colors.background),
                foreground: declared(builtIn.colors.foreground)))
    }

    public var palette: Palette { derivePalette(colors.schemeColors) }
    public var isDark: Bool { palette.isDark }
}

public struct SchemeLibrary {
    public static let themesDirname = "themes"

    private let themesDirectory: URL
    public private(set) var all: [Scheme] = []

    /// `themesDirectory` is the folder holding the `.itermcolors` files (`<data dir>/themes`).
    public init(themesDirectory: URL) {
        self.themesDirectory = themesDirectory
        rescan()
    }

    /// Built-ins first, then every readable theme file in name order. The folder is created when
    /// missing so there is somewhere obvious to drop files; a bad file is skipped, not fatal.
    public mutating func rescan() {
        var schemes = [Scheme(builtIn: .dark), Scheme(builtIn: .light)]
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
            let names = try fm.contentsOfDirectory(atPath: themesDirectory.path)
                .filter { $0.lowercased().hasSuffix(".itermcolors") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            for entry in names {
                let url = themesDirectory.appendingPathComponent(entry)
                guard let data = try? Data(contentsOf: url), let parsed = parseItermColors(data) else {
                    continue
                }
                let name = String(entry.dropLast(".itermcolors".count))
                schemes.append(Scheme(id: "file:\(name)", name: name, colors: parsed))
            }
        } catch {
            // Directory could not be created or read: built-ins only, like v2.
        }
        all = schemes
    }

    /// An unknown id falls back to the first built-in. Pure: the stored setting is left alone.
    public func resolve(id: String) -> Scheme {
        all.first { $0.id == id } ?? all[0]
    }
}
