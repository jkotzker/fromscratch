import Foundation

public enum DataLocation {
    /// Release builds use `<home>/.fromscratch`. Debug builds use `<home>/.fromscratch/dev`
    /// unless `FROMSCRATCH_DATA_DIR` is set; release builds ignore that variable.
    public static func directory(environment: [String: String], isDebug: Bool, home: URL) -> URL {
        let root = home.appendingPathComponent(".fromscratch", isDirectory: true)
        guard isDebug else { return root }
        if let override = environment["FROMSCRATCH_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return root.appendingPathComponent("dev", isDirectory: true)
    }
}
