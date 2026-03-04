import SwiftUI
import CoreImage

struct PresetStudioView: View {
    @ObservedObject var viewModel: CameraViewModel

    @State private var draftSettings: AdjustmentSettings
    @State private var presetName: String = ""
    @State private var selectedPresetID: UUID?
    @State private var statusMessage: String?

    @State private var referenceSourceImage: CIImage?
    @State private var referencePreviewImage: UIImage?
    @State private var isReferenceLoading = false
    @State private var previewRequestID = 0

    init(viewModel: CameraViewModel) {
        self.viewModel = viewModel
        _draftSettings = State(initialValue: viewModel.adjustmentSettings)
    }

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Preset Studio",
                subtitle: "Reference still + full grading sliders"
            )

            referenceImagePanel
                .padding(.horizontal, 16)

            presetHeaderSection
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 14) {
                    baseSection
                    colorSection
                    castSection
                    textureSection
                    finalFXSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }

            HStack(spacing: 10) {
                Button(action: { viewModel.closePresetStudio() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: resetDraft) {
                    Text("Reset")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: saveOrUpdatePreset) {
                    Text(primaryActionTitle)
                }
                .cineButtonStyle(isPrimary: true, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(CineTheme.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.top, 12)
            }
        }
        .onAppear {
            if selectedPresetID == nil, presetName.isEmpty, let firstPreset = viewModel.presets.first {
                selectPreset(firstPreset, showToast: false)
            }
            loadReferenceImageIfNeeded()
        }
        .onChange(of: draftSettings) { _, _ in
            renderReferencePreview()
        }
        .onChange(of: viewModel.presets) { _, _ in
            syncSelectedPresetAfterChanges()
        }
    }

    private var selectedPreset: AdjustmentPreset? {
        guard let selectedPresetID else { return nil }
        return viewModel.presets.first { $0.id == selectedPresetID }
    }

    private var shouldUpdateSelectedPreset: Bool {
        guard let selectedPreset else { return false }
        let currentName = normalizedPresetName(presetName)
        return !currentName.isEmpty && currentName.caseInsensitiveCompare(selectedPreset.name) == .orderedSame
    }

    private var primaryActionTitle: String {
        shouldUpdateSelectedPreset ? "Update Selected" : "Save New"
    }

    private var referenceImagePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CineTheme.darkGray.opacity(0.52))

            if let image = referencePreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .cornerRadius(11)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))

                    Text("Reference image image.DNG not loaded")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            if isReferenceLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(CineTheme.orange)
                    Text("Updating preview")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(10)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(height: 205)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CineTheme.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var presetHeaderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preset")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(CineTheme.orange)

            TextField("Preset name", text: $presetName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CineTheme.darkGray)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CineTheme.orange.opacity(0.35), lineWidth: 1)
                )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: startNewPreset) {
                        Text("New")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedPresetID == nil ? CineTheme.darkBackground : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedPresetID == nil ? CineTheme.orange : CineTheme.darkGray)
                            .clipShape(Capsule())
                    }

                    ForEach(viewModel.presets) { preset in
                        let isSelected = preset.id == selectedPresetID
                        Button(action: { selectPreset(preset) }) {
                            Text(preset.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? CineTheme.darkBackground : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSelected ? CineTheme.orange : CineTheme.darkGray)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(CineTheme.orange.opacity(isSelected ? 0.0 : 0.45), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if let selectedPreset {
                    Text("Selected: \(selectedPreset.name)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    Button(action: { deletePreset(selectedPreset) }) {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(CineTheme.orange)
                    }
                } else {
                    Text("Choose a preset to update, or enter a new name to save as new")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(CineTheme.darkGray.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var baseSection: some View {
        PresetSection(title: "Base") {
            AdjustmentSlider(title: "Exposure", value: $draftSettings.exposure, range: -2.0...2.0)
            AdjustmentSlider(title: "Contrast", value: $draftSettings.contrast, range: 0.0...2.0)
            AdjustmentSlider(title: "Shadows", value: $draftSettings.shadows, range: -1.0...1.0)
            AdjustmentSlider(title: "Highlights", value: $draftSettings.highlights, range: -1.0...1.0)
        }
    }

    private var colorSection: some View {
        PresetSection(title: "Basic Colors") {
            AdjustmentSlider(
                title: "Red / Blue",
                value: $draftSettings.redBlueBalance,
                range: -1.0...1.0,
                tint: draftSettings.redBlueBalance >= 0 ? .blue : .red
            )
            AdjustmentSlider(
                title: "Green / Tint",
                value: $draftSettings.greenTint,
                range: -1.0...1.0,
                tint: draftSettings.greenTint >= 0 ? .pink : .green
            )
            AdjustmentSlider(
                title: "Saturation (+/-)",
                value: $draftSettings.saturationAdjustment,
                range: -1.0...1.0,
                tint: draftSettings.saturationAdjustment >= 0 ? .yellow : .gray
            )
            AdjustmentSlider(
                title: "Vibrance (+/-)",
                value: $draftSettings.vibrance,
                range: -1.0...1.0,
                tint: draftSettings.vibrance >= 0 ? .mint : .teal
            )
        }
    }

    private var castSection: some View {
        PresetSection(title: "Color Grading") {
            AdjustmentSlider(
                title: "Global Hue",
                value: $draftSettings.globalCastHue,
                range: 0.0...360.0,
                tint: hueColor(draftSettings.globalCastHue)
            )
            AdjustmentSlider(
                title: "Global Cast Strength",
                value: $draftSettings.globalColorCast,
                range: 0.0...1.0,
                tint: castAmountColor(hue: draftSettings.globalCastHue)
            )

            AdjustmentSlider(
                title: "Shadows Hue",
                value: $draftSettings.shadowsCastHue,
                range: 0.0...360.0,
                tint: hueColor(draftSettings.shadowsCastHue)
            )
            AdjustmentSlider(
                title: "Shadows Cast Strength",
                value: $draftSettings.shadowsColorCast,
                range: 0.0...1.0,
                tint: castAmountColor(hue: draftSettings.shadowsCastHue)
            )

            AdjustmentSlider(
                title: "Highlights Hue",
                value: $draftSettings.highlightsCastHue,
                range: 0.0...360.0,
                tint: hueColor(draftSettings.highlightsCastHue)
            )
            AdjustmentSlider(
                title: "Highlights Cast Strength",
                value: $draftSettings.highlightsColorCast,
                range: 0.0...1.0,
                tint: castAmountColor(hue: draftSettings.highlightsCastHue)
            )
        }
    }

    private var textureSection: some View {
        PresetSection(title: "Texture") {
            AdjustmentSlider(title: "Texture (+/-)", value: $draftSettings.texture, range: -1.0...1.0)
            AdjustmentSlider(title: "Clarity (+/-)", value: $draftSettings.clarity, range: -1.0...1.0)
            AdjustmentSlider(title: "Grain", value: $draftSettings.grain, range: 0.0...1.0)
            AdjustmentSlider(title: "Vignette", value: $draftSettings.vignette, range: 0.0...1.0)
        }
    }

    private var finalFXSection: some View {
        PresetSection(title: "Final FX") {
            AdjustmentSlider(title: "Bloom", value: $draftSettings.bloom, range: 0.0...1.0)
            AdjustmentSlider(title: "Soft Glow", value: $draftSettings.softGlow, range: 0.0...1.0)
            AdjustmentSlider(title: "Dust / Scratches", value: $draftSettings.vhsAmount, range: 0.0...1.0)
        }
    }

    private func normalizedPresetName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startNewPreset() {
        selectedPresetID = nil
        presetName = ""
        showStatus("New preset mode")
    }

    private func selectPreset(_ preset: AdjustmentPreset, showToast: Bool = true) {
        selectedPresetID = preset.id
        presetName = preset.name
        draftSettings = preset.settings
        if showToast {
            showStatus("Selected \(preset.name)")
        }
    }

    private func saveOrUpdatePreset() {
        if shouldUpdateSelectedPreset,
           let selectedPreset,
           let updatedPreset = viewModel.updatePreset(
            id: selectedPreset.id,
            name: presetName,
            settings: draftSettings
           ) {
            selectedPresetID = updatedPreset.id
            presetName = updatedPreset.name
            showStatus("Updated \(updatedPreset.name)")
            return
        }

        let newPreset = viewModel.savePreset(name: presetName, settings: draftSettings)
        selectedPresetID = newPreset.id
        presetName = newPreset.name
        showStatus("Saved \(newPreset.name)")
    }

    private func deletePreset(_ preset: AdjustmentPreset) {
        viewModel.deletePreset(id: preset.id)
        if selectedPresetID == preset.id {
            selectedPresetID = nil
            presetName = ""
        }
        showStatus("Deleted \(preset.name)")
    }

    private func resetDraft() {
        draftSettings = AdjustmentSettings()
        showStatus("Sliders reset")
    }

    private func syncSelectedPresetAfterChanges() {
        guard let selectedPresetID else { return }
        guard let selectedPreset = viewModel.presets.first(where: { $0.id == selectedPresetID }) else {
            self.selectedPresetID = nil
            return
        }

        let trimmed = normalizedPresetName(presetName)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare(selectedPreset.name) == .orderedSame {
            presetName = selectedPreset.name
        }
    }

    private func loadReferenceImageIfNeeded() {
        guard referenceSourceImage == nil else {
            renderReferencePreview()
            return
        }

        guard let resourceURL = Bundle.main.url(forResource: "image", withExtension: "DNG")
            ?? Bundle.main.url(forResource: "image", withExtension: "dng")
            ?? Bundle.main.url(forResource: "image", withExtension: "Dng") else {
            showStatus("image.DNG not found in app bundle")
            return
        }

        isReferenceLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let source = CIImage(contentsOf: resourceURL, options: [.applyOrientationProperty: true])
            let reduced = source.map { downscaledReferenceImage($0, maxDimension: 1500) }

            DispatchQueue.main.async {
                self.referenceSourceImage = reduced
                self.isReferenceLoading = false
                if reduced == nil {
                    self.showStatus("Failed to decode image.DNG")
                }
                self.renderReferencePreview()
            }
        }
    }

    private func renderReferencePreview() {
        guard let referenceSourceImage else { return }

        previewRequestID += 1
        let requestID = previewRequestID
        let settingsSnapshot = draftSettings

        isReferenceLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = viewModel.videoProcessor.renderPreviewImage(from: referenceSourceImage, adjustments: settingsSnapshot)

            DispatchQueue.main.async {
                guard requestID == self.previewRequestID else { return }
                self.referencePreviewImage = rendered
                self.isReferenceLoading = false
            }
        }
    }

    private func hueColor(_ hueDegrees: Double) -> Color {
        Color(hue: normalizedHue(hueDegrees), saturation: 0.9, brightness: 0.95)
    }

    private func castAmountColor(hue hueDegrees: Double) -> Color {
        Color(hue: normalizedHue(hueDegrees), saturation: 0.9, brightness: 0.95)
    }

    private func normalizedHue(_ hueDegrees: Double) -> Double {
        let wrapped = hueDegrees.truncatingRemainder(dividingBy: 360)
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        return positive / 360.0
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

private struct PresetSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(CineTheme.orange)

            VStack(spacing: 10) {
                content
            }
        }
        .padding(12)
        .background(CineTheme.darkGray.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func downscaledReferenceImage(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
    let extent = image.extent.integral
    let maxSourceDimension = max(extent.width, extent.height)
    guard maxSourceDimension > maxDimension, maxSourceDimension > 0 else {
        return image
    }

    let scale = maxDimension / maxSourceDimension
    return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
}
