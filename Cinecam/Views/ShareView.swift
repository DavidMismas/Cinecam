import SwiftUI
import AVKit

struct ShareView: View {
    @ObservedObject var viewModel: CameraViewModel
    @State private var isSharing = false
    @State private var sharePlayer: AVPlayer?
    
    var body: some View {
        VStack {
            Text("Your Cinematic Masterpiece")
                .font(CineTheme.fontTitle)
                .foregroundColor(CineTheme.orange)
                .padding()
            
            if let player = sharePlayer {
                CineVideoPlayer(player: player)
                    .cornerRadius(CineTheme.buttonCornerRadius)
                    .padding()
            } else {
                CinemaRenderAnimationView()
                    .padding()
            }
            
            Spacer()
            
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
            .padding()
        }
        .onAppear {
            prepareSharePlayer(with: viewModel.processedVideoURL)
        }
        .onChange(of: viewModel.processedVideoURL) { _, newURL in
            prepareSharePlayer(with: newURL)
        }
        .onDisappear {
            sharePlayer?.pause()
            sharePlayer = nil
        }
    }
    
    private func prepareSharePlayer(with url: URL?) {
        guard let url else {
            sharePlayer?.pause()
            sharePlayer = nil
            return
        }
        
        let player = AVPlayer(url: url)
        viewModel.configureInlinePlayback(player)
        sharePlayer = player
    }
}

struct CinemaRenderAnimationView: View {
    @State private var animateScanner = false
    @State private var animateReels = false
    @State private var pulse = false
    
    var body: some View {
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
            
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate * 3)
                let dotCount = ((step % 4) + 4) % 4
                let dots = String(repeating: ".", count: dotCount)
                
                Text("Rendering\(dots)")
                    .font(CineTheme.fontHeadline)
                    .foregroundColor(.white)
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
