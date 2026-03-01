import SwiftUI
import AVFoundation
import UIKit

struct VideoEditorPreviewPanel: View {
    let player: AVPlayer
    let sourceURL: URL

    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var aspectTask: Task<Void, Never>?

    private var clampedAspectRatio: CGFloat {
        min(max(videoAspectRatio, 0.4), 2.4)
    }

    private var maximumPreviewHeight: CGFloat {
        clampedAspectRatio > 1.0 ? 250 : 370
    }

    var body: some View {
        VStack(spacing: 6) {
            CineVideoPlayer(player: player, showsPlaybackControls: false)
                .aspectRatio(clampedAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: maximumPreviewHeight)
                .background(Color.black.opacity(0.55))
                .cornerRadius(CineTheme.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: CineTheme.buttonCornerRadius, style: .continuous)
                        .stroke(CineTheme.orange.opacity(0.35), lineWidth: 1)
                )

            VideoSceneScrubberView(player: player, sourceURL: sourceURL)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .onAppear {
            resolveVideoAspectRatio(for: sourceURL)
            player.pause()
        }
        .onChange(of: sourceURL) { _, newURL in
            resolveVideoAspectRatio(for: newURL)
            player.pause()
        }
        .onDisappear {
            aspectTask?.cancel()
            aspectTask = nil
            player.pause()
        }
    }

    private func resolveVideoAspectRatio(for url: URL) {
        aspectTask?.cancel()
        aspectTask = Task {
            let ratio = await loadedAspectRatio(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                videoAspectRatio = ratio
            }
        }
    }

    private func loadedAspectRatio(for url: URL) async -> CGFloat {
        let asset = AVURLAsset(url: url)

        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return 16.0 / 9.0
            }

            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = natural.applying(transform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)

            guard width > 0, height > 0 else {
                return 16.0 / 9.0
            }

            return width / height
        } catch {
            return 16.0 / 9.0
        }
    }
}

struct VideoSceneScrubberView: View {
    let player: AVPlayer
    let sourceURL: URL

    @State private var thumbnails: [UIImage] = []
    @State private var durationSeconds: Double = 0.0
    @State private var selectedTime: Double = 0.0
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scene")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(CineTheme.orange.opacity(0.95))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 30)
                            .clipped()
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(index == highlightedThumbnailIndex ? CineTheme.orange : Color.white.opacity(0.18), lineWidth: index == highlightedThumbnailIndex ? 1.8 : 1)
                            )
                            .cornerRadius(7)
                            .onTapGesture {
                                guard durationSeconds > 0 else { return }
                                let destination = (Double(index) / Double(max(thumbnails.count - 1, 1))) * durationSeconds
                                selectedTime = destination
                                seekPlayer(to: destination)
                            }
                    }
                }
            }
            .frame(height: 32)

            Slider(
                value: Binding(
                    get: { selectedTime },
                    set: { newValue in
                        selectedTime = newValue
                        seekPlayer(to: newValue)
                    }
                ),
                in: 0...max(durationSeconds, 0.001),
                onEditingChanged: { editing in
                    if editing {
                        player.pause()
                    }
                }
            )
            .tint(CineTheme.orange)
            .scaleEffect(x: 1.0, y: 0.70, anchor: .center)
            .frame(height: 14)

            HStack {
                Text(formatTime(selectedTime))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))

                Spacer()

                Text(formatTime(durationSeconds))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(6)
        .background(CineTheme.darkGray.opacity(0.78))
        .cornerRadius(12)
        .onAppear {
            loadTimelineIfNeeded()
        }
        .onChange(of: sourceURL) { _, _ in
            loadTimelineIfNeeded(forceReload: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var highlightedThumbnailIndex: Int {
        guard !thumbnails.isEmpty, durationSeconds > 0 else { return -1 }
        let ratio = selectedTime / durationSeconds
        let index = Int((ratio * Double(thumbnails.count - 1)).rounded())
        return min(max(index, 0), thumbnails.count - 1)
    }

    private func loadTimelineIfNeeded(forceReload: Bool = false) {
        if !forceReload, durationSeconds > 0, !thumbnails.isEmpty {
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            let asset = AVURLAsset(url: sourceURL)
            guard let duration = try? await asset.load(.duration) else { return }
            let seconds = max(CMTimeGetSeconds(duration), 0)
            guard seconds > 0 else { return }

            let generated = await generateThumbnails(for: asset, durationSeconds: seconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                durationSeconds = seconds
                if selectedTime > seconds {
                    selectedTime = seconds
                }
                thumbnails = generated
            }
        }
    }

    private func generateThumbnails(for asset: AVAsset, durationSeconds: Double) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 180)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let count = 10
        var images: [UIImage] = []

        for index in 0..<count {
            let progress = Double(index) / Double(max(count - 1, 1))
            let targetSeconds = durationSeconds * progress
            let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)

            guard let image = await generateImage(generator: generator, at: targetTime) else {
                continue
            }

            images.append(image)
        }

        return images
    }

    private func generateImage(generator: AVAssetImageGenerator, at time: CMTime) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                guard error == nil, let image else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: UIImage(cgImage: image))
            }
        }
    }

    private func seekPlayer(to seconds: Double) {
        guard durationSeconds > 0 else { return }
        let safeSeconds = min(max(seconds, 0), durationSeconds)
        let targetTime = CMTime(seconds: safeSeconds, preferredTimescale: 600)
        player.pause()
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

struct AdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(CineTheme.orange)
            }

            Slider(value: $value, in: range)
                .tint(CineTheme.orange)
                .scaleEffect(x: 1.0, y: 0.78, anchor: .center)
                .frame(height: 18)
        }
    }
}

struct EditorStepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(CineTheme.orange)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
}
