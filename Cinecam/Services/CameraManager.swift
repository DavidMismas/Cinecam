import AVFoundation
import SwiftUI
import Combine
import VideoToolbox

enum OutputAspectRatioOption: String, CaseIterable, Identifiable {
    case native16x9
    case cinema21x9
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .native16x9:
            return "16:9"
        case .cinema21x9:
            return "21:9"
        }
    }
    
    func targetAspectRatio(for sourceSize: CGSize) -> CGFloat? {
        switch self {
        case .native16x9:
            return nil
        case .cinema21x9:
            let landscapeRatio: CGFloat = 21.0 / 9.0
            let isLandscape = abs(sourceSize.width) >= abs(sourceSize.height)
            return isLandscape ? landscapeRatio : (1.0 / landscapeRatio)
        }
    }
}

struct FocusFeedback: Identifiable {
    let id = UUID()
    let previewPoint: CGPoint
    let isLocked: Bool
}

class CameraManager: NSObject, ObservableObject {
    private enum SettingsKey {
        static let selectedFrameRate = "camera.selectedFrameRate"
        static let selectedOutputAspectRatio = "camera.selectedOutputAspectRatio"
        static let recordingBitrateMbps = "camera.recordingBitrateMbps"
        static let renderBitrateMbps = "camera.renderBitrateMbps"
        static let useSoftwareStabilization = "camera.useSoftwareStabilization"
        static let lockWhiteBalanceDuringRecording = "camera.lockWhiteBalanceDuringRecording"
    }
    
    static let bitrateRangeMbps: ClosedRange<Double> = 20...500
    static let defaultRecordingBitrateMbps: Double = 220
    static let defaultRenderBitrateMbps: Double = 260
    
    private let required4KResolution = CMVideoDimensions(width: 3840, height: 2160)

    @Published var session = AVCaptureSession()
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    @Published var isAuthorized = false
    @Published var focusFeedback: FocusFeedback?
    @Published var statusMessage: String?
    @Published private(set) var is4KFormatActive = false
    
    // Configuration Properties
    @Published var selectedFrameRate: Int = 30 {
        didSet {
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(selectedFrameRate, forKey: SettingsKey.selectedFrameRate)
            sessionQueue.async { [weak self] in
                self?.configureFormat()
                self?.configureOutput()
            }
        }
    }
    @Published var selectedOutputAspectRatio: OutputAspectRatioOption = .native16x9 {
        didSet {
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(selectedOutputAspectRatio.rawValue, forKey: SettingsKey.selectedOutputAspectRatio)
        }
    }
    @Published var recordingDuration: TimeInterval = 0
    private var recordingTimer: Timer?
    @Published var recordingBitrateMbps: Double = CameraManager.defaultRecordingBitrateMbps {
        didSet {
            let clamped = Self.clampBitrate(recordingBitrateMbps)
            if abs(clamped - recordingBitrateMbps) > 0.0001 {
                recordingBitrateMbps = clamped
                return
            }
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(recordingBitrateMbps, forKey: SettingsKey.recordingBitrateMbps)
            sessionQueue.async { [weak self] in
                self?.configureOutput()
            }
        }
    }
    @Published var renderBitrateMbps: Double = CameraManager.defaultRenderBitrateMbps {
        didSet {
            let clamped = Self.clampBitrate(renderBitrateMbps)
            if abs(clamped - renderBitrateMbps) > 0.0001 {
                renderBitrateMbps = clamped
                return
            }
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(renderBitrateMbps, forKey: SettingsKey.renderBitrateMbps)
        }
    }
    @Published var useSoftwareStabilization: Bool = true {
        didSet {
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(useSoftwareStabilization, forKey: SettingsKey.useSoftwareStabilization)
            sessionQueue.async { [weak self] in
                self?.configureOutput()
            }
        }
    }
    @Published var lockWhiteBalanceDuringRecording: Bool = false {
        didSet {
            guard !isRestoringPersistedSettings else { return }
            UserDefaults.standard.set(lockWhiteBalanceDuringRecording, forKey: SettingsKey.lockWhiteBalanceDuringRecording)
            sessionQueue.async { [weak self] in
                self?.applyWhiteBalanceStateForCurrentCaptureContext()
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
    private var pendingFocusLockWorkItem: DispatchWorkItem?
    private let focusFeedbackDisplayDuration: TimeInterval = 1.8
    private let focusLockDelay: TimeInterval = 0.2
    private var statusMessageDismissWorkItem: DispatchWorkItem?
    private var isRestoringPersistedSettings = false
    
    override init() {
        super.init()
        restorePersistedSettings()
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
            
            self.configureFormat() // Apply 4K 60fps logic first (codec availability depends on format)
            self.configureOutput()
            self.applyWhiteBalanceStateForCurrentCaptureContext()
            
            self.session.commitConfiguration()
            self.session.startRunning()
            self.configureOutput() // Re-apply once running; some codec availability is only final after start.
        }
    }
    
    func switchLens(to lens: AVCaptureDevice.DeviceType) {
        sessionQueue.async {
            self.session.beginConfiguration()
            if let currentInput = self.videoInput {
                self.session.removeInput(currentInput)
            }
            self.setupInput(for: lens)
            self.configureFormat() // Re-apply format constraints to new device first
            self.configureOutput() // Then apply output settings against the resolved format
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
                applyWhiteBalanceStateForCurrentCaptureContext()
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
            
            let supported4KFormats = device.formats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dimensions.width == required4KResolution.width,
                      dimensions.height == required4KResolution.height else {
                    return false
                }
                return format.videoSupportedFrameRateRanges.contains { range in
                    range.minFrameRate <= targetFrameRate && targetFrameRate <= range.maxFrameRate
                }
            }
            
            guard !supported4KFormats.isEmpty else {
                set4KCaptureAvailability(
                    false,
                    message: "4K \(selectedFrameRate) FPS is unavailable for this lens. Switch lens or FPS."
                )
                return
            }

            let bestFormat = supported4KFormats.sorted { lhs, rhs in
                let leftMaxFPS = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                let rightMaxFPS = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return leftMaxFPS > rightMaxFPS
            }.first

            guard let bestFormat else {
                set4KCaptureAvailability(
                    false,
                    message: "4K format selection failed at \(selectedFrameRate) FPS."
                )
                return
            }

            device.activeFormat = bestFormat

            let duration = CMTime(value: 1, timescale: CMTimeScale(selectedFrameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            set4KCaptureAvailability(true, message: nil)
            
        } catch {
            set4KCaptureAvailability(false, message: "4K setup error: \(error.localizedDescription)")
            print("Error configuring format: \(error)")
        }
    }
    
    private func configureOutput() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        applyStabilizationMode(for: connection)
        
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

        configureHEVCOutput(for: connection)
    }
    
    private func applyStabilizationMode(for connection: AVCaptureConnection) {
        guard connection.isVideoStabilizationSupported else { return }
        
        connection.preferredVideoStabilizationMode = useSoftwareStabilization ? .cinematic : .off
    }
    
    private func configureHEVCOutput(for connection: AVCaptureConnection) {
        guard videoOutput.availableVideoCodecTypes.contains(.hevc) else {
            presentStatusMessage("HEVC unavailable for current lens/FPS/format.")
            return
        }
        
        let supportedKeys = Set(videoOutput.supportedOutputSettingsKeys(for: connection))
        var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc]
        
        if supportedKeys.contains(AVVideoCompressionPropertiesKey) {
            settings[AVVideoCompressionPropertiesKey] = makeCompressionProperties()
        }
        
        videoOutput.setOutputSettings(settings, for: connection)
    }
    
    private func makeCompressionProperties() -> [String: Any] {
        let bitrateBps = Int(Self.clampBitrate(recordingBitrateMbps) * 1_000_000)
        var compression: [String: Any] = [
            kVTCompressionPropertyKey_AverageBitRate as String: bitrateBps,
            AVVideoExpectedSourceFrameRateKey: selectedFrameRate
        ]
        
        compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        
        return compression
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
            self.cancelPendingFocusLock()
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

                let lockWorkItem = DispatchWorkItem { [weak self] in
                    self?.lockFocusAndExposure()
                }
                self.pendingFocusLockWorkItem = lockWorkItem
                self.sessionQueue.asyncAfter(deadline: .now() + self.focusLockDelay, execute: lockWorkItem)
            } catch {
                print("Error updating focus: \(error)")
            }
        }
    }
    
    private func lockFocusAndExposure() {
        pendingFocusLockWorkItem = nil
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
    
    private func cancelPendingFocusLock() {
        pendingFocusLockWorkItem?.cancel()
        pendingFocusLockWorkItem = nil
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

    private func restorePersistedSettings() {
        isRestoringPersistedSettings = true
        defer { isRestoringPersistedSettings = false }
        
        let defaults = UserDefaults.standard
        let persistedFrameRate = defaults.object(forKey: SettingsKey.selectedFrameRate) as? Int ?? 30
        selectedFrameRate = [30, 60].contains(persistedFrameRate) ? persistedFrameRate : 30
        if let rawAspectRatio = defaults.string(forKey: SettingsKey.selectedOutputAspectRatio),
           let aspectRatio = OutputAspectRatioOption(rawValue: rawAspectRatio) {
            selectedOutputAspectRatio = aspectRatio
        }
        
        let persistedRecordingBitrate = defaults.object(forKey: SettingsKey.recordingBitrateMbps) as? Double ?? Self.defaultRecordingBitrateMbps
        recordingBitrateMbps = Self.clampBitrate(persistedRecordingBitrate)
        
        let persistedRenderBitrate = defaults.object(forKey: SettingsKey.renderBitrateMbps) as? Double ?? Self.defaultRenderBitrateMbps
        renderBitrateMbps = Self.clampBitrate(persistedRenderBitrate)
        useSoftwareStabilization = defaults.object(forKey: SettingsKey.useSoftwareStabilization) as? Bool ?? true
        
        lockWhiteBalanceDuringRecording = defaults.bool(forKey: SettingsKey.lockWhiteBalanceDuringRecording)
    }

    private func applyWhiteBalanceStateForCurrentCaptureContext() {
        let shouldLock = isRecording && lockWhiteBalanceDuringRecording
        setWhiteBalanceLocked(shouldLock)
    }

    private func setWhiteBalanceLocked(_ isLocked: Bool) {
        guard let device = videoInput?.device ?? activeDevice else { return }
        
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            if isLocked {
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            }
        } catch {
            print("Error applying white balance mode: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        guard is4KFormatActive else {
            presentStatusMessage("Recording blocked: 4K format is not active for this lens/FPS.")
            return
        }
        
        // Rotation is handled by RotationCoordinator dynamically.
        setWhiteBalanceLocked(lockWhiteBalanceDuringRecording)
        
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
        setWhiteBalanceLocked(false)
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }
    }
    
    private func set4KCaptureAvailability(_ isActive: Bool, message: String?) {
        DispatchQueue.main.async {
            self.is4KFormatActive = isActive
            if let message {
                self.presentStatusMessage(message)
            }
        }
    }
    
    private func presentStatusMessage(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessageDismissWorkItem?.cancel()
            self.statusMessageDismissWorkItem = nil
            self.statusMessage = message
            
            let dismissWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.statusMessage == message {
                    self.statusMessage = nil
                }
            }
            self.statusMessageDismissWorkItem = dismissWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: dismissWorkItem)
        }
    }
    
    private static func clampBitrate(_ value: Double) -> Double {
        min(max(value, bitrateRangeMbps.lowerBound), bitrateRangeMbps.upperBound)
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            presentStatusMessage("Recording failed: \(error.localizedDescription)")
            print("Error recording: \(error)")
            return
        }
        
        DispatchQueue.main.async {
            self.recordedVideoURL = outputFileURL
        }
    }
}
