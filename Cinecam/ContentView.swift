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
            case .presetSelection:
                PresetSelectionView(viewModel: viewModel)
            case .adjustments:
                AdjustmentView(viewModel: viewModel)
            case .share:
                ShareView(viewModel: viewModel)
            }
        }
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
    private let previewAspectRatio: CGFloat = 9.0 / 16.0
    
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
                    .overlay(alignment: .topTrailing) {
                        if viewModel.cameraManager.useProRes {
                            Text("ProRes")
                                .font(CineTheme.fontHeadline)
                                .foregroundColor(CineTheme.orange)
                                .rotationEffect(rotationAngle)
                                .animation(.default, value: rotationAngle)
                                .padding(.top, 28)
                                .padding(.trailing, 16)
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
            VideoImportPicker { importedURL in
                guard let importedURL else { return }
                viewModel.importVideo(from: importedURL)
            }
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
    let onPick: (URL?) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
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
        private let onPick: (URL?) -> Void
        
        init(onPick: @escaping (URL?) -> Void) {
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
            
            provider.loadFileRepresentation(forTypeIdentifier: movieType) { [onPick] pickedURL, _ in
                guard let pickedURL else {
                    DispatchQueue.main.async {
                        onPick(nil)
                    }
                    return
                }
                
                let fileExtension = pickedURL.pathExtension.isEmpty ? "mov" : pickedURL.pathExtension
                let copiedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)
                
                do {
                    try FileManager.default.copyItem(at: pickedURL, to: copiedURL)
                    DispatchQueue.main.async {
                        onPick(copiedURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        onPick(nil)
                    }
                }
            }
        }
    }
}
