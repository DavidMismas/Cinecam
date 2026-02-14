import SwiftUI
import AVKit

struct PresetSelectionView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let player = viewModel.player {
                CineVideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 470)
                    .cornerRadius(CineTheme.buttonCornerRadius)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            
            Spacer(minLength: 12)
            
            VStack(spacing: 14) {
                Text("Choose Your Look")
                    .font(CineTheme.fontHeadline)
                    .foregroundColor(CineTheme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                GeometryReader { geometry in
                    let spacing: CGFloat = 12
                    let visibleCards: CGFloat = 3
                    let cardSide = max(84, (geometry.size.width - (spacing * (visibleCards - 1))) / visibleCards)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(MoviePreset.allCases) { preset in
                                PresetCard(
                                    preset: preset,
                                    isSelected: viewModel.selectedPreset == preset
                                ) {
                                    viewModel.selectedPreset = preset
                                    viewModel.updatePlayerPreview()
                                }
                                .frame(width: cardSide, height: cardSide)
                            }
                        }
                    }
                }
                .frame(height: 114)
            
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
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
    }
}

private extension MoviePreset {
    var symbolName: String {
        switch self {
        case .matrix:
            return "cpu.fill"
        case .bladeRunner2049:
            return "sun.max.fill"
        case .sinCity:
            return "drop.fill"
        case .theBatman:
            return "moon.stars.fill"
        case .strangerThings:
            return "sparkles.tv.fill"
        case .dune:
            return "sun.haze.fill"
        case .drive:
            return "car.fill"
        case .madMax:
            return "flame.fill"
        case .revenant:
            return "leaf.fill"
        case .inTheMoodForLove:
            return "heart.fill"
        case .seven:
            return "7.circle.fill"
        case .vertigo:
            return "hurricane"
        case .orderOfPhoenix:
            return "wand.and.stars"
        case .hero:
            return "shield.lefthalf.filled"
        case .laLaLand:
            return "music.note"
        }
    }
}

struct PresetCard: View {
    let preset: MoviePreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(CineTheme.orange)
                
                Text(preset.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(CineTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CineTheme.darkBackground)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? CineTheme.orange : CineTheme.orange.opacity(0.40),
                        lineWidth: isSelected ? 2.2 : 1
                    )
            )
        }
    }
}
