import AVFoundation
import SwiftUI
import Combine

struct FocusFeedback: Identifiable {
    let id = UUID()
    let previewPoint: CGPoint
    let isLocked: Bool
}

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    @Published var isAuthorized = false
    @Published var focusFeedback: FocusFeedback?
    
    // Configuration Properties
    @Published var selectedFrameRate: Int = 30 {
        didSet {
            sessionQueue.async { [weak self] in
                self?.configureFormat()
            }
        }
    }
    @Published var recordingDuration: TimeInterval = 0
    private var recordingTimer: Timer?
    @Published var useProRes: Bool = false {
        didSet {
            sessionQueue.async { [weak self] in
                self?.configureOutput()
            }
        }
    }
    
    private var videoOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    @Published public private(set) var activeDevice: AVCaptureDevice? // Expose for UI updates
    private var sessionQueue = DispatchQueue(label: "com.cinecam.sessionQueue")
    
    private var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var focusFeedbackDismissWorkItem: DispatchWorkItem?
    private let focusFeedbackDisplayDuration: TimeInterval = 1.8
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted {
                        self.setupSession()
                    }
                }
            }
        default:
            self.isAuthorized = false
        }
    }
    
    private func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .inputPriority // Allow custom format configuration
            
            // Add Input
            self.setupInput(for: .builtInWideAngleCamera)
            
            // Add Audio Input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
            
            // Add Output
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            self.configureOutput()
            self.configureFormat() // Apply 4K 60fps logic
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    func switchLens(to lens: AVCaptureDevice.DeviceType) {
        sessionQueue.async {
            self.session.beginConfiguration()
            if let currentInput = self.videoInput {
                self.session.removeInput(currentInput)
            }
            self.setupInput(for: lens)
            self.configureOutput() // Update connection properties (mirroring, stabilization)
            self.configureFormat() // Re-apply format constraints to new device
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.currentLens = lens
            }
        }
    }
    
    private func setupInput(for lens: AVCaptureDevice.DeviceType) {
        // Fallback logic for devices that don't have specific lenses (e.g., non-Pro phones)
        let preferredDevice = AVCaptureDevice.default(lens, for: .video, position: .back)
        let fallbackDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        
        guard let device = preferredDevice ?? fallbackDevice else {
            print("No video device found.")
            return
        }
        
        DispatchQueue.main.async {
            self.activeDevice = device
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                self.videoInput = input
                
                // Setup Rotation Coordinator
                setupCaptureRotationCoordinator(for: device)
            }
        } catch {
            print("Error setting up input: \(error)")
        }
    }
    
    private func configureFormat() {
        guard let device = videoInput?.device ?? activeDevice else { return }
        let targetFrameRate = Float64(selectedFrameRate)
        
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            let supportedFormats = device.formats.filter { format in
                format.videoSupportedFrameRateRanges.contains { range in
                    range.minFrameRate <= targetFrameRate && targetFrameRate <= range.maxFrameRate
                }
            }
            
            guard !supportedFormats.isEmpty else {
                print("No camera format supports \(selectedFrameRate) FPS on current lens.")
                return
            }

            let bestFormat = supportedFormats.sorted { lhs, rhs in
                let leftDimensions = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
                let rightDimensions = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
                let leftIs4K = leftDimensions.width == 3840 && leftDimensions.height == 2160
                let rightIs4K = rightDimensions.width == 3840 && rightDimensions.height == 2160

                if leftIs4K != rightIs4K {
                    return leftIs4K
                }

                let leftPixels = Int(leftDimensions.width) * Int(leftDimensions.height)
                let rightPixels = Int(rightDimensions.width) * Int(rightDimensions.height)

                if leftPixels != rightPixels {
                    return leftPixels > rightPixels
                }

                let leftMaxFPS = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                let rightMaxFPS = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return leftMaxFPS > rightMaxFPS
            }.first

            guard let bestFormat else {
                print("Failed to select a format for \(selectedFrameRate) FPS")
                return
            }

            device.activeFormat = bestFormat

            let duration = CMTime(value: 1, timescale: CMTimeScale(selectedFrameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            
        } catch {
            print("Error configuring format: \(error)")
        }
    }
    
    private func configureOutput() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematic
        }
        
        // Mirroring Logic for Front Camera
        if let input = videoInput, input.device.position == .front {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        } else {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        
        // ProRes Configuration (if available)
        if useProRes {
             let proResCodecs: [AVVideoCodecType] = [.proRes422, .proRes422HQ, .proRes422LT, .proRes4444]
             if let availableCodec = videoOutput.availableVideoCodecTypes.first(where: { proResCodecs.contains($0) }) {
                 videoOutput.setOutputSettings([AVVideoCodecKey: availableCodec], for: connection)
             } else {
                 print("ProRes not supported on this device/configuration.")
                 // Fallback to HEVC
                 videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
             }
        } else {
            // HEVC
            if videoOutput.availableVideoCodecTypes.contains(.hevc) {
                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }
    }
    
    private func setupCaptureRotationCoordinator(for device: AVCaptureDevice) {
        captureRotationObservation?.invalidate()
        captureRotationObservation = nil

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        captureRotationCoordinator = coordinator

        applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)

        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coord, _ in
            let angle = coord.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async {
                self?.applyCaptureRotation(angle)
            }
        }
    }

    func startSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
    
    func showFocusFeedback(at previewPoint: CGPoint, isLocked: Bool) {
        let clampedPoint = CGPoint(
            x: min(max(previewPoint.x, 0), 1),
            y: min(max(previewPoint.y, 0), 1)
        )
        
        DispatchQueue.main.async {
            self.focusFeedbackDismissWorkItem?.cancel()
            self.focusFeedbackDismissWorkItem = nil
            
            let feedback = FocusFeedback(previewPoint: clampedPoint, isLocked: isLocked)
            self.focusFeedback = feedback
            
            let dismissWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.focusFeedback?.id == feedback.id else { return }
                self.focusFeedback = nil
            }
            self.focusFeedbackDismissWorkItem = dismissWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.focusFeedbackDisplayDuration,
                execute: dismissWorkItem
            )
        }
    }
    
    func focus(at point: CGPoint) {
        updateFocus(at: point, lockAfterFocus: false)
    }
    
    func focusAndLock(at point: CGPoint) {
        updateFocus(at: point, lockAfterFocus: true)
    }
    
    private func updateFocus(at point: CGPoint, lockAfterFocus: Bool) {
        sessionQueue.async {
            guard let device = self.videoInput?.device ?? self.activeDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                }
                
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                }
                
                if lockAfterFocus {
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    } else if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    } else if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    } else if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = !lockAfterFocus
                device.unlockForConfiguration()
                
                guard lockAfterFocus else { return }
                
                self.sessionQueue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.lockFocusAndExposure()
                }
            } catch {
                print("Error updating focus: \(error)")
            }
        }
    }
    
    private func lockFocusAndExposure() {
        guard let device = videoInput?.device ?? activeDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: device.lensPosition, completionHandler: nil)
            } else if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = false
            device.unlockForConfiguration()
        } catch {
            print("Error locking focus: \(error)")
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        
        // ADAPTIVE RECORDING:
        // User requested: "if phone is in portrait mode - record in portrait mode too."
        // The RotationCoordinator provides the correct angle for "HorizonLevelCapture".
        // We simply apply it directly.
        
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Rotation is now handled by RotationCoordinator dynamically
        
        let outputFileName = NSUUID().uuidString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        videoOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.recordingDuration += 1
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        videoOutput.stopRecording()
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording: \(error)")
            return
        }
        
        DispatchQueue.main.async {
            self.recordedVideoURL = outputFileURL
        }
    }
}
