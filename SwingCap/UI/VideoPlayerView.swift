import AVFoundation
import SwiftUI

/// `UIViewRepresentable` wrapping `AVPlayerLayer` for video playback.
/// Uses `override class var layerClass` so the layer automatically
/// fills and resizes with the view — no manual `addSublayer` needed.
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

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func attach(_ player: AVPlayer) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
