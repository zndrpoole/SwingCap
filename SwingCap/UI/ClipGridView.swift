import SwiftUI

/// Scrollable grid of clip thumbnails for post-session review.
///
/// ## Two initialisers
///
/// - `init(session:)` — live active session. `displayedClips` reads from
///   `liveSession.clips` which is `@Observable`, so the grid automatically
///   updates as clips are added during the session.
///
/// - `init(clips:title:)` — static snapshot for history playback. Clips are
///   stored in a `@State` array (`staticClips`) so deletions can update the
///   grid immediately without needing a live session reference.
///
/// ## Deletion
///
/// `deleteClip(_:)` performs three operations in order:
/// 1. Removes the MP4 file from disk.
/// 2. Removes the `Clip` from the live session's in-memory array (no-op for
///    the static path).
/// 3. Removes the `PersistedClip` SwiftData record via `SessionStore`.
/// 4. Removes the clip from `staticClips` so the history grid refreshes.
struct ClipGridView: View {

    private let title: String
    /// When non-nil, the grid is backed by a live session and stays reactive.
    private let liveSession: DrivingSession?
    /// Mutable copy for the static (history) path so deletions update the grid.
    @State private var staticClips: [Clip]

    @State private var selectedClip: Clip?
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    // Live session init (active session review)
    init(session: DrivingSession) {
        self.liveSession = session
        self._staticClips = State(initialValue: [])   // unused — body reads liveSession
        self.title = "Clips"
    }

    // Static init (history viewer)
    init(clips: [Clip], title: String = "Clips") {
        self.liveSession = nil
        self._staticClips = State(initialValue: clips)
        self.title = title
    }

    /// Returns the appropriate clip source depending on which init was used.
    private var displayedClips: [Clip] {
        liveSession?.clips ?? staticClips
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if displayedClips.isEmpty {
                    emptyState
                } else {
                    clipGrid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedClip) { clip in
            ClipPlayerView(clip: clip, liveSession: liveSession)
        }
    }

    // MARK: - Subviews

    private var clipGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(displayedClips) { clip in
                    ClipThumbnailCell(clip: clip)
                        .onTapGesture { selectedClip = clip }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteClip(clip)
                            } label: {
                                Label("Delete Clip", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(16)
        }
    }

    /// Deletes a clip from disk, the live session (if applicable), SwiftData,
    /// and the local `staticClips` array (for the history path).
    private func deleteClip(_ clip: Clip) {
        // Remove the MP4 file from disk
        try? FileManager.default.removeItem(at: clip.url)
        // Remove from live session in-memory state
        liveSession?.removeClip(clip)
        // Remove the persisted SwiftData record
        sessionStore.removeClip(clip)
        // Update the static list (no-op for live sessions)
        staticClips.removeAll { $0.id == clip.id }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            Text("No clips yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Start swinging — clips appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Thumbnail cell

private struct ClipThumbnailCell: View {

    let clip: Clip

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailImage
                .resizable()
                .scaledToFill()
                .frame(height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Duration label (bottom-right)
            Text(String(format: "%.1fs", clip.duration))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(6)
        }
        // Rating badge (top-left) — only shown when rated
        .overlay(alignment: .topLeading) {
            if let rating = clip.rating {
                Text(rating == .good ? "👍" : "👎")
                    .font(.system(size: 18))
                    .padding(5)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: clip.rating != nil ? 2 : 1)
        }
    }

    /// Tints the thumbnail border to reinforce the rating — green for good,
    /// red for bad, subtle white when unrated.
    private var borderColor: Color {
        switch clip.rating {
        case .good: return .green.opacity(0.7)
        case .bad:  return .red.opacity(0.7)
        case nil:   return .white.opacity(0.15)
        }
    }

    private var thumbnailImage: Image {
        if let uiImage = clip.thumbnail {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "video.fill")
    }
}
