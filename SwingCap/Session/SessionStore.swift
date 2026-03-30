import Foundation
import Observation
import SwiftData

/// Persists driving-range sessions across app launches using SwiftData.
///
/// Inject via the SwiftUI environment:
/// ```swift
/// @main struct SwingCapApp: App {
///     @State private var store = SessionStore()
///     var body: some Scene {
///         WindowGroup { SessionView().environment(store) }
///     }
/// }
/// ```
@Observable
final class SessionStore {

    // MARK: - Public state

    /// Past sessions, newest first.
    private(set) var pastSessions: [PersistedSession] = []

    // MARK: - Private

    private let container: ModelContainer
    private let context: ModelContext

    // MARK: - Init

    init() {
        let schema = Schema([PersistedSession.self, PersistedClip.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // Force-try is acceptable here: if the container can't be created the
        // app has a fatal configuration problem (e.g. corrupt store).
        let container = try! ModelContainer(for: schema, configurations: config)
        self.container = container
        self.context = ModelContext(container)
        fetchSessions()
        cleanOrphanedFiles()
    }

    // MARK: - Session lifecycle

    /// Creates a new `PersistedSession` for an active `DrivingSession` and
    /// returns it. Call this when the session begins so clips can be appended
    /// incrementally as they are captured.
    @discardableResult
    func beginSession(startedAt: Date = Date()) -> PersistedSession {
        let record = PersistedSession(startedAt: startedAt)
        context.insert(record)
        save()
        fetchSessions()
        return record
    }

    /// Appends a newly exported `Clip` to an existing `PersistedSession`.
    func addClip(_ clip: Clip, to session: PersistedSession) {
        let record = PersistedClip(from: clip)
        session.clips.append(record)
        save()
        fetchSessions()
    }

    /// Deletes a session and all its clips from the store.
    func delete(_ session: PersistedSession) {
        context.delete(session)
        save()
        fetchSessions()
    }

    // MARK: - Private

    private func save() {
        try? context.save()
    }

    private func fetchSessions() {
        let descriptor = FetchDescriptor<PersistedSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        pastSessions = (try? context.fetch(descriptor)) ?? []
    }

    private func cleanOrphanedFiles() {
        let known = Set(pastSessions.flatMap { $0.clips.map(\.fileName) })
        ClipStorageManager.deleteOrphanedFiles(knownFileNames: known)
    }
}
