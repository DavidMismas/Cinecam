import AVFoundation
import CoreImage
import SwiftUI
import Combine

class VideoProcessor: ObservableObject {
    
    // MARK: - Playback Composition
    
    /// Creates an AVVideoComposition to apply the preset and adjustments in real-time during playback.
    func createComposition(for asset: AVAsset, preset: MoviePreset?, adjustments: AdjustmentSettings?) async throws -> AVVideoComposition {
        let composition = try await AVVideoComposition.videoComposition(with: asset) { request in
            let sourceImage = request.sourceImage
            var outputImage = sourceImage
            
            // 1. Apply Preset
            if let preset = preset {
                outputImage = PresetService.apply(preset: preset, to: outputImage, at: request.compositionTime)
            }
            
            // 2. Apply Manual Adjustments
            if let adjustments = adjustments {
                outputImage = self.applyAdjustments(adjustments, to: outputImage)
            }
            
            request.finish(with: outputImage.cropped(to: sourceImage.extent), context: nil)
        }
        return composition
    }
    
    // MARK: - Export
    
    private static func makeExportSession(for asset: AVAsset, codec: VideoCodecPreference) -> AVAssetExportSession? {
        var presetsToTry: [String] = []
        
        switch codec {
        case .h265:
            presetsToTry = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        case .h264:
            presetsToTry = [AVAssetExportPresetHighestQuality]
        }
        
        for preset in presetsToTry {
            if let session = AVAssetExportSession(asset: asset, presetName: preset) {
                return session
            }
        }
        
        return AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
    }

    func exportVideo(asset: AVAsset, 
                     preset: MoviePreset?, 
                     adjustments: AdjustmentSettings?, 
                     codecPreference: VideoCodecPreference,
                     start: Double? = nil,
                     end: Double? = nil,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        
        let outputFileName = NSUUID().uuidString
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName).appendingPathExtension("mov")
        
        // Remove existing file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        Task {
            do {
                guard let exportSession = Self.makeExportSession(for: asset, codec: codecPreference) else {
                    throw NSError(domain: "VideoProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
                }
                
                // Configure Session
                // Note: export(to:as:) sets outputURL and outputFileType, so we don't need to set them on session if we pass them.
                // But we definitely need to set videoComposition and timeRange BEFORE export.
                
                // Apply Video Composition (Async)
                let composition = try await createComposition(for: asset, preset: preset, adjustments: adjustments)
                exportSession.videoComposition = composition
                
                // Time Range
                if let start = start, let end = end {
                     let startTime = CMTime(seconds: start, preferredTimescale: 600)
                     let endTime = CMTime(seconds: end, preferredTimescale: 600)
                     exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
                }
                
                // Export (Async)
                try await exportSession.export(to: outputURL, as: .mov)
                
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Adjustment Logic
    
    private func applyAdjustments(_ settings: AdjustmentSettings, to image: CIImage) -> CIImage {
        var output = image
        
        // Exposure
        if settings.exposure != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(settings.exposure)
            output = exposure.outputImage ?? output
        }
        
        // Contrast, Saturation, Brightness
        if settings.contrast != 1.0 { // Assuming 1.0 is default
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.contrast = Float(settings.contrast)
            output = controls.outputImage ?? output
        }
        
        // Highlights & Shadows
        if abs(settings.highlights) > 0.0001 || abs(settings.shadows) > 0.0001 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = output
            // UI is -1...1 with 0 centered. Positive increases highlights.
            highlightShadow.highlightAmount = Float(min(max(1.0 + (settings.highlights * 0.90), 0.0), 2.0))
            highlightShadow.shadowAmount = Float(min(max(settings.shadows, -1.0), 1.0))
            output = highlightShadow.outputImage ?? output
        }
        
        return output
    }
}

// MARK: - Helper Structs

struct AdjustmentSettings {
    var exposure: Double = 0.0
    var contrast: Double = 1.0
    var highlights: Double = 0.0
    var shadows: Double = 0.0
}
