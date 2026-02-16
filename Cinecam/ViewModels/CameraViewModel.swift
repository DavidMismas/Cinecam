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
    
    init() {
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
        selectedPreset = nil
        adjustmentSettings = AdjustmentSettings()
        renderProgress = 0.0
        isRenderingFinalVideo = false
        activeRenderToken = UUID()
        loadSourceVideo(url)
    }
    
    private func loadSourceVideo(_ url: URL) {
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
}
