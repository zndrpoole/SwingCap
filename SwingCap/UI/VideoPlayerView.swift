import AVFoundation
import SwiftUI

/// `UIViewRepresentable` wrapping `AVPlayerLayer` for video playback.
///
/// Uses `override class var layerClass` to make `AVPlayerLayer` the backing
/// layer of the `UIView` itself, rather than a sublayer. This means:
/// - The layer is created by UIKit before `makeUIView` is called.
/// - No manual `addSublayer` or `removeFromSuperlayer` is needed.
/// - `layoutSubviews` just needs to set `playerLayer.frame = bounds` to keep
///   the video filling the view.
///
/// This approach is more robust than adding an `AVPlayerLayer` as a sublayer
/// because it avoids the extra `CALayer` hierarchy level and auto-sizes cleanly.
struct VideoPlayerView: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> _PlayerUIView {
        let view = _PlayerUIView()
        view.backgroundColor = .black
        view.attach(player)
        return view
    }

    func updateUIView(_ uiView: _PlayerUIView, context: Context) {}
}

// MARK: - Internal UIView

final class _PlayerUIView: UIView {

    /// Declares `AVPlayerLayer` as the backing layer class so UIKit creates
    /// it automatically — no sublayer management required.
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// Convenience cast of the already-created backing layer.
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func attach(_ player: AVPlayer) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect   // letterbox to preserve aspect ratio
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
