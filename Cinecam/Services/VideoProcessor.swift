@preconcurrency import AVFoundation
import CoreImage
import SwiftUI
import Combine
import VideoToolbox

class VideoProcessor: ObservableObject {
    private struct UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private enum ExportError: LocalizedError {
        case missingVideoTrack
        case readerSetupFailed(String)
        case writerSetupFailed(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "No video track found in the source asset."
            case .readerSetupFailed(let message):
                return message
            case .writerSetupFailed(let message):
                return message
            case .exportFailed(let message):
                return message
            }
        }
    }

    // MARK: - Playback Composition

    /// Creates an AVVideoComposition to apply the preset and adjustments in real-time during playback.
    func createComposition(for asset: AVAsset,
                           preset: MoviePreset?,
                           adjustments: AdjustmentSettings?,
                           outputAspectRatio: OutputAspectRatioOption) async throws -> AVVideoComposition {
        let baseRenderSize = try await resolvedRenderSize(for: asset)
        let targetRenderSize = compositionRenderSize(for: baseRenderSize, aspectRatio: outputAspectRatio)
        
        let baseComposition = try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
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

            let renderRect = self.compositionRenderRect(for: sourceImage.extent, aspectRatio: outputAspectRatio)
            let shiftedOutput = outputImage
                .cropped(to: renderRect)
                .transformed(by: CGAffineTransform(translationX: -renderRect.origin.x, y: -renderRect.origin.y))
                .cropped(to: CGRect(origin: .zero, size: renderRect.size))
            request.finish(with: shiftedOutput, context: nil)
        })
        
        let configuration = AVVideoComposition.Configuration(
            animationTool: baseComposition.animationTool,
            colorPrimaries: baseComposition.colorPrimaries,
            colorTransferFunction: baseComposition.colorTransferFunction,
            colorYCbCrMatrix: baseComposition.colorYCbCrMatrix,
            customVideoCompositorClass: baseComposition.customVideoCompositorClass,
            frameDuration: baseComposition.frameDuration,
            instructions: baseComposition.instructions,
            outputBufferDescription: baseComposition.outputBufferDescription,
            perFrameHDRDisplayMetadataPolicy: baseComposition.perFrameHDRDisplayMetadataPolicy,
            renderScale: baseComposition.renderScale,
            renderSize: targetRenderSize,
            sourceSampleDataTrackIDs: baseComposition.sourceSampleDataTrackIDs,
            sourceTrackIDForFrameTiming: baseComposition.sourceTrackIDForFrameTiming,
            spatialVideoConfigurations: baseComposition.spatialVideoConfigurations
        )
        return AVVideoComposition(configuration: configuration)
    }

    // MARK: - Export

    func exportVideo(asset: AVAsset,
                     preset: MoviePreset?,
                     adjustments: AdjustmentSettings?,
                     outputAspectRatio: OutputAspectRatioOption,
                     targetBitrateMbps: Double,
                     start: Double? = nil,
                     end: Double? = nil,
                     progress: ((Double) -> Void)? = nil,
                     completion: @escaping (Result<URL, Error>) -> Void) {

        let outputFileName = NSUUID().uuidString
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(outputFileName)
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        Task {
            do {
                DispatchQueue.main.async {
                    progress?(0.0)
                }

                let finalURL = try await transcodeAsset(asset: asset,
                                                        outputURL: outputURL,
                                                        preset: preset,
                                                        adjustments: adjustments,
                                                        outputAspectRatio: outputAspectRatio,
                                                        targetBitrateMbps: targetBitrateMbps,
                                                        start: start,
                                                        end: end,
                                                        progress: progress)

                DispatchQueue.main.async {
                    progress?(1.0)
                    completion(.success(finalURL))
                }
            } catch {
                DispatchQueue.main.async {
                    progress?(0.0)
                    completion(.failure(error))
                }
            }
        }
    }

    private func transcodeAsset(asset: AVAsset,
                                outputURL: URL,
                                preset: MoviePreset?,
                                adjustments: AdjustmentSettings?,
                                outputAspectRatio: OutputAspectRatioOption,
                                targetBitrateMbps: Double,
                                start: Double?,
                                end: Double?,
                                progress: ((Double) -> Void)?) async throws -> URL {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let assetDuration = try await asset.load(.duration)
        let timeRange = resolvedTimeRange(assetDuration: assetDuration, start: start, end: end)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let writer = try AVAssetWriter(url: outputURL, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = false
        let sendableWriter = UncheckedSendableBox(value: writer)
        let sendableReader = UncheckedSendableBox(value: reader)

        let hasAspectRatioProcessing = outputAspectRatio != .native16x9
        let hasVisualProcessing = preset != nil || !(adjustments?.isIdentity ?? true) || hasAspectRatioProcessing
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let frameRate = Int(max(1, round(Double(nominalFrameRate > 0 ? nominalFrameRate : 30))))
        let bitrateBps = Int(clampedBitrateMbps(targetBitrateMbps) * 1_000_000)

        let videoOutput: AVAssetReaderOutput
        let videoRenderSize: CGSize
        let videoTransform: CGAffineTransform

        if hasVisualProcessing {
            let composition = try await createComposition(for: asset,
                                                          preset: preset,
                                                          adjustments: adjustments,
                                                          outputAspectRatio: outputAspectRatio)
            let readerOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            )
            readerOutput.videoComposition = composition
            readerOutput.alwaysCopiesSampleData = false

            videoOutput = readerOutput
            videoRenderSize = composition.renderSize
            videoTransform = .identity
        } else {
            let readerOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            )
            readerOutput.alwaysCopiesSampleData = false

            videoOutput = readerOutput
            videoRenderSize = try await videoTrack.load(.naturalSize)
            videoTransform = try await videoTrack.load(.preferredTransform)
        }

        guard reader.canAdd(videoOutput) else {
            throw ExportError.readerSetupFailed("Unable to add video output to reader.")
        }
        reader.add(videoOutput)

        let encodedSize = sanitizedRenderSize(videoRenderSize)
        var compression: [String: Any] = [
            kVTCompressionPropertyKey_AverageBitRate as String: bitrateBps,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoAllowFrameReorderingKey: false
        ]
        compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(encodedSize.width),
            AVVideoHeightKey: Int(encodedSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = videoTransform
        let sendableVideoInput = UncheckedSendableBox(value: videoInput)
        let sendableVideoOutput = UncheckedSendableBox(value: videoOutput)

        guard writer.canAdd(videoInput) else {
            throw ExportError.writerSetupFailed("Unable to add video input to writer.")
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?

        if let audioTrack {
            let candidateOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            candidateOutput.alwaysCopiesSampleData = false
            let candidateInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            candidateInput.expectsMediaDataInRealTime = false

            if reader.canAdd(candidateOutput), writer.canAdd(candidateInput) {
                reader.add(candidateOutput)
                writer.add(candidateInput)
                audioOutput = candidateOutput
                audioInput = candidateInput
            }
        }

        guard writer.startWriting() else {
            throw ExportError.writerSetupFailed(writer.error?.localizedDescription ?? "Writer failed to start writing.")
        }

        guard reader.startReading() else {
            throw ExportError.readerSetupFailed(reader.error?.localizedDescription ?? "Reader failed to start reading.")
        }

        writer.startSession(atSourceTime: timeRange.start)

        let startSeconds = CMTimeGetSeconds(timeRange.start)
        let durationSeconds = max(CMTimeGetSeconds(timeRange.duration), 0.001)

        let stateQueue = DispatchQueue(label: "com.cinecam.export.state")
        var exportError: Error?
        var lastProgressSent = 0.0

        let dispatchGroup = DispatchGroup()

        func setExportErrorIfNeeded(_ error: Error?) {
            guard let error else { return }
            stateQueue.sync {
                if exportError == nil {
                    exportError = error
                }
            }
        }

        dispatchGroup.enter()
        let videoQueue = DispatchQueue(label: "com.cinecam.export.video", qos: .userInitiated)
        var videoLoopFinished = false

        sendableVideoInput.value.requestMediaDataWhenReady(on: videoQueue) {
            guard !videoLoopFinished else { return }

            while sendableVideoInput.value.isReadyForMoreMediaData {
                let hasError = stateQueue.sync { exportError != nil }

                if hasError {
                    sendableVideoInput.value.markAsFinished()
                    videoLoopFinished = true
                    dispatchGroup.leave()
                    return
                }

                if let sample = sendableVideoOutput.value.copyNextSampleBuffer() {
                    if !sendableVideoInput.value.append(sample) {
                        setExportErrorIfNeeded(sendableWriter.value.error)
                        sendableVideoInput.value.markAsFinished()
                        videoLoopFinished = true
                        dispatchGroup.leave()
                        return
                    }

                    if let progress {
                        let sampleSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                        let normalized = min(max((sampleSeconds - startSeconds) / durationSeconds, 0.0), 0.99)
                        let shouldEmitProgress = stateQueue.sync {
                            if normalized - lastProgressSent >= 0.01 {
                                lastProgressSent = normalized
                                return true
                            }
                            return false
                        }
                        if shouldEmitProgress {
                            DispatchQueue.main.async {
                                progress(normalized)
                            }
                        }
                    }
                } else {
                    if sendableReader.value.status == .failed {
                        setExportErrorIfNeeded(sendableReader.value.error)
                    }
                    sendableVideoInput.value.markAsFinished()
                    videoLoopFinished = true
                    dispatchGroup.leave()
                    return
                }
            }
        }

        if let audioInput, let audioOutput {
            let sendableAudioInput = UncheckedSendableBox(value: audioInput)
            let sendableAudioOutput = UncheckedSendableBox(value: audioOutput)
            dispatchGroup.enter()
            let audioQueue = DispatchQueue(label: "com.cinecam.export.audio", qos: .utility)
            var audioLoopFinished = false

            sendableAudioInput.value.requestMediaDataWhenReady(on: audioQueue) {
                guard !audioLoopFinished else { return }

                while sendableAudioInput.value.isReadyForMoreMediaData {
                    let hasError = stateQueue.sync { exportError != nil }

                    if hasError {
                        sendableAudioInput.value.markAsFinished()
                        audioLoopFinished = true
                        dispatchGroup.leave()
                        return
                    }

                    if let sample = sendableAudioOutput.value.copyNextSampleBuffer() {
                        if !sendableAudioInput.value.append(sample) {
                            setExportErrorIfNeeded(sendableWriter.value.error)
                            sendableAudioInput.value.markAsFinished()
                            audioLoopFinished = true
                            dispatchGroup.leave()
                            return
                        }
                    } else {
                        if sendableReader.value.status == .failed {
                            setExportErrorIfNeeded(sendableReader.value.error)
                        }
                        sendableAudioInput.value.markAsFinished()
                        audioLoopFinished = true
                        dispatchGroup.leave()
                        return
                    }
                }
            }
        }

        await withCheckedContinuation { continuation in
            dispatchGroup.notify(queue: DispatchQueue.global(qos: .utility)) {
                continuation.resume()
            }
        }

        let capturedError = stateQueue.sync { exportError }

        if let capturedError {
            reader.cancelReading()
            writer.cancelWriting()
            throw capturedError
        }

        if reader.status == .failed {
            throw ExportError.exportFailed(reader.error?.localizedDescription ?? "Reader failed during export.")
        }

        try await finishWriting(writer)

        if writer.status == .failed {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Writer failed during export.")
        }

        return outputURL
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let sendableWriter = UncheckedSendableBox(value: writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendableWriter.value.finishWriting {
                if let error = sendableWriter.value.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    private func resolvedTimeRange(assetDuration: CMTime, start: Double?, end: Double?) -> CMTimeRange {
        guard let start, let end, end > start else {
            return CMTimeRange(start: .zero, duration: assetDuration)
        }

        let totalSeconds = max(CMTimeGetSeconds(assetDuration), 0)
        let clampedStart = max(0, min(start, totalSeconds))
        let clampedEnd = max(clampedStart, min(end, totalSeconds))

        let startTime = CMTime(seconds: clampedStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: clampedEnd, preferredTimescale: 600)
        return CMTimeRange(start: startTime, end: endTime)
    }

    private func sanitizedRenderSize(_ size: CGSize) -> CGSize {
        let width = max(2, Int(abs(size.width).rounded()))
        let height = max(2, Int(abs(size.height).rounded()))

        let evenWidth = width % 2 == 0 ? width : width - 1
        let evenHeight = height % 2 == 0 ? height : height - 1

        return CGSize(width: evenWidth, height: evenHeight)
    }
    
    private func resolvedRenderSize(for asset: AVAsset) async throws -> CGSize {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }
    
    private func compositionRenderSize(for sourceSize: CGSize, aspectRatio: OutputAspectRatioOption) -> CGSize {
        let safeSource = sanitizedRenderSize(sourceSize)
        guard let targetRatio = aspectRatio.targetAspectRatio(for: safeSource) else {
            return safeSource
        }
        
        let sourceRatio = safeSource.width / safeSource.height
        var outputWidth = safeSource.width
        var outputHeight = safeSource.height
        
        if sourceRatio > targetRatio {
            outputWidth = safeSource.height * targetRatio
        } else {
            outputHeight = safeSource.width / targetRatio
        }
        
        return sanitizedRenderSize(CGSize(width: outputWidth, height: outputHeight))
    }
    
    private func compositionRenderRect(for sourceExtent: CGRect, aspectRatio: OutputAspectRatioOption) -> CGRect {
        let width = abs(sourceExtent.width)
        let height = abs(sourceExtent.height)
        guard width > 0, height > 0 else { return sourceExtent }
        
        guard let targetRatio = aspectRatio.targetAspectRatio(for: CGSize(width: width, height: height)) else {
            return sourceExtent
        }
        
        let sourceRatio = width / height
        var cropRect = sourceExtent
        
        if sourceRatio > targetRatio {
            let croppedWidth = height * targetRatio
            cropRect.origin.x = sourceExtent.midX - (croppedWidth / 2.0)
            cropRect.size.width = croppedWidth
        } else {
            let croppedHeight = width / targetRatio
            cropRect.origin.y = sourceExtent.midY - (croppedHeight / 2.0)
            cropRect.size.height = croppedHeight
        }
        
        return cropRect
    }

    private func clampedBitrateMbps(_ value: Double) -> Double {
        min(max(value, CameraManager.bitrateRangeMbps.lowerBound), CameraManager.bitrateRangeMbps.upperBound)
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

    var isIdentity: Bool {
        abs(exposure) < 0.0001 &&
        abs(contrast - 1.0) < 0.0001 &&
        abs(highlights) < 0.0001 &&
        abs(shadows) < 0.0001
    }
}
