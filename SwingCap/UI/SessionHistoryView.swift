import SwiftUI

/// Browses all past driving-range sessions stored by `SessionStore`.
/// Presented as a sheet from `SessionView` via the history clock button.
struct SessionHistoryView: View {

    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSession: PersistedSession?
    @State private var sessionToDelete: PersistedSession?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if store.pastSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
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
        .sheet(item: $selectedSession) { session in
            ClipGridView(
                clips: session.orderedClips.map { $0.toClip() },
                title: sessionTitle(session)
            )
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let s = sessionToDelete { store.delete(s) }
            }
        } message: {
            Text("This will permanently remove the session and all its clips.")
        }
    }

    // MARK: - Subviews

    private var sessionList: some View {
        List {
            ForEach(store.pastSessions) { session in
                SessionRow(session: session)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedSession = session }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    .listRowSeparatorTint(.white.opacity(0.1))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            Text("No past sessions")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Sessions are saved automatically as you hit balls.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Helpers

    private func sessionTitle(_ session: PersistedSession) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startedAt)
    }
}

// MARK: - Session row

private struct SessionRow: View {

    let session: PersistedSession

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail from first clip
            if let first = session.orderedClips.first,
               let data = first.thumbnailData,
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 44)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 64, height: 44)
                    .overlay {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(relativeDate(session.startedAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(session.clipCount) clip\(session.clipCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 4)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        // For older sessions fall back to absolute date
        if abs(date.timeIntervalSinceNow) > 7 * 24 * 3600 {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return relative.prefix(1).uppercased() + relative.dropFirst()
    }
}
