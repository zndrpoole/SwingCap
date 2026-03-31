import Foundation
import Observation
import SwiftData

/// Persists driving-range sessions across app launches using SwiftData.
///
/// ## Injection
/// Created once in `SwingCapApp` and pushed into the environment:
/// ```swift
/// @main struct SwingCapApp: App {
///     @State private var store = SessionStore()
///     var body: some Scene {
///         WindowGroup { SessionView().environment(store) }
///     }
/// }
/// ```
/// Child views that need it declare `@Environment(SessionStore.self)`.
///
/// ## Schema
/// `PersistedSession` → (cascade) `PersistedClip`.
/// Deleting a session deletes all its clips automatically (cascade rule).
///
/// ## Orphan cleanup
/// On init, `cleanOrphanedFiles()` removes MP4 files from disk that have no
/// matching `PersistedClip` record — handles the edge case where the app
/// crashed after writing a file but before persisting its SwiftData record.
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
    /// Called by `SessionView.persistLatestClip()` each time `session.clips` grows.
    func addClip(_ clip: Clip, to session: PersistedSession) {
        let record = PersistedClip(from: clip)
        session.clips.append(record)
        save()
        fetchSessions()
    }

    /// Updates the shot rating on the `PersistedClip` matching `clip`.
    /// Called by `DrivingSession` (gesture) and `ClipPlayerView` (manual tap).
    func updateRating(_ rating: ShotRating?, for clip: Clip) {
        let record = pastSessions
            .flatMap { $0.clips }
            .first { $0.id == clip.id }
        guard let record else { return }
        record.rating = rating
        save()
    }

    /// Updates the user-written note on the `PersistedClip` matching `clip`.
    /// Called by `ClipPlayerView` on dismiss and when the user submits the
    /// notes text field.
    func updateNotes(_ notes: String, for clip: Clip) {
        let record = pastSessions
            .flatMap { $0.clips }
            .first { $0.id == clip.id }
        guard let record else { return }
        record.notes = notes
        save()
    }

    /// Returns the persisted rating for `clip`, or `nil` if not found or unrated.
    func rating(for clip: Clip) -> ShotRating? {
        pastSessions
            .flatMap { $0.clips }
            .first { $0.id == clip.id }
            .flatMap { $0.rating }
    }

    /// Returns the persisted notes for `clip`, or `nil` if the clip record
    /// cannot be found (e.g. a clip that was never persisted in the first place).
    func notes(for clip: Clip) -> String? {
        pastSessions
            .flatMap { $0.clips }
            .first { $0.id == clip.id }
            .map { $0.notes }
    }

    /// Removes the `PersistedClip` record matching `clip` from whichever
    /// session owns it. Does not delete the file from disk — callers are
    /// responsible for removing the MP4 before or after calling this.
    func removeClip(_ clip: Clip) {
        let match = pastSessions
            .flatMap { $0.clips }
            .first { $0.id == clip.id }
        guard let record = match else { return }
        context.delete(record)
        save()
        fetchSessions()
    }

    /// Deletes a session and all its clips from the store.
    /// The cascade delete rule on `PersistedSession.clips` ensures all
    /// `PersistedClip` records are removed automatically.
    func delete(_ session: PersistedSession) {
        context.delete(session)
        save()
        fetchSessions()
    }

    // MARK: - Private

    private func save() {
        try? context.save()
    }

    /// Re-fetches all sessions from SwiftData, sorted newest first, and
    /// updates `pastSessions` so any observing view re-renders.
    private func fetchSessions() {
        let descriptor = FetchDescriptor<PersistedSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        pastSessions = (try? context.fetch(descriptor)) ?? []
    }

    /// Removes MP4 files from disk that have no corresponding `PersistedClip`
    /// record. Called once at init to clean up after crashes or incomplete writes.
    private func cleanOrphanedFiles() {
        let known = Set(pastSessions.flatMap { $0.clips.map(\.fileName) })
        ClipStorageManager.deleteOrphanedFiles(knownFileNames: known)
    }
}
