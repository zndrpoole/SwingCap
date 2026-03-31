import SwiftUI
import AVFoundation

/// Wraps `AVCaptureVideoPreviewLayer` in a SwiftUI view.
/// This is the only place we drop down to UIKit in the camera layer.
///
/// `AVCaptureVideoPreviewLayer` is a `CALayer` subclass and must be hosted in
/// a `UIView` — there is no native SwiftUI equivalent. We use
/// `UIViewRepresentable` with a minimal `_PreviewUIView` to attach the layer
/// and keep it sized to the view's bounds via `layoutSubviews`.
///
/// The `hasLayer` guard in `updateUIView` prevents re-attaching the layer
/// on subsequent SwiftUI update passes (which would add duplicate sublayers).
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

    /// Called on every SwiftUI update cycle. Only attaches the preview layer
    /// if it hasn't been attached yet — guards against double-attachment.
    func updateUIView(_ uiView: _PreviewUIView, context: Context) {
        if let layer = session.previewLayer, !uiView.hasLayer {
            uiView.attach(layer)
        }
    }
}

// MARK: - Internal UIView

final class _PreviewUIView: UIView {

    private(set) var hasLayer = false

    /// Adds the capture preview layer as a sublayer and tracks that it's attached.
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.frame = bounds
        self.layer.addSublayer(layer)
        hasLayer = true
    }

    /// Keeps the preview layer filling the entire view as the view is resized
    /// (e.g. rotation, split-screen).
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?
            .compactMap { $0 as? AVCaptureVideoPreviewLayer }
            .forEach { $0.frame = bounds }
    }
}
