import Foundation

/// Atomic, versioned persistence for MetaState (GOAL §5).
/// JSON in Application Support — no UserDefaults for game data.
public enum SaveStore {
    public static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("NeonHorde", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("meta.json")
    }

    public static func load() -> MetaState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(MetaState.self, from: data) else {
            return MetaState()
        }
        // Future schema migrations branch on state.schemaVersion here.
        return state
    }

    @discardableResult
    public static func save(_ state: MetaState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
