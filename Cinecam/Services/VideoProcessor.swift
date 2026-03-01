@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
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

    func createComposition(for asset: AVAsset,
                           adjustments: AdjustmentSettings?,
                           outputAspectRatio: OutputAspectRatioOption) async throws -> AVVideoComposition {
        let baseRenderSize = try await resolvedRenderSize(for: asset)
        let targetRenderSize = compositionRenderSize(for: baseRenderSize, aspectRatio: outputAspectRatio)

        let baseComposition = try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            let sourceImage = request.sourceImage
            let renderRect = self.compositionRenderRect(for: sourceImage.extent, aspectRatio: outputAspectRatio)

            var outputImage = sourceImage
            if let adjustments {
                outputImage = self.applyAdjustments(
                    adjustments,
                    to: outputImage,
                    at: request.compositionTime
                )
            }

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
        let hasVisualProcessing = !(adjustments?.isIdentity ?? true) || hasAspectRatioProcessing
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let frameRate = Int(max(1, round(Double(nominalFrameRate > 0 ? nominalFrameRate : 30))))
        let bitrateBps = Int(clampedBitrateMbps(targetBitrateMbps) * 1_000_000)

        let videoOutput: AVAssetReaderOutput
        let videoRenderSize: CGSize
        let videoTransform: CGAffineTransform

        if hasVisualProcessing {
            let composition = try await createComposition(for: asset,
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

    private func applyAdjustments(_ settings: AdjustmentSettings, to image: CIImage, at time: CMTime? = nil) -> CIImage {
        var output = image

        output = applyPrimaryTone(settings, to: output)
        output = applyWhiteBalance(settings, to: output)
        output = applyHueCast(settings, to: output)
        output = applyTextureAndDetail(settings, to: output)
        output = applyFilmFinish(settings, to: output, at: time)
        output = applyFinalEffects(settings, to: output, at: time)

        return output.cropped(to: image.extent)
    }

    private func applyPrimaryTone(_ settings: AdjustmentSettings, to image: CIImage) -> CIImage {
        var output = image

        if abs(settings.exposure) > 0.0001 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(settings.exposure)
            output = exposure.outputImage ?? output
        }

        let resolvedSaturation = min(max(1.0 + settings.saturationAdjustment, 0.0), 2.0)
        if abs(settings.contrast - 1.0) > 0.0001 || abs(resolvedSaturation - 1.0) > 0.0001 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.contrast = Float(settings.contrast)
            controls.saturation = Float(resolvedSaturation)
            output = controls.outputImage ?? output
        }

        if abs(settings.vibrance) > 0.0001 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = Float(settings.vibrance)
            output = vibrance.outputImage ?? output
        }

        if abs(settings.highlights) > 0.0001 || abs(settings.shadows) > 0.0001 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = output
            highlightShadow.highlightAmount = Float(min(max(1.0 + (settings.highlights * 0.9), 0.0), 2.0))
            highlightShadow.shadowAmount = Float(min(max(settings.shadows, -1.0), 1.0))
            output = highlightShadow.outputImage ?? output
        }

        return output
    }

    private func applyWhiteBalance(_ settings: AdjustmentSettings, to image: CIImage) -> CIImage {
        guard abs(settings.redBlueBalance) > 0.0001 || abs(settings.greenTint) > 0.0001 else {
            return image
        }

        let whiteBalance = CIFilter.temperatureAndTint()
        whiteBalance.inputImage = image
        whiteBalance.neutral = CIVector(x: 6500.0, y: 0.0)
        whiteBalance.targetNeutral = CIVector(
            x: 6500.0 + (settings.redBlueBalance * 1800.0),
            y: settings.greenTint * 180.0
        )
        return whiteBalance.outputImage ?? image
    }

    private func applyHueCast(_ settings: AdjustmentSettings, to image: CIImage) -> CIImage {
        var output = image

        if abs(settings.globalColorCast) > 0.0001 {
            output = applyGlobalCast(to: output,
                                     hue: settings.globalCastHue,
                                     amount: settings.globalColorCast)
        }

        if abs(settings.shadowsColorCast) > 0.0001 {
            output = applyMaskedCast(to: output,
                                     hue: settings.shadowsCastHue,
                                     amount: settings.shadowsColorCast,
                                     targetShadows: true)
        }

        if abs(settings.highlightsColorCast) > 0.0001 {
            output = applyMaskedCast(to: output,
                                     hue: settings.highlightsCastHue,
                                     amount: settings.highlightsColorCast,
                                     targetShadows: false)
        }

        return output
    }

    private func applyTextureAndDetail(_ settings: AdjustmentSettings, to image: CIImage) -> CIImage {
        var output = image

        if abs(settings.texture) > 0.0001 {
            if settings.texture > 0 {
                let sharpen = CIFilter.sharpenLuminance()
                sharpen.inputImage = output
                sharpen.sharpness = Float(settings.texture * 3.8)
                output = sharpen.outputImage ?? output

                let microUnsharp = CIFilter.unsharpMask()
                microUnsharp.inputImage = output
                microUnsharp.radius = Float(0.7 + (settings.texture * 1.5))
                microUnsharp.intensity = Float(0.6 + (settings.texture * 1.8))
                output = microUnsharp.outputImage ?? output
            } else {
                let soften = CIFilter.gaussianBlur()
                soften.inputImage = output
                soften.radius = Float(abs(settings.texture) * 3.2)
                if let softened = soften.outputImage?.cropped(to: output.extent) {
                    let alphaSoftened = withAlpha(softened, alpha: min(abs(settings.texture) * 0.9, 0.92))
                    output = alphaSoftened
                        .applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: output])
                        .cropped(to: output.extent)
                }
            }
        }

        if abs(settings.clarity) > 0.0001 {
            if settings.clarity > 0 {
                let unsharp = CIFilter.unsharpMask()
                unsharp.inputImage = output
                unsharp.radius = Float(1.8 + settings.clarity * 3.4)
                unsharp.intensity = Float(0.9 + settings.clarity * 3.0)
                output = unsharp.outputImage ?? output

                let boost = CIFilter.colorControls()
                boost.inputImage = output
                boost.contrast = Float(1.0 + (settings.clarity * 0.08))
                output = boost.outputImage ?? output
            } else {
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = output
                blur.radius = Float(abs(settings.clarity) * 3.6)
                if let blurred = blur.outputImage?.cropped(to: output.extent) {
                    let alphaBlurred = withAlpha(blurred, alpha: min(abs(settings.clarity) * 0.95, 0.96))
                    output = alphaBlurred
                        .applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: output])
                        .cropped(to: output.extent)
                }
            }
        }

        return output
    }

    private func applyFilmFinish(_ settings: AdjustmentSettings, to image: CIImage, at time: CMTime?) -> CIImage {
        var output = image

        if settings.grain > 0.0001 {
            output = applyFilmGrain(to: output, amount: settings.grain, at: time)
        }

        if settings.vignette > 0.0001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = output
            vignette.intensity = Float(settings.vignette * 1.5)
            vignette.radius = Float(1.0 + settings.vignette * 1.8)
            output = vignette.outputImage ?? output
        }

        return output
    }

    private func applyFinalEffects(_ settings: AdjustmentSettings, to image: CIImage, at time: CMTime?) -> CIImage {
        var output = image

        if settings.bloom > 0.0001 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = output
            bloom.intensity = Float(settings.bloom * 0.9)
            bloom.radius = Float(8.0 + settings.bloom * 20.0)
            output = bloom.outputImage ?? output
        }

        if settings.softGlow > 0.0001 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = output
            bloom.intensity = Float(settings.softGlow * 0.45)
            bloom.radius = Float(15.0 + settings.softGlow * 18.0)
            output = bloom.outputImage ?? output
        }

        if settings.vhsAmount > 0.0001 {
            output = applyDustAndScratchesEffect(to: output, amount: settings.vhsAmount, at: time)
        }

        return output
    }

    private func applyGlobalCast(to image: CIImage, hue: Double, amount: Double) -> CIImage {
        let strength = min(max(abs(amount), 0.0), 1.0) * 0.28
        guard strength > 0.0001 else { return image }

        let color = resolvedCastColor(baseHue: hue, signedAmount: amount)
        let tint = CIImage(color: CIColor(color: color.withAlphaComponent(strength))).cropped(to: image.extent)
        return tint
            .applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: image.extent)
    }

    private func applyMaskedCast(to image: CIImage,
                                 hue: Double,
                                 amount: Double,
                                 targetShadows: Bool) -> CIImage {
        let strength = min(max(abs(amount), 0.0), 1.0)
        guard strength > 0.0001 else { return image }

        let luminance = image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputBrightnessKey: 0.0,
                kCIInputContrastKey: 1.0
            ]
        )

        let tonalMaskBase = targetShadows
            ? luminance.applyingFilter("CIColorInvert")
            : luminance

        let alphaMask = tonalMaskBase
            .applyingFilter("CIMaskToAlpha")
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: strength * 0.75)
                ]
            )
            .cropped(to: image.extent)

        let color = resolvedCastColor(baseHue: hue, signedAmount: amount)
        let tint = CIImage(color: CIColor(color: color)).cropped(to: image.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = tint
        blend.backgroundImage = image
        blend.maskImage = alphaMask
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applyFilmGrain(to image: CIImage, amount: Double, at time: CMTime?) -> CIImage {
        let intensity = min(max(amount, 0.0), 1.0)
        guard intensity > 0.0001 else { return image }
        guard let noiseA = CIFilter.randomGenerator().outputImage,
              let noiseB = CIFilter.randomGenerator().outputImage else { return image }

        let frameSeed = Int((time?.value ?? 0) & 0x7fff_ffff)
        let offsetA = pseudoRandomOffset(frame: frameSeed, salt: 19)
        let offsetB = pseudoRandomOffset(frame: frameSeed, salt: 53)
        let scaleA = 0.75 + (pseudoRandom(frameSeed + 337) * 0.9)
        let scaleB = 0.85 + (pseudoRandom(frameSeed + 761) * 0.75)
        let rotationA = (pseudoRandom(frameSeed + 541) - 0.5) * 0.10
        let rotationB = (pseudoRandom(frameSeed + 941) - 0.5) * 0.12

        let animatedNoiseA = noiseA
            .transformed(by: CGAffineTransform(translationX: offsetA.x, y: offsetA.y))
            .transformed(by: CGAffineTransform(scaleX: scaleA, y: scaleA))
            .transformed(by: CGAffineTransform(rotationAngle: rotationA))
            .clampedToExtent()
            .cropped(to: image.extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.9 + (intensity * 1.2),
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.02 + (intensity * 0.08)])
            .cropped(to: image.extent)

        let animatedNoiseB = noiseB
            .transformed(by: CGAffineTransform(translationX: offsetB.x, y: offsetB.y))
            .transformed(by: CGAffineTransform(scaleX: scaleB, y: scaleB))
            .transformed(by: CGAffineTransform(rotationAngle: rotationB))
            .clampedToExtent()
            .cropped(to: image.extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.8 + (intensity * 1.0),
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.01 + (intensity * 0.06)])
            .cropped(to: image.extent)

        let combinedNoise = animatedNoiseA
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: animatedNoiseB])
            .cropped(to: image.extent)
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 0.5, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.5, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.5, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.0)
                ]
            )
            .cropped(to: image.extent)

        // Build neutral grain around 50% gray; overlay blend is luminance-neutral at 50%.
        let amplitude = CGFloat(0.36 + (intensity * 0.58))
        let neutralGrain = combinedNoise.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amplitude, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.0),
                "inputBiasVector": CIVector(
                    x: (1.0 - amplitude) * 0.5,
                    y: (1.0 - amplitude) * 0.5,
                    z: (1.0 - amplitude) * 0.5,
                    w: 0.0
                )
            ]
        ).cropped(to: image.extent)

        let overlayResult = neutralGrain
            .applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: image.extent)

        let mix = CGFloat(0.18 + (intensity * 0.72))
        let mask = CIImage(color: CIColor(red: mix, green: mix, blue: mix, alpha: 1.0)).cropped(to: image.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = overlayResult
        blend.backgroundImage = image
        blend.maskImage = mask

        return (blend.outputImage ?? image)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: image.extent)
    }

    private func applyDustAndScratchesEffect(to image: CIImage, amount: Double, at time: CMTime?) -> CIImage {
        let normalized = min(max(amount, 0.0), 1.0)
        guard normalized > 0.0001 else { return image }

        let frameSeed = Int((time?.value ?? 0) & 0x7fff_ffff)
        let extent = image.extent

        guard let noise = CIFilter.randomGenerator().outputImage else { return image }

        let offset = pseudoRandomOffset(frame: frameSeed, salt: 97)
        // Vary speck size per frame for irregular natural shapes
        let speckSize: CGFloat = 4.0 + CGFloat(pseudoRandom(frameSeed &+ 77)) * 10.0

        let spots = noise
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
            .transformed(by: CGAffineTransform(scaleX: speckSize, y: speckSize))
            .clampedToExtent()
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 10.0,
                kCIInputBrightnessKey: -0.88  // fixed threshold — moderate spot density
            ])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.5])
            .cropped(to: extent)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])

        // Slider controls opacity smoothly via power curve — very subtle at low end
        let maskOpacity = pow(normalized, 2.0)
        let mask = spots
            .applyingFilter("CIMaskToAlpha")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: maskOpacity)
            ])
            .cropped(to: extent)

        let black = CIImage(color: CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
            .cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = black
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private func pseudoRandom(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }

    private func pseudoRandomOffset(frame: Int, salt: Int) -> CGPoint {
        let x = (pseudoRandom((frame &* 1597) &+ (salt &* 13)) - 0.5) * 4096.0
        let y = (pseudoRandom((frame &* 3571) &+ (salt &* 29)) - 0.5) * 4096.0
        return CGPoint(x: x, y: y)
    }

    private func withAlpha(_ image: CIImage, alpha: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(max(alpha, 0.0), 1.0))
        ])
    }

    private func resolvedCastColor(baseHue: Double, signedAmount: Double) -> UIColor {
        let wrappedHue = baseHue.truncatingRemainder(dividingBy: 360)
        let normalizedHue = (wrappedHue < 0 ? wrappedHue + 360 : wrappedHue) / 360.0
        let hue = signedAmount >= 0 ? normalizedHue : ((normalizedHue + 0.5).truncatingRemainder(dividingBy: 1.0))
        return UIColor(hue: CGFloat(hue), saturation: 0.70, brightness: 0.58, alpha: 1.0)
    }

}

// MARK: - Models

struct AdjustmentSettings {
    // Step 1
    var exposure: Double = 0.0
    var contrast: Double = 1.0
    var highlights: Double = 0.0
    var shadows: Double = 0.0

    // Step 2
    var redBlueBalance: Double = 0.0
    var greenTint: Double = 0.0
    var saturationAdjustment: Double = 0.0
    var vibrance: Double = 0.0

    // Step 3
    var globalCastHue: Double = 35.0
    var shadowsCastHue: Double = 220.0
    var highlightsCastHue: Double = 95.0
    var globalColorCast: Double = 0.0
    var shadowsColorCast: Double = 0.0
    var highlightsColorCast: Double = 0.0

    // Step 4
    var texture: Double = 0.0
    var clarity: Double = 0.0
    var grain: Double = 0.0
    var vignette: Double = 0.0

    // Step 5
    var bloom: Double = 0.0
    var softGlow: Double = 0.0
    var vhsAmount: Double = 0.0

    var isIdentity: Bool {
        abs(exposure) < 0.0001 &&
        abs(contrast - 1.0) < 0.0001 &&
        abs(highlights) < 0.0001 &&
        abs(shadows) < 0.0001 &&
        abs(redBlueBalance) < 0.0001 &&
        abs(greenTint) < 0.0001 &&
        abs(saturationAdjustment) < 0.0001 &&
        abs(vibrance) < 0.0001 &&
        abs(globalColorCast) < 0.0001 &&
        abs(shadowsColorCast) < 0.0001 &&
        abs(highlightsColorCast) < 0.0001 &&
        abs(texture) < 0.0001 &&
        abs(clarity) < 0.0001 &&
        abs(grain) < 0.0001 &&
        abs(vignette) < 0.0001 &&
        abs(bloom) < 0.0001 &&
        abs(softGlow) < 0.0001 &&
        abs(vhsAmount) < 0.0001
    }
}
