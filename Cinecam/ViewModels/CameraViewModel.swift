import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum AppScreen {
    case camera
    case basicAdjustments
    case colorBalance
    case hueCast
    case textureEffects
    case finalEffects
    case renderedPreview
}

class CameraViewModel: ObservableObject {
    @Published var currentScreen: AppScreen = .camera

    // Services
    @ObservedObject var cameraManager = CameraManager()
    let videoProcessor = VideoProcessor()

    // State
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
        UIApplication.shared.isIdleTimerDisabled = true

        cameraManager.$recordedVideoURL
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                guard let self = self, let url = url else { return }
                self.loadSourceVideo(url)
            }
            .store(in: &cancellables)

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
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Navigation

    func navigateToBasicAdjustments() {
        currentScreen = .basicAdjustments
        updatePlayerPreview()
    }

    func navigateToColorBalance() {
        currentScreen = .colorBalance
        updatePlayerPreview()
    }

    func navigateToHueCast() {
        currentScreen = .hueCast
        updatePlayerPreview()
    }

    func navigateToTextureEffects() {
        currentScreen = .textureEffects
        updatePlayerPreview()
    }

    func navigateToFinalEffects() {
        currentScreen = .finalEffects
        updatePlayerPreview()
    }

    func navigateToRenderedPreview(with url: URL) {
        processedVideoURL = url
        pausePlaybackAndClearNowPlaying()
        setupPlayer(with: url)
        currentScreen = .renderedPreview
    }

    func navigateBackToCamera() {
        pausePlaybackAndClearNowPlaying()
        cleanupWorkingVideoFiles(keepProcessedOutput: false)
        purgeTemporaryVideoFiles()
        currentScreen = .camera
        cameraManager.startSession()
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
        currentScreen = .basicAdjustments
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        self.player?.pause()
        self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func updatePlayerPreview() {
        guard let url = recordedVideoURL, let player = player else { return }

        let asset = AVURLAsset(url: url)

        Task {
            if let composition = try? await videoProcessor.createComposition(
                for: asset,
                adjustments: adjustmentSettings,
                outputAspectRatio: cameraManager.selectedOutputAspectRatio
            ) {
                await MainActor.run {
                    player.currentItem?.videoComposition = composition
                }
            }
        }
    }

    @objc
    func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: .zero, completionHandler: nil)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            updateIdleTimerState()
        case .inactive, .background:
            UIApplication.shared.isIdleTimerDisabled = true
            pausePlaybackAndClearNowPlaying()
        @unknown default:
            UIApplication.shared.isIdleTimerDisabled = true
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

    func renderFinalVideo(completion: ((Result<URL, Error>) -> Void)? = nil) {
        guard let url = recordedVideoURL else {
            isRenderingFinalVideo = false
            return
        }

        let adjustments = adjustmentSettings
        let asset = AVURLAsset(url: url)
        let renderToken = activeRenderToken

        removeManagedVideoFileIfNeeded(processedVideoURL)
        processedVideoURL = nil
        renderProgress = 0.0
        isRenderingFinalVideo = true

        videoProcessor.exportVideo(
            asset: asset,
            adjustments: adjustments,
            outputAspectRatio: cameraManager.selectedOutputAspectRatio,
            targetBitrateMbps: cameraManager.renderBitrateMbps,
            progress: { [weak self] progress in
                guard let self = self, self.activeRenderToken == renderToken else { return }
                self.renderProgress = min(max(progress, 0.0), 1.0)
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.activeRenderToken == renderToken else { return }

                switch result {
                case .success(let finalURL):
                    self.renderProgress = 1.0
                    self.isRenderingFinalVideo = false
                    self.processedVideoURL = finalURL
                    completion?(.success(finalURL))
                case .failure(let error):
                    print("Export failed: \(error)")
                    self.renderProgress = 0.0
                    self.isRenderingFinalVideo = false
                    self.processedVideoURL = nil
                    completion?(.failure(error))
                }
            }
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = true
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
