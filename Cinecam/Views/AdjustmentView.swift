import SwiftUI
import AVKit

struct AdjustmentView: View {
    @ObservedObject var viewModel: CameraViewModel
    
    var body: some View {
        VStack {
            if let player = viewModel.player {
                CineVideoPlayer(player: player)
                    .frame(height: 250)
                    .cornerRadius(CineTheme.buttonCornerRadius)
                    .padding()
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    AdjustmentSlider(title: "Exposure", value: $viewModel.adjustmentSettings.exposure, range: -2.0...2.0)
                        .onChange(of: viewModel.adjustmentSettings.exposure) { viewModel.updatePlayerPreview() }
                    
                    AdjustmentSlider(title: "Contrast", value: $viewModel.adjustmentSettings.contrast, range: 0.5...1.5)
                        .onChange(of: viewModel.adjustmentSettings.contrast) { viewModel.updatePlayerPreview() }
                    
                    AdjustmentSlider(title: "Highlights", value: $viewModel.adjustmentSettings.highlights, range: -1.0...1.0)
                        .onChange(of: viewModel.adjustmentSettings.highlights) { viewModel.updatePlayerPreview() }
                        
                    AdjustmentSlider(title: "Shadows", value: $viewModel.adjustmentSettings.shadows, range: -1.0...1.0)
                        .onChange(of: viewModel.adjustmentSettings.shadows) { viewModel.updatePlayerPreview() }
                }
                .padding()
            }
            
            HStack {
                Button(action: { viewModel.navigateToPresets() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false)
                
                Button(action: { viewModel.navigateToShare() }) {
                    Text("Render & Share")
                }
                .cineButtonStyle(isPrimary: true)
            }
            .padding()
        }
    }
}

struct AdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(CineTheme.fontHeadline)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(CineTheme.fontBody)
                    .foregroundColor(CineTheme.orange)
            }
            
            Slider(value: $value, in: range)
                .accentColor(CineTheme.orange)
        }
    }
}
