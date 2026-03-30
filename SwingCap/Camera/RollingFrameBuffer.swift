import AVFoundation

/// A fixed-capacity ring buffer of `CMSampleBuffer` objects.
///
/// Frames are appended by the capture pipeline at 60 fps. When the buffer
/// is full the oldest frame is silently evicted.  Call `drain()` to get a
/// chronologically-ordered snapshot of all retained frames.
///
/// Thread-safe: all mutations and reads are serialised via `NSLock`.
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

    /// Appends a copy of `sampleBuffer`, evicting the oldest frame if full.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let copy = copySampleBuffer(sampleBuffer) else { return }
        lock.withLock {
            ring[head] = copy
            head = (head + 1) % capacity
            if count < capacity { count += 1 }
        }
    }

    /// Returns a snapshot of retained frames in chronological order (oldest first).
    /// Does **not** clear the buffer.
    func snapshot() -> [CMSampleBuffer] {
        lock.withLock {
            guard count > 0 else { return [] }
            var result: [CMSampleBuffer] = []
            result.reserveCapacity(count)
            // If buffer hasn't wrapped yet, oldest frame is at index 0;
            // otherwise it's at `head` (the next write position).
            let start = count < capacity ? 0 : head
            for i in 0 ..< count {
                let idx = (start + i) % capacity
                if let buf = ring[idx] { result.append(buf) }
            }
            return result
        }
    }

    /// Clears all retained frames.
    func clear() {
        lock.withLock {
            ring = Array(repeating: nil, count: capacity)
            head = 0
            count = 0
        }
    }

    var frameCount: Int { lock.withLock { count } }

    // MARK: - Private

    private func copySampleBuffer(_ src: CMSampleBuffer) -> CMSampleBuffer? {
        var dst: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault,
                                              sampleBuffer: src,
                                              sampleBufferOut: &dst)
        return status == noErr ? dst : nil
    }
}
