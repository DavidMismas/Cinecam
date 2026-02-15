import SwiftUI
import AVKit
import Photos
import UIKit

struct ShareView: View {
    @ObservedObject var viewModel: CameraViewModel
    @State private var isSharing = false
    @State private var sharePlayer: AVPlayer?
    @State private var playerURL: URL?
    @State private var videoAspectRatio: CGFloat = 9.0 / 16.0
    @State private var aspectRatioTask: Task<Void, Never>?
    @State private var isSavingToPhotos = false
    @State private var statusMessage: String?
    
    var body: some View {
        GeometryReader { geometry in
            let previewMaxHeight = min(max(geometry.size.height * 0.50, 260), 500)
            
            VStack(spacing: 16) {
                Text("Your Cinematic Masterpiece")
                    .font(CineTheme.fontTitle)
                    .foregroundColor(CineTheme.orange)
                    .padding()
                
                if let player = sharePlayer {
                    CineVideoPlayer(player: player)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: previewMaxHeight)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(CineTheme.buttonCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: CineTheme.buttonCornerRadius, style: .continuous)
                                .stroke(CineTheme.orange.opacity(0.35), lineWidth: 1)
                        )
                        .clipped()
                        .padding(.horizontal, 16)
                } else {
                    CinemaRenderAnimationView(renderProgress: viewModel.renderProgress)
                        .frame(maxWidth: .infinity)
                        .frame(height: min(previewMaxHeight, 250))
                        .padding(.horizontal, 16)
                }
                
                Spacer(minLength: 6)
                
                HStack {
                    Button(action: saveVideoToGallery) {
                        Text(isSavingToPhotos ? "Saving..." : "Save")
                    }
                    .cineButtonStyle(isPrimary: true)
                    .disabled(viewModel.processedVideoURL == nil || isSavingToPhotos)
                    .opacity((viewModel.processedVideoURL == nil || isSavingToPhotos) ? 0.5 : 1.0)
                    
                    Button(action: openGallery) {
                        Text("Open Gallery")
                    }
                    .cineButtonStyle(isPrimary: false)
                }
                .padding(.horizontal)
                
                HStack {
                    Button(action: { viewModel.navigateBackToCamera() }) {
                        Text("New Recording")
                    }
                    .cineButtonStyle(isPrimary: false)
                    
                    Button(action: { isSharing = true }) {
                        Text("Share Video")
                    }
                    .cineButtonStyle(isPrimary: true)
                    .disabled(viewModel.processedVideoURL == nil)
                    .opacity(viewModel.processedVideoURL == nil ? 0.5 : 1.0)
                    .sheet(isPresented: $isSharing) {
                        if let url = viewModel.processedVideoURL {
                            ShareSheet(activityItems: [url])
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if let statusMessage {
                StatusPopupView(message: statusMessage)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: statusMessage != nil)
        .onAppear {
            prepareSharePlayer(with: viewModel.processedVideoURL)
        }
        .onChange(of: viewModel.processedVideoURL) { _, newURL in
            prepareSharePlayer(with: newURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: sharePlayer?.currentItem)) { _ in
            sharePlayer?.seek(to: .zero)
            sharePlayer?.play()
        }
        .onDisappear {
            sharePlayer?.pause()
            sharePlayer = nil
            playerURL = nil
            aspectRatioTask?.cancel()
            aspectRatioTask = nil
        }
    }
    
    private func prepareSharePlayer(with url: URL?) {
        guard let url else {
            sharePlayer?.pause()
            sharePlayer = nil
            playerURL = nil
            videoAspectRatio = 9.0 / 16.0
            aspectRatioTask?.cancel()
            aspectRatioTask = nil
            return
        }
        
        if playerURL == url, let sharePlayer {
            sharePlayer.play()
            return
        }
        
        updateAspectRatio(for: url)
        let player = AVPlayer(url: url)
        viewModel.configureInlinePlayback(player)
        player.actionAtItemEnd = .none
        sharePlayer = player
        playerURL = url
        player.play()
    }

    private func updateAspectRatio(for url: URL) {
        aspectRatioTask?.cancel()
        aspectRatioTask = Task {
            let ratio = await resolvedVideoAspectRatio(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard playerURL == url else { return }
                videoAspectRatio = ratio
            }
        }
    }

    private func resolvedVideoAspectRatio(for url: URL) async -> CGFloat {
        let asset = AVURLAsset(url: url)
        
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return 9.0 / 16.0
            }
            
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)
            
            guard width > 0.0, height > 0.0 else {
                return 9.0 / 16.0
            }
            
            return width / height
        } catch {
            return 9.0 / 16.0
        }
    }
    
    private func saveVideoToGallery() {
        guard let url = viewModel.processedVideoURL else {
            showStatus("Video is still rendering")
            return
        }
        
        isSavingToPhotos = true
        
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                handlePhotoPermission(status: status, videoURL: url)
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                handlePhotoPermission(status: status, videoURL: url)
            }
        }
    }
    
    private func handlePhotoPermission(status: PHAuthorizationStatus, videoURL: URL) {
        let granted = status == .authorized || status == .limited
        
        guard granted else {
            DispatchQueue.main.async {
                isSavingToPhotos = false
                showStatus("Photos access denied")
            }
            return
        }
        
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                isSavingToPhotos = false
                showStatus(success ? "Saved to gallery" : "Save failed")
            }
        }
    }
    
    private func openGallery() {
        let application = UIApplication.shared
        let candidates = ["photos-redirect://", "photos://"].compactMap(URL.init(string:))
        
        func openNext(at index: Int) {
            guard index < candidates.count else {
                showStatus("Could not open gallery")
                return
            }
            
            application.open(candidates[index], options: [:]) { opened in
                if !opened {
                    openNext(at: index + 1)
                }
            }
        }
        
        openNext(at: 0)
    }
    
    private func showStatus(_ message: String) {
        DispatchQueue.main.async {
            statusMessage = message
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if statusMessage == message {
                    statusMessage = nil
                }
            }
        }
    }
}

private struct StatusPopupView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(CineTheme.orange)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CineTheme.darkGray.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CineTheme.orange.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 20)
    }
}

struct CinemaRenderAnimationView: View {
    let renderProgress: Double
    @State private var animateScanner = false
    @State private var animateReels = false
    @State private var pulse = false
    
    var body: some View {
        let clampedProgress = min(max(renderProgress, 0.0), 1.0)
        let percent = Int((clampedProgress * 100.0).rounded())
        
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.08),
                                Color(white: 0.14),
                                Color(white: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 0) {
                    FilmPerforationStrip()
                        .padding(.top, 10)
                    Spacer()
                    FilmPerforationStrip()
                        .padding(.bottom, 10)
                }
                
                HStack(spacing: 28) {
                    filmReel
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 64, height: 4)
                        .cornerRadius(2)
                    filmReel
                }
                
                Image(systemName: "clapperboard.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(CineTheme.orange)
                    .offset(y: -56)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                CineTheme.orange.opacity(0.20),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 96, height: 150)
                    .blur(radius: 1.0)
                    .offset(x: animateScanner ? 136 : -136)
                    .animation(.linear(duration: 1.55).repeatForever(autoreverses: false), value: animateScanner)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CineTheme.orange.opacity(0.5), lineWidth: 1)
            )
            
            VStack(spacing: 8) {
                ProgressView(value: clampedProgress, total: 1.0)
                    .tint(CineTheme.orange)
                    .frame(maxWidth: 260)
                
                Text("\(percent)%")
                    .font(CineTheme.fontHeadline)
                    .foregroundColor(.white)
                
                Text("Keep the app open. Do not lock your phone while rendering.")
                    .font(.footnote)
                    .foregroundColor(CineTheme.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Text("Developing your final cut")
                .font(CineTheme.fontBody)
                .foregroundColor(CineTheme.textSecondary)
        }
        .onAppear {
            animateScanner = true
            animateReels = true
            pulse = true
        }
    }
    
    private var filmReel: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.20))
                .frame(width: 72, height: 72)
            
            Circle()
                .stroke(CineTheme.orange.opacity(0.85), lineWidth: 3)
                .frame(width: 70, height: 70)
            
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 10, height: 10)
                    .offset(y: -22)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            
            Circle()
                .fill(CineTheme.orange.opacity(0.9))
                .frame(width: 12, height: 12)
        }
        .rotationEffect(.degrees(animateReels ? 360 : 0))
        .animation(.linear(duration: 1.9).repeatForever(autoreverses: false), value: animateReels)
    }
}

private struct FilmPerforationStrip: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<15, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.black.opacity(0.75))
                    .frame(width: 10, height: 5)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
