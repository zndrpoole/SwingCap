import AVFoundation

/// A fixed-capacity ring buffer of `CMSampleBuffer` objects.
///
/// **Purpose**: Keeps a sliding window of the most recent ~2 seconds of
/// camera frames in memory at all times. When a strike is detected, the
/// buffer is snapshotted and cleared — the snapshot becomes the pre-strike
/// portion of the saved clip.
///
/// **Ring buffer mechanics**: The buffer is backed by a fixed-size array
/// (`ring`). `head` always points to the next write slot. On each `append`:
/// - Write the new frame at `ring[head]`.
/// - Advance `head` modulo `capacity` — when `head` wraps to 0 the oldest
///   frame is silently overwritten (evicted).
/// - Increment `count` until it equals `capacity`.
///
/// `snapshot()` reconstructs the chronological order:
/// - If the buffer has never filled, frames start at index 0.
/// - After wrap-around, the oldest frame sits at `head` (the next write
///   position) because that slot was the last one overwritten.
///
/// **Memory management**: AVFoundation reuses `CMSampleBuffer` memory after
/// the delegate callback returns. Each `append` calls `CMSampleBufferCreateCopy`
/// so the frames stay valid for the full 2-second window. Evicted frames are
/// released when their slot is overwritten with a new copy.
///
/// **Thread safety**: All mutations and reads are serialised via `NSLock`
/// so the buffer can be appended from the camera frames queue while being
/// snapshotted from the same or any other queue.
final class RollingFrameBuffer {

    // MARK: - Configuration

    /// Number of frames to retain.
    /// Default 120 ≈ 2 seconds at 60 fps.
    static let defaultCapacity = 120

    let capacity: Int

    // MARK: - Storage

    private var ring: [CMSampleBuffer?]
    /// Index of the *next write* slot (i.e. one past the most-recently written).
    private var head = 0
    private var count = 0
    private let lock = NSLock()

    // MARK: - Init

    init(capacity: Int = RollingFrameBuffer.defaultCapacity) {
        self.capacity = capacity
        self.ring = Array(repeating: nil, count: capacity)
    }

    // MARK: - API

    /// Appends a copy of `sampleBuffer`, evicting the oldest frame if the
    /// buffer is at capacity. Copying ensures the frame data outlives the
    /// AVFoundation delegate callback that provided it.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let copy = copySampleBuffer(sampleBuffer) else { return }
        lock.withLock {
            ring[head] = copy
            head = (head + 1) % capacity   // advance and wrap around
            if count < capacity { count += 1 }
        }
    }

    /// Returns a snapshot of retained frames in chronological order (oldest first).
    ///
    /// After wrap-around the oldest frame is at `head`, so we start there
    /// and step forward by `count` positions to reconstruct the sequence.
    /// Does **not** clear the buffer — call `clear()` explicitly after the
    /// snapshot is handed off to `FrameProcessor`.
    func snapshot() -> [CMSampleBuffer] {
        lock.withLock {
            guard count > 0 else { return [] }
            var result: [CMSampleBuffer] = []
            result.reserveCapacity(count)
            // If the buffer has never filled, the oldest frame is at index 0.
            // After the first wrap, the oldest frame is at `head` (the slot
            // that will be overwritten next, which holds the evicted entry).
            let start = count < capacity ? 0 : head
            for i in 0 ..< count {
                let idx = (start + i) % capacity
                if let buf = ring[idx] { result.append(buf) }
            }
            return result
        }
    }

    /// Clears all retained frames.
    /// Called by `FrameProcessor` immediately after taking a snapshot on
    /// strike detection so fresh post-strike frames land in an empty buffer.
    func clear() {
        lock.withLock {
            ring = Array(repeating: nil, count: capacity)
            head = 0
            count = 0
        }
    }

    var frameCount: Int { lock.withLock { count } }

    // MARK: - Private

    /// Creates a deep copy of `src` using the system allocator.
    /// Returns `nil` and logs nothing on failure — the caller silently skips
    /// the frame, which is preferable to crashing.
    private func copySampleBuffer(_ src: CMSampleBuffer) -> CMSampleBuffer? {
        var dst: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault,
                                              sampleBuffer: src,
                                              sampleBufferOut: &dst)
        return status == noErr ? dst : nil
    }
}
