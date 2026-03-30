import SwiftUI

/// Scrollable grid of clip thumbnails for post-session review.
///
/// Two initialisers are available:
/// - `init(session:)` — live active session; grid stays reactive.
/// - `init(clips:title:)` — static array for history playback.
struct ClipGridView: View {

    private let clips: [Clip]
    private let title: String
    /// When non-nil, the grid is backed by a live session and stays reactive.
    private let liveSession: DrivingSession?

    @State private var selectedClip: Clip?
    @Environment(\.dismiss) private var dismiss

    // Live session init (active session review)
    init(session: DrivingSession) {
        self.liveSession = session
        self.clips = []          // unused — body reads from liveSession
        self.title = "Clips"
    }

    // Static init (history viewer)
    init(clips: [Clip], title: String = "Clips") {
        self.liveSession = nil
        self.clips = clips
        self.title = title
    }

    private var displayedClips: [Clip] {
        liveSession?.clips ?? clips
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
            ClipPlayerView(clip: clip)
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

    private func deleteClip(_ clip: Clip) {
        // Remove the MP4 file from disk
        try? FileManager.default.removeItem(at: clip.url)
        // Remove from live session if applicable
        liveSession?.removeClip(clip)
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

            Text(String(format: "%.1fs", clip.duration))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }

    private var thumbnailImage: Image {
        if let uiImage = clip.thumbnail {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "video.fill")
    }
}
