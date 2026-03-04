import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            CineTheme.darkBackground.edgesIgnoringSafeArea(.all)
            
            switch viewModel.currentScreen {
            case .camera:
                CameraScreen(viewModel: viewModel)
            case .presetStudio:
                PresetStudioView(viewModel: viewModel)
            case .basicAdjustments:
                BasicAdjustmentsView(viewModel: viewModel)
            case .colorBalance:
                ColorBalanceView(viewModel: viewModel)
            case .hueCast:
                HueCastView(viewModel: viewModel)
            case .textureEffects:
                TextureEffectsView(viewModel: viewModel)
            case .finalEffects:
                FinalEffectsView(viewModel: viewModel)
            case .renderedPreview:
                RenderedVideoPreviewView(viewModel: viewModel)
            }

            if viewModel.isImportingVideo {
                ImportLoadingOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isImportingVideo)
        .statusBar(hidden: true)
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
    }
}

// Placeholder Views for compilation until fully implemented
    // ... (Placeholder Views comment) ...
struct CameraScreen: View {
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var cameraManager: CameraManager
    
    @State private var showSettings = false
    @State private var showVideoImportPicker = false
    @State private var rotationAngle: Angle = .zero
    
    private var previewAspectRatio: CGFloat {
        switch cameraManager.selectedOutputAspectRatio {
        case .native16x9:
            return 9.0 / 16.0
        case .cinema21x9:
            return 9.0 / 21.0
        }
    }
    
    init(viewModel: CameraViewModel) {
        self.viewModel = viewModel
        self.cameraManager = viewModel.cameraManager
    }
    
    var body: some View {
        ZStack {
            CineTheme.darkBackground.edgesIgnoringSafeArea(.all)
            
            // Camera Preview (Bordered)
            VStack {
                Spacer()
                CameraPreviewView(cameraManager: viewModel.cameraManager)
                    // The app UI stays portrait; use portrait coordinates so landscape device hold
                    // still appears as a normal 16:9 preview to the user.
                    .aspectRatio(previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(CineTheme.darkBackground)
                    .overlay {
                        FocusFeedbackOverlay(feedback: cameraManager.focusFeedback)
                    }
                    .overlay(alignment: .top) {
                        if let statusMessage = cameraManager.statusMessage {
                            Text(statusMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(CineTheme.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.72))
                                .clipShape(Capsule())
                                .padding(.top, 24)
                                .padding(.horizontal, 16)
                        }
                    }
                    .clipped()
                Spacer()
            }
            .edgesIgnoringSafeArea(.all)
            
            // Top bar pinned to safe-area top, outside of preview content.
            VStack {
                HStack {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                            .rotationEffect(rotationAngle)
                            .animation(.default, value: rotationAngle)
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView(cameraManager: cameraManager)
                    }

                    Spacer()

                    Button(action: { viewModel.navigateToPresetStudio() }) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                            .rotationEffect(rotationAngle)
                            .animation(.default, value: rotationAngle)
                    }
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.5 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .offset(y: -22)

                Spacer()
            }

            // Bottom Controls
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    HStack {
                        LensPickerButton(currentLens: cameraManager.currentLens, rotationAngle: rotationAngle) { lens in
                            cameraManager.switchLens(to: lens)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        RecordButton(isRecording: cameraManager.isRecording, rotationAngle: rotationAngle) {
                            if cameraManager.isRecording {
                                cameraManager.stopRecording()
                            } else {
                                cameraManager.startRecording()
                            }
                        }
                        .disabled(!cameraManager.is4KFormatActive && !cameraManager.isRecording)
                        .opacity((!cameraManager.is4KFormatActive && !cameraManager.isRecording) ? 0.5 : 1.0)

                        Group {
                            if cameraManager.isRecording {
                                RecordingTimeBadge(
                                    timeText: viewModel.recordingTimeFormatted,
                                    rotationAngle: rotationAngle
                                )
                            } else {
                                ImportVideoButton(rotationAngle: rotationAngle) {
                                    showVideoImportPicker = true
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 72)
            }
        }
        .sheet(isPresented: $showVideoImportPicker) {
            VideoImportPicker(
                onStartLoading: {
                    viewModel.isImportingVideo = true
                },
                onPick: { importedURL in
                    defer { viewModel.isImportingVideo = false }
                    guard let importedURL else { return }
                    viewModel.importVideo(from: importedURL)
                }
            )
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let orientation = UIDevice.current.orientation
            switch orientation {
            case .landscapeLeft:
                rotationAngle = .degrees(90)
            case .landscapeRight:
                rotationAngle = .degrees(-90)
            case .portrait, .portraitUpsideDown:
                rotationAngle = .degrees(0)
            default:
                rotationAngle = .degrees(0)
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            withAnimation {
                switch orientation {
                case .landscapeLeft:
                    rotationAngle = .degrees(90)
                case .landscapeRight:
                    rotationAngle = .degrees(-90)
                case .portrait, .portraitUpsideDown:
                    rotationAngle = .degrees(0)
                default:
                    // Keep previous rotation for faceUp/faceDown
                    break
                }
            }
        }
    }
}

struct LensPickerButton: View {
    let currentLens: AVCaptureDevice.DeviceType
    let rotationAngle: Angle
    let action: (AVCaptureDevice.DeviceType) -> Void

    private var currentTitle: String {
        switch currentLens {
        case .builtInUltraWideCamera:
            return "0.5x"
        case .builtInTelephotoCamera:
            return "Tele"
        default:
            return "1x"
        }
    }
    
    var body: some View {
        Menu {
            Button("0.5x") { action(.builtInUltraWideCamera) }
            Button("1x") { action(.builtInWideAngleCamera) }
            Button("Tele") { action(.builtInTelephotoCamera) }
        } label: {
            HStack(spacing: 4) {
                Text(currentTitle)
                    .font(CineTheme.fontHeadline)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white, lineWidth: 1)
            )
        }
        .rotationEffect(rotationAngle)
        .animation(.default, value: rotationAngle)
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let rotationAngle: Angle
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                RoundedRectangle(cornerRadius: isRecording ? 10 : 35)
                    .fill(CineTheme.orange)
                    .frame(width: isRecording ? 35 : 60, height: isRecording ? 35 : 60)
                    .animation(.easeInOut, value: isRecording)
            }
        }
        .rotationEffect(rotationAngle) // Rotate the button itself (useful if icon inside)
        .animation(.default, value: rotationAngle)
    }
}

struct RecordingTimeBadge: View {
    let timeText: String
    let rotationAngle: Angle

    var body: some View {
        Text(timeText)
            .font(CineTheme.fontHeadline)
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1)
            )
            .rotationEffect(rotationAngle)
            .animation(.default, value: rotationAngle)
    }
}

struct ImportVideoButton: View {
    let rotationAngle: Angle
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "film.stack")
                .foregroundColor(.white)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 1)
                )
        }
        .rotationEffect(rotationAngle)
        .animation(.default, value: rotationAngle)
    }
}

struct FocusFeedbackOverlay: View {
    let feedback: FocusFeedback?
    
    var body: some View {
        GeometryReader { geometry in
            if let feedback {
                FocusFeedbackMarker(isLocked: feedback.isLocked)
                    .position(
                        x: feedback.previewPoint.x * geometry.size.width,
                        y: feedback.previewPoint.y * geometry.size.height
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: feedback?.id)
    }
}

struct FocusFeedbackMarker: View {
    let isLocked: Bool
    
    private var accentColor: Color {
        isLocked ? Color.yellow : Color.white
    }
    
    private var title: String {
        isLocked ? "AF/AE LOCK" : "FOCUS"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(accentColor, lineWidth: 2)
                    .frame(width: 74, height: 74)
                
                Circle()
                    .stroke(accentColor.opacity(0.55), lineWidth: 1)
                    .frame(width: 44, height: 44)
                
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
            }
            
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72))
                .clipShape(Capsule())
        }
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 2)
    }
}

struct VideoImportPicker: UIViewControllerRepresentable {
    let onStartLoading: () -> Void
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStartLoading: onStartLoading, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onStartLoading: () -> Void
        private let onPick: (URL?) -> Void

        init(onStartLoading: @escaping () -> Void, onPick: @escaping (URL?) -> Void) {
            self.onStartLoading = onStartLoading
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else {
                onPick(nil)
                return
            }

            let movieType = UTType.movie.identifier
            guard provider.hasItemConformingToTypeIdentifier(movieType) else {
                onPick(nil)
                return
            }

            // Signal loading before the async file transfer starts
            onStartLoading()

            provider.loadFileRepresentation(forTypeIdentifier: movieType) { [onPick] pickedURL, _ in
                guard let pickedURL else {
                    DispatchQueue.main.async { onPick(nil) }
                    return
                }

                let fileExtension = pickedURL.pathExtension.isEmpty ? "mov" : pickedURL.pathExtension
                let copiedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)

                do {
                    try FileManager.default.copyItem(at: pickedURL, to: copiedURL)
                    DispatchQueue.main.async { onPick(copiedURL) }
                } catch {
                    DispatchQueue.main.async { onPick(nil) }
                }
            }
        }
    }
}

private struct ImportLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(CineTheme.orange)
                    .scaleEffect(1.4)

                Text("Importing video...")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(CineTheme.darkGray.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CineTheme.orange.opacity(0.45), lineWidth: 1)
            )
        }
        .allowsHitTesting(true)
    }
}
