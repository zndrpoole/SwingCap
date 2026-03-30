import SwiftUI

/// Scrollable grid of clip thumbnails for post-session review.
/// Receives the live `DrivingSession` reference so the grid
/// updates automatically if new clips arrive while the sheet is open.
struct ClipGridView: View {

    let session: DrivingSession
    @State private var selectedClip: Clip?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if session.clips.isEmpty {
                    emptyState
                } else {
                    clipGrid
                }
            }
            .navigationTitle("Clips")
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
                ForEach(session.clips) { clip in
                    ClipThumbnailCell(clip: clip)
                        .onTapGesture { selectedClip = clip }
                }
            }
            .padding(16)
        }
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
