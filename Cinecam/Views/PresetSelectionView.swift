import SwiftUI
import AVKit

struct PresetSelectionView: View {
    @ObservedObject var viewModel: CameraViewModel
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 10)
    ]
    
    var body: some View {
        VStack {
            // Preview Area
            if let player = viewModel.player {
                CineVideoPlayer(player: player)
                    .frame(height: 300)
                    .cornerRadius(CineTheme.buttonCornerRadius)
                    .padding()
            }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(MoviePreset.allCases) { preset in
                        PresetButton(preset: preset, isSelected: viewModel.selectedPreset == preset) {
                            viewModel.selectedPreset = preset
                            viewModel.updatePlayerPreview()
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                Button(action: { viewModel.navigateBackToCamera() }) {
                    Text("Back to Camera")
                }
                .cineButtonStyle(isPrimary: false)
                
                Button(action: {
                    if viewModel.selectedPreset != nil {
                        viewModel.navigateToAdjustments()
                    }
                }) {
                    Text("Next: Adjustments")
                }
                .cineButtonStyle(isPrimary: true)
                .disabled(viewModel.selectedPreset == nil)
                .opacity(viewModel.selectedPreset == nil ? 0.5 : 1.0)
            }
            .padding()
        }
    }
}

struct PresetButton: View {
    let preset: MoviePreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                // Placeholder for thumbnail. In real app, generate from video frame.
                Rectangle()
                    .fill(Color.gray)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Text(preset.title.prefix(1))
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    )
                
                Text(preset.title)
                    .font(CineTheme.fontBody)
                    .foregroundColor(isSelected ? CineTheme.orange : .white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CineTheme.orange : Color.clear, lineWidth: 2)
            )
        }
    }
}
