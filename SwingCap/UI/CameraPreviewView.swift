import SwiftUI
import AVFoundation

/// Wraps `AVCaptureVideoPreviewLayer` in a SwiftUI view.
/// This is the only place we drop down to UIKit in the camera layer.
struct CameraPreviewView: UIViewRepresentable {

    let session: CameraSession

    func makeUIView(context: Context) -> _PreviewUIView {
        let view = _PreviewUIView()
        view.backgroundColor = .black
        if let layer = session.previewLayer {
            view.attach(layer)
        }
        return view
    }

    func updateUIView(_ uiView: _PreviewUIView, context: Context) {
        if let layer = session.previewLayer, !uiView.hasLayer {
            uiView.attach(layer)
        }
    }
}

// MARK: - Internal UIView

final class _PreviewUIView: UIView {

    private(set) var hasLayer = false

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.frame = bounds
        self.layer.addSublayer(layer)
        hasLayer = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?
            .compactMap { $0 as? AVCaptureVideoPreviewLayer }
            .forEach { $0.frame = bounds }
    }
}
