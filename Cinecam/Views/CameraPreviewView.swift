import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = cameraManager.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onFocusSelection = { [weak cameraManager] capturePoint, previewPoint, shouldLockFocus in
            guard let cameraManager else { return }
            cameraManager.showFocusFeedback(at: previewPoint, isLocked: shouldLockFocus)
            if shouldLockFocus {
                cameraManager.focusAndLock(at: capturePoint)
            } else {
                cameraManager.focus(at: capturePoint)
            }
        }
        // The rotation coordinator will be set up when the view moves to window and has a device
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = cameraManager.session
        uiView.onFocusSelection = { [weak cameraManager] capturePoint, previewPoint, shouldLockFocus in
            guard let cameraManager else { return }
            cameraManager.showFocusFeedback(at: previewPoint, isLocked: shouldLockFocus)
            if shouldLockFocus {
                cameraManager.focusAndLock(at: capturePoint)
            } else {
                cameraManager.focus(at: capturePoint)
            }
        }
        // Pass the explicit active device to set up the rotation coordinator correctly
        if let device = cameraManager.activeDevice {
            uiView.updateActiveDevice(device)
        }
    }
}

class PreviewView: UIView {
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var activeDevice: AVCaptureDevice?
    var onFocusSelection: ((CGPoint, CGPoint, Bool) -> Void)?
    
    private lazy var tapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTapToFocus(_:))
    )
    
    private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPressToLockFocus(_:))
        )
        recognizer.minimumPressDuration = 0.5
        return recognizer
    }()
    
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }
    
    func updateActiveDevice(_ device: AVCaptureDevice?) {
        guard device != activeDevice else { return }
        activeDevice = device
        setupRotationIfReady()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setupRotationIfReady()
        } else {
            teardownRotation()
        }
    }
    
    private func setupRotationIfReady() {
        guard let device = activeDevice else { return }
        guard videoPreviewLayer.connection != nil else { return }
        
        if let coordinator = rotationCoordinator, coordinator.device == device {
            return
        }
        
        teardownRotation()
        
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
        rotationCoordinator = coordinator
        
        applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] coord, _ in
             DispatchQueue.main.async {
                 self?.applyRotation(coord.videoRotationAngleForHorizonLevelPreview)
             }
        }
    }
    
    private func applyRotation(_ angle: CGFloat) {
        if let connection = videoPreviewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
    
    private func teardownRotation() {
        previewRotationObservation?.invalidate()
        previewRotationObservation = nil
        rotationCoordinator = nil
    }
    
    private func setupGestures() {
        isUserInteractionEnabled = true
        tapGestureRecognizer.require(toFail: longPressGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(longPressGestureRecognizer)
    }
    
    private func capturePoint(from gesture: UIGestureRecognizer) -> CGPoint {
        let location = gesture.location(in: self)
        return videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
    }
    
    private func previewPoint(from gesture: UIGestureRecognizer) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        
        let location = gesture.location(in: self)
        return CGPoint(
            x: min(max(location.x / bounds.width, 0), 1),
            y: min(max(location.y / bounds.height, 0), 1)
        )
    }
    
    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onFocusSelection?(capturePoint(from: gesture), previewPoint(from: gesture), false)
    }
    
    @objc private func handleLongPressToLockFocus(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onFocusSelection?(capturePoint(from: gesture), previewPoint(from: gesture), true)
    }
}
