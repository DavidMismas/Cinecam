import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum AppScreen {
    case camera
    case presetSelection
    case adjustments
    case share
}

class CameraViewModel: ObservableObject {
    @Published var currentScreen: AppScreen = .camera
    
    // Services
    @ObservedObject var cameraManager = CameraManager()
    let videoProcessor = VideoProcessor()
    
    // State
    @Published var selectedPreset: MoviePreset? = nil
    @Published var adjustmentSettings = AdjustmentSettings()
    @Published var recordedVideoURL: URL?
    @Published var processedVideoURL: URL?
    
    // Player State
    @Published var player: AVPlayer?
    @Published var recordingTimeFormatted: String = "00:00"
    @Published var renderProgress: Double = 0.0
    @Published private(set) var isRenderingFinalVideo = false
    
    private var cancellables = Set<AnyCancellable>()
    private var activeRenderToken = UUID()
    private let fileManager = FileManager.default
    private let managedVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    
    init() {
        purgeTemporaryVideoFiles()
        
        // Listen for new recordings
        cameraManager.$recordedVideoURL
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                guard let self = self, let url = url else { return }
                self.loadSourceVideo(url)
            }
            .store(in: &cancellables)
            
        // Listen for recording duration
        cameraManager.$recordingDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                self?.recordingTimeFormatted = self?.formatDuration(duration) ?? "00:00"
            }
            .store(in: &cancellables)
        
        cameraManager.$isRecording
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIdleTimerState()
            }
            .store(in: &cancellables)
        
        cameraManager.$selectedOutputAspectRatio
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePlayerPreview()
            }
            .store(in: &cancellables)
        
        $isRenderingFinalVideo
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIdleTimerState()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Navigation
    
    func navigateToPresets() {
        currentScreen = .presetSelection
        player?.pause() // Pause for smooth editing
        updatePlayerPreview()
    }
    
    func navigateToAdjustments() {
        currentScreen = .adjustments
        player?.pause() // Pause for smooth editing
        updatePlayerPreview()
    }
    
    func navigateToShare() {
        removeManagedVideoFileIfNeeded(processedVideoURL)
        processedVideoURL = nil
        renderProgress = 0.0
        activeRenderToken = UUID()
        currentScreen = .share
        player?.pause()
        // Render final video here or just preview? 
        // For share, we probably want to render it.
        renderFinalVideo()
    }
    
    func navigateBackToCamera() {
        pausePlaybackAndClearNowPlaying()
        cleanupWorkingVideoFiles(keepProcessedOutput: false)
        purgeTemporaryVideoFiles()
        currentScreen = .camera
        cameraManager.startSession() 
        // Reset state
        selectedPreset = nil
        adjustmentSettings = AdjustmentSettings()
        recordedVideoURL = nil
        processedVideoURL = nil
        renderProgress = 0.0
        isRenderingFinalVideo = false
        activeRenderToken = UUID()
        player = nil
    }
    
    // MARK: - Video Handling
    
    func importVideo(from url: URL) {
        cleanupWorkingVideoFiles(keepProcessedOutput: false, preserving: [url])
        selectedPreset = nil
        adjustmentSettings = AdjustmentSettings()
        renderProgress = 0.0
        isRenderingFinalVideo = false
        activeRenderToken = UUID()
        loadSourceVideo(url)
    }
    
    private func loadSourceVideo(_ url: URL) {
        cleanupWorkingVideoFiles(keepProcessedOutput: false, preserving: [url])
        processedVideoURL = nil
        renderProgress = 0.0
        isRenderingFinalVideo = false
        recordedVideoURL = url
        setupPlayer(with: url)
        updatePlayerPreview()
        currentScreen = .presetSelection
    }
    
    func setupPlayer(with url: URL) {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: item)
        configureInlinePlayback(self.player)
        
        // Loop video
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidReachEnd(notification:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: item)
        
        self.player?.play()
    }
    
    func updatePlayerPreview() {
        guard let url = recordedVideoURL, let player = player else { return }
        
        let asset = AVURLAsset(url: url)
        
        Task {
            // Create composition with current settings
            if let composition = try? await videoProcessor.createComposition(for: asset, 
                                                                             preset: selectedPreset, 
                                                                             adjustments: adjustmentSettings,
                                                                             outputAspectRatio: cameraManager.selectedOutputAspectRatio) {
                await MainActor.run {
                    player.currentItem?.videoComposition = composition
                }
            }
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: .zero, completionHandler: nil)
        }
    }
    
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            updateIdleTimerState()
            break
        case .inactive, .background:
            UIApplication.shared.isIdleTimerDisabled = false
            pausePlaybackAndClearNowPlaying()
        @unknown default:
            UIApplication.shared.isIdleTimerDisabled = false
            pausePlaybackAndClearNowPlaying()
        }
    }
    
    func configureInlinePlayback(_ player: AVPlayer?) {
        guard let player else { return }
        player.actionAtItemEnd = .none
        player.allowsExternalPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
    }
    
    func pausePlaybackAndClearNowPlaying() {
        player?.pause()
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    
    // MARK: - Rendering
    
    func renderFinalVideo() {
        guard let url = recordedVideoURL else {
            isRenderingFinalVideo = false
            return
        }
        let preset = selectedPreset
        let adjustments = adjustmentSettings
        let asset = AVURLAsset(url: url)
        let renderToken = activeRenderToken
        
        removeManagedVideoFileIfNeeded(processedVideoURL)
        processedVideoURL = nil
        renderProgress = 0.0
        isRenderingFinalVideo = true
        videoProcessor.exportVideo(asset: asset, 
                                   preset: preset, 
                                   adjustments: adjustments,
                                   outputAspectRatio: cameraManager.selectedOutputAspectRatio,
                                   targetBitrateMbps: cameraManager.renderBitrateMbps,
                                   progress: { [weak self] progress in
                                       guard let self = self, self.activeRenderToken == renderToken else { return }
                                       self.renderProgress = min(max(progress, 0.0), 1.0)
                                   }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.activeRenderToken == renderToken else { return }
                switch result {
                case .success(let finalUrl):
                    self.renderProgress = 1.0
                    self.isRenderingFinalVideo = false
                    self.processedVideoURL = finalUrl
                    // Pre-load the shared video into a player if needed, or just keep the preview player
                case .failure(let error):
                    print("Export failed: \(error)")
                    self.renderProgress = 0.0
                    self.isRenderingFinalVideo = false
                    self.processedVideoURL = nil
                }
            }
        }
    }
    
    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = cameraManager.isRecording || isRenderingFinalVideo
    }
    
    func cleanupAfterAutoSave() {
        cleanupWorkingVideoFiles(keepProcessedOutput: true)
        if let processedVideoURL {
            purgeTemporaryVideoFiles(keeping: [processedVideoURL])
        } else {
            purgeTemporaryVideoFiles()
        }
    }
    
    func cleanupAfterShareCompletion() {
        cleanupWorkingVideoFiles(keepProcessedOutput: false)
        purgeTemporaryVideoFiles()
    }
    
    private func cleanupWorkingVideoFiles(keepProcessedOutput: Bool, preserving urlsToKeep: [URL] = []) {
        let keepSet = Set(urlsToKeep.map(\.standardizedFileURL))
        
        if let recordedVideoURL, !keepSet.contains(recordedVideoURL.standardizedFileURL) {
            removeManagedVideoFileIfNeeded(recordedVideoURL)
            self.recordedVideoURL = nil
        }
        
        if let managerRecordedURL = cameraManager.recordedVideoURL,
           !keepSet.contains(managerRecordedURL.standardizedFileURL) {
            removeManagedVideoFileIfNeeded(managerRecordedURL)
            cameraManager.recordedVideoURL = nil
        }
        
        if !keepProcessedOutput,
           let processedVideoURL,
           !keepSet.contains(processedVideoURL.standardizedFileURL) {
            removeManagedVideoFileIfNeeded(processedVideoURL)
            self.processedVideoURL = nil
        }
    }
    
    func purgeTemporaryVideoFiles(keeping keepURLs: [URL] = []) {
        let keepSet = Set(keepURLs.map(\.standardizedFileURL))
        let tempDirectory = fileManager.temporaryDirectory
        
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for url in fileURLs where isManagedTemporaryVideoURL(url) {
            let normalizedURL = url.standardizedFileURL
            if keepSet.contains(normalizedURL) { continue }
            try? fileManager.removeItem(at: normalizedURL)
        }
    }
    
    private func removeManagedVideoFileIfNeeded(_ url: URL?) {
        guard let url else { return }
        let normalizedURL = url.standardizedFileURL
        guard isManagedTemporaryVideoURL(normalizedURL) else { return }
        try? fileManager.removeItem(at: normalizedURL)
    }
    
    private func isManagedTemporaryVideoURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard managedVideoExtensions.contains(url.pathExtension.lowercased()) else { return false }
        
        let normalizedURL = url.standardizedFileURL
        let tempPath = fileManager.temporaryDirectory.standardizedFileURL.path
        let filePath = normalizedURL.path
        return filePath == tempPath || filePath.hasPrefix(tempPath + "/")
    }
}
