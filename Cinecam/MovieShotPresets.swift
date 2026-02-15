import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import Foundation
import UIKit

// MARK: - Models

public enum MoviePreset: String, CaseIterable, Identifiable {
    case matrix
    case bladeRunner2049
    case sinCity
    case theBatman
    case strangerThings
    case dune
    case drive
    case madMax
    case revenant
    case inTheMoodForLove
    case seven
    case vertigo
    case orderOfPhoenix
    case hero
    case laLaLand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .matrix: return "MathX"
        case .bladeRunner2049: return "Runner 2094"
        case .sinCity: return "Hell City"
        case .theBatman: return "Darkman"
        case .strangerThings: return "Weird Things"
        case .dune: return "Arrakis Dust"
        case .drive: return "Night Drive"
        case .madMax: return "Fury Heat"
        case .revenant: return "Risen One"
        case .inTheMoodForLove: return "Mood for Love"
        case .seven: return "Seven Sins"
        case .vertigo: return "Spiral"
        case .orderOfPhoenix: return "Dark Order"
        case .hero: return "Ying Xiong"
        case .laLaLand: return "La La"
        }
    }

    public var subtitle: String {
        switch self {
        case .matrix: return "Green cast, cooler mids, high contrast"
        case .bladeRunner2049: return "Orange highlights, teal-purple shadows, wide dynamic range"
        case .sinCity: return "High contrast B&W, crushed shadows, noir"
        case .theBatman: return "Dark desaturated, teal shadows, crushed blacks"
        case .strangerThings: return "Kodachrome amber, teal shadows, vivid 80s palette"
        case .dune: return "Dusty amber desert, cool shadows, cinematic haze"
        case .drive: return "Magenta-cyan neon, glossy blacks, night contrast"
        case .madMax: return "Aggressive orange-teal, gritty contrast, heat"
        case .revenant: return "Cold desaturated earth, natural dramatic tone"
        case .inTheMoodForLove: return "Rich tungsten reds, jade greens, soft glow"
        case .seven: return "Bleach bypass grit, cyan shadows, heavy grain"
        case .vertigo: return "Rich Technicolor reds, mysterious greens, dreamy fog"
        case .orderOfPhoenix: return "Heavy blue-teal cast, crushed shadows, dark desaturated"
        case .hero: return "Vivid saturated primaries, epic color contrast"
        case .laLaLand: return "Pastel dreamscape, warm magic hour, soft grain"
        }
    }
}

public struct FilmFinishSettings {
    public let grainAmount: CGFloat
    public let grainSize: CGFloat
    public let vignetteStrength: CGFloat
    public let vignetteSoftness: CGFloat
    public let chromaticAberration: CGFloat
    public let bloomIntensity: CGFloat
    public let bloomRadius: CGFloat
}

private struct GradeProfile {
    let rVector: CIVector
    let gVector: CIVector
    let bVector: CIVector
    let biasVector: CIVector
    let saturation: Float
    let contrast: Float
    let brightness: Float
    let targetTemperature: CGFloat
    let targetTint: CGFloat
    let exposure: Float
    let shadowAmount: Float
    let highlightAmount: Float
}

// MARK: - Preset Service

public struct PresetService {
    private static let baseTemperature: CGFloat = 6500
    private static let presetContrastCompression: Float = 0.32
    private static let presetExposureCompression: Float = 0.45
    private static let presetBrightnessLift: Float = 0.012
    private static let minimumShadowLift: Float = 0.16
    private static let minimumHighlightAmount: Float = 0.90

    public static func apply(preset: MoviePreset, to image: CIImage, at time: CMTime? = nil) -> CIImage {
        let graded = applyColorGrading(preset, to: image)
        return applyFinish(preset, to: graded, at: time)
    }

    public static func applyColorGrading(_ preset: MoviePreset, to image: CIImage) -> CIImage {
        switch preset {
        case .sinCity:
            return applySinCityGrade(to: image)
        default:
            return applyProfile(profile(for: preset), to: image)
        }
    }

    public static func applyFinish(_ preset: MoviePreset, to image: CIImage, at time: CMTime? = nil) -> CIImage {
        let settings = filmFinishSettings(for: preset)
        var output = image

        let normalizedBloomIntensity = min(settings.bloomIntensity * 0.55, 0.12)
        let normalizedBloomRadius = min(settings.bloomRadius, 8.0)
        output = applyBloom(to: output, intensity: normalizedBloomIntensity, radius: normalizedBloomRadius)
        output = normalizeHighlights(in: output)
        output = applyChromaticAberration(to: output, amount: settings.chromaticAberration)
        output = applyFilmGrain(to: output, amount: settings.grainAmount, size: settings.grainSize, at: time)

        return output.cropped(to: image.extent)
    }

    // MARK: - Grade Profiles

    private static func profile(for preset: MoviePreset) -> GradeProfile {
        switch preset {
        case .matrix:
            return GradeProfile(
                rVector: CIVector(x: 0.93, y: 0.05, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.10, y: 1.04, z: 0.03, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.10, z: 0.74, w: 0.0),
                biasVector: CIVector(x: 0.000, y: 0.006, z: 0.000, w: 0.0),
                saturation: 0.78,
                contrast: 1.14,
                brightness: -0.008,
                targetTemperature: 5750,
                targetTint: -16,
                exposure: -0.06,
                shadowAmount: 0.10,
                highlightAmount: 0.94
            )

        case .bladeRunner2049:
            return GradeProfile(
                rVector: CIVector(x: 1.09, y: 0.07, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.03, y: 0.91, z: 0.10, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.15, z: 0.84, w: 0.0),
                biasVector: CIVector(x: 0.012, y: 0.006, z: 0.022, w: 0.0),
                saturation: 0.96,
                contrast: 1.17,
                brightness: 0.010,
                targetTemperature: 7050,
                targetTint: 14,
                exposure: -0.03,
                shadowAmount: 0.12,
                highlightAmount: 0.88
            )

        case .theBatman:
            return GradeProfile(
                rVector: CIVector(x: 0.88, y: 0.06, z: 0.04, w: 0.0),
                gVector: CIVector(x: 0.05, y: 0.90, z: 0.09, w: 0.0),
                bVector: CIVector(x: 0.01, y: 0.12, z: 0.84, w: 0.0),
                biasVector: CIVector(x: 0.006, y: 0.010, z: 0.014, w: 0.0),
                saturation: 0.58,
                contrast: 1.12,
                brightness: -0.022,
                targetTemperature: 5400,
                targetTint: -14,
                exposure: -0.24,
                shadowAmount: 0.18,
                highlightAmount: 0.88
            )

        case .strangerThings:
            return GradeProfile(
                rVector: CIVector(x: 1.07, y: 0.07, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.03, y: 0.95, z: 0.03, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.15, z: 0.79, w: 0.0),
                biasVector: CIVector(x: 0.018, y: 0.010, z: -0.006, w: 0.0),
                saturation: 1.08,
                contrast: 1.12,
                brightness: -0.005,
                targetTemperature: 5600,
                targetTint: 10,
                exposure: -0.03,
                shadowAmount: 0.04,
                highlightAmount: 0.93
            )

        case .dune:
            return GradeProfile(
                rVector: CIVector(x: 1.08, y: 0.09, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.07, y: 0.98, z: 0.03, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.10, z: 0.74, w: 0.0),
                biasVector: CIVector(x: 0.014, y: 0.007, z: -0.014, w: 0.0),
                saturation: 0.80,
                contrast: 1.10,
                brightness: -0.020,
                targetTemperature: 5200,
                targetTint: -6,
                exposure: -0.12,
                shadowAmount: 0.02,
                highlightAmount: 0.88
            )

        case .drive:
            return GradeProfile(
                rVector: CIVector(x: 1.12, y: 0.03, z: 0.08, w: 0.0),
                gVector: CIVector(x: 0.02, y: 0.90, z: 0.09, w: 0.0),
                bVector: CIVector(x: 0.02, y: 0.11, z: 1.02, w: 0.0),
                biasVector: CIVector(x: 0.008, y: -0.002, z: 0.014, w: 0.0),
                saturation: 1.14,
                contrast: 1.16,
                brightness: -0.015,
                targetTemperature: 7100,
                targetTint: 22,
                exposure: -0.03,
                shadowAmount: 0.10,
                highlightAmount: 0.94
            )

        case .madMax:
            return GradeProfile(
                rVector: CIVector(x: 1.20, y: 0.12, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.04, y: 0.91, z: 0.06, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.14, z: 0.74, w: 0.0),
                biasVector: CIVector(x: 0.024, y: 0.010, z: -0.018, w: 0.0),
                saturation: 1.16,
                contrast: 1.16,
                brightness: -0.010,
                targetTemperature: 5000,
                targetTint: 6,
                exposure: -0.01,
                shadowAmount: 0.08,
                highlightAmount: 0.89
            )

        case .revenant:
            return GradeProfile(
                rVector: CIVector(x: 0.88, y: 0.05, z: 0.07, w: 0.0),
                gVector: CIVector(x: 0.03, y: 0.95, z: 0.08, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.11, z: 1.00, w: 0.0),
                biasVector: CIVector(x: -0.004, y: 0.002, z: 0.008, w: 0.0),
                saturation: 0.72,
                contrast: 1.08,
                brightness: -0.018,
                targetTemperature: 7000,
                targetTint: -4,
                exposure: -0.08,
                shadowAmount: 0.04,
                highlightAmount: 0.92
            )

        case .inTheMoodForLove:
            return GradeProfile(
                rVector: CIVector(x: 1.14, y: 0.09, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.08, y: 0.94, z: 0.03, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.11, z: 0.74, w: 0.0),
                biasVector: CIVector(x: 0.018, y: 0.008, z: -0.006, w: 0.0),
                saturation: 1.05,
                contrast: 1.10,
                brightness: 0.002,
                targetTemperature: 5300,
                targetTint: 20,
                exposure: -0.02,
                shadowAmount: 0.06,
                highlightAmount: 0.90
            )

        case .seven:
            return GradeProfile(
                rVector: CIVector(x: 0.86, y: 0.06, z: 0.05, w: 0.0),
                gVector: CIVector(x: 0.03, y: 0.95, z: 0.08, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.10, z: 0.92, w: 0.0),
                biasVector: CIVector(x: -0.010, y: 0.000, z: 0.010, w: 0.0),
                saturation: 0.62,
                contrast: 1.12,
                brightness: -0.018,
                targetTemperature: 5250,
                targetTint: -14,
                exposure: -0.10,
                shadowAmount: 0.10,
                highlightAmount: 0.87
            )

        case .vertigo:
            return GradeProfile(
                rVector: CIVector(x: 1.10, y: 0.05, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.05, y: 1.05, z: 0.02, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.06, z: 0.82, w: 0.0),
                biasVector: CIVector(x: 0.012, y: 0.008, z: -0.004, w: 0.0),
                saturation: 1.18,
                contrast: 1.10,
                brightness: 0.010,
                targetTemperature: 5850,
                targetTint: 12,
                exposure: 0.02,
                shadowAmount: 0.08,
                highlightAmount: 0.90
            )

        case .orderOfPhoenix:
            return GradeProfile(
                rVector: CIVector(x: 0.86, y: 0.05, z: 0.04, w: 0.0),
                gVector: CIVector(x: 0.02, y: 0.94, z: 0.07, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.11, z: 1.03, w: 0.0),
                biasVector: CIVector(x: -0.008, y: 0.000, z: 0.016, w: 0.0),
                saturation: 0.68,
                contrast: 1.08,
                brightness: -0.016,
                targetTemperature: 5000,
                targetTint: -12,
                exposure: -0.08,
                shadowAmount: 0.10,
                highlightAmount: 0.88
            )

        case .hero:
            return GradeProfile(
                rVector: CIVector(x: 1.12, y: 0.05, z: 0.00, w: 0.0),
                gVector: CIVector(x: 0.05, y: 1.02, z: 0.02, w: 0.0),
                bVector: CIVector(x: 0.00, y: 0.05, z: 0.86, w: 0.0),
                biasVector: CIVector(x: 0.014, y: 0.004, z: -0.008, w: 0.0),
                saturation: 1.30,
                contrast: 1.16,
                brightness: 0.000,
                targetTemperature: 5400,
                targetTint: 8,
                exposure: -0.02,
                shadowAmount: 0.02,
                highlightAmount: 0.92
            )

        case .laLaLand:
            return GradeProfile(
                rVector: CIVector(x: 1.05, y: 0.05, z: 0.02, w: 0.0),
                gVector: CIVector(x: 0.03, y: 0.98, z: 0.04, w: 0.0),
                bVector: CIVector(x: 0.01, y: 0.06, z: 0.90, w: 0.0),
                biasVector: CIVector(x: 0.016, y: 0.010, z: 0.012, w: 0.0),
                saturation: 1.10,
                contrast: 1.06,
                brightness: 0.015,
                targetTemperature: 5900,
                targetTint: 14,
                exposure: 0.03,
                shadowAmount: 0.12,
                highlightAmount: 0.92
            )

        case .sinCity:
            // Handled by applySinCityGrade(to:)
            return GradeProfile(
                rVector: CIVector(x: 1, y: 0, z: 0, w: 0),
                gVector: CIVector(x: 0, y: 1, z: 0, w: 0),
                bVector: CIVector(x: 0, y: 0, z: 1, w: 0),
                biasVector: CIVector(x: 0, y: 0, z: 0, w: 0),
                saturation: 1,
                contrast: 1,
                brightness: 0,
                targetTemperature: baseTemperature,
                targetTint: 0,
                exposure: 0,
                shadowAmount: 0,
                highlightAmount: 1
            )
        }
    }

    private static func applyProfile(_ profile: GradeProfile, to image: CIImage) -> CIImage {
        var output = image

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = output
        matrix.rVector = profile.rVector
        matrix.gVector = profile.gVector
        matrix.bVector = profile.bVector
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = profile.biasVector
        output = matrix.outputImage ?? output

        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.saturation = profile.saturation
        let flattenedContrast = 1.0 + ((profile.contrast - 1.0) * presetContrastCompression)
        controls.contrast = flattenedContrast
        controls.brightness = profile.brightness + presetBrightnessLift
        output = controls.outputImage ?? output

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = output
        temperature.neutral = CIVector(x: baseTemperature, y: 0)
        temperature.targetNeutral = CIVector(x: profile.targetTemperature, y: profile.targetTint)
        output = temperature.outputImage ?? output

        if abs(profile.exposure) > 0.001 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = profile.exposure * presetExposureCompression
            output = exposure.outputImage ?? output
        }

        let flattenedShadowAmount = max(profile.shadowAmount, minimumShadowLift)
        let flattenedHighlightAmount = max(profile.highlightAmount, minimumHighlightAmount)
        if abs(flattenedShadowAmount) > 0.001 || abs(flattenedHighlightAmount - 1.0) > 0.001 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = output
            highlightShadow.shadowAmount = flattenedShadowAmount
            highlightShadow.highlightAmount = flattenedHighlightAmount
            output = highlightShadow.outputImage ?? output
        }

        return output
    }

    private static func applySinCityGrade(to image: CIImage) -> CIImage {
        // Luma conversion + hard contrast for graphic noir base.
        let bwMatrix = CIFilter.colorMatrix()
        bwMatrix.inputImage = image
        bwMatrix.rVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0.0)
        bwMatrix.gVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0.0)
        bwMatrix.bVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0.0)
        bwMatrix.aVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
        var bw = bwMatrix.outputImage ?? image

        let controls = CIFilter.colorControls()
        controls.inputImage = bw
        controls.saturation = 0.0
        controls.contrast = 1.10
        controls.brightness = 0.0
        bw = controls.outputImage ?? bw

        let shadowHighlight = CIFilter.highlightShadowAdjust()
        shadowHighlight.inputImage = bw
        shadowHighlight.shadowAmount = 0.10
        shadowHighlight.highlightAmount = 0.88
        bw = shadowHighlight.outputImage ?? bw

        let mask = sinCityRedMask(image: image)

        let colorBoost = CIFilter.colorControls()
        colorBoost.inputImage = image
        colorBoost.saturation = 2.0
        colorBoost.contrast = 1.04
        colorBoost.brightness = 0.0
        let boostedColor = colorBoost.outputImage ?? image

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return bw }
        blend.setValue(boostedColor, forKey: kCIInputImageKey)
        blend.setValue(bw, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? bw
    }

    private static func filmFinishSettings(for preset: MoviePreset) -> FilmFinishSettings {
        switch preset {
        case .matrix:
            return FilmFinishSettings(
                grainAmount: 0.05,
                grainSize: 1.15,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.004,
                bloomIntensity: 0.02,
                bloomRadius: 4.0
            )

        case .bladeRunner2049:
            return FilmFinishSettings(
                grainAmount: 0.03,
                grainSize: 1.10,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.020,
                bloomIntensity: 0.12,
                bloomRadius: 8.0
            )

        case .sinCity:
            return FilmFinishSettings(
                grainAmount: 0.10,
                grainSize: 1.20,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.0,
                bloomIntensity: 0.0,
                bloomRadius: 0.0
            )

        case .theBatman:
            return FilmFinishSettings(
                grainAmount: 0.12,
                grainSize: 1.35,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.006,
                bloomIntensity: 0.03,
                bloomRadius: 5.0
            )

        case .strangerThings:
            return FilmFinishSettings(
                grainAmount: 0.09,
                grainSize: 1.25,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.004,
                bloomIntensity: 0.04,
                bloomRadius: 6.0
            )

        case .dune:
            return FilmFinishSettings(
                grainAmount: 0.03,
                grainSize: 1.30,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.0,
                bloomIntensity: 0.07,
                bloomRadius: 8.0
            )

        case .drive:
            return FilmFinishSettings(
                grainAmount: 0.08,
                grainSize: 1.10,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.03,
                bloomIntensity: 0.10,
                bloomRadius: 9.0
            )

        case .madMax:
            return FilmFinishSettings(
                grainAmount: 0.05,
                grainSize: 1.00,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.008,
                bloomIntensity: 0.03,
                bloomRadius: 5.0
            )

        case .revenant:
            return FilmFinishSettings(
                grainAmount: 0.025,
                grainSize: 1.20,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.0,
                bloomIntensity: 0.01,
                bloomRadius: 4.0
            )

        case .inTheMoodForLove:
            return FilmFinishSettings(
                grainAmount: 0.09,
                grainSize: 1.35,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.005,
                bloomIntensity: 0.09,
                bloomRadius: 8.0
            )

        case .seven:
            return FilmFinishSettings(
                grainAmount: 0.13,
                grainSize: 1.60,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.010,
                bloomIntensity: 0.0,
                bloomRadius: 0.0
            )

        case .vertigo:
            return FilmFinishSettings(
                grainAmount: 0.05,
                grainSize: 1.15,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.0,
                bloomIntensity: 0.06,
                bloomRadius: 7.0
            )

        case .orderOfPhoenix:
            return FilmFinishSettings(
                grainAmount: 0.07,
                grainSize: 1.15,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.006,
                bloomIntensity: 0.02,
                bloomRadius: 4.0
            )

        case .hero:
            return FilmFinishSettings(
                grainAmount: 0.03,
                grainSize: 0.95,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.0,
                bloomIntensity: 0.02,
                bloomRadius: 5.0
            )

        case .laLaLand:
            return FilmFinishSettings(
                grainAmount: 0.06,
                grainSize: 1.10,
                vignetteStrength: 0.0,
                vignetteSoftness: 0.0,
                chromaticAberration: 0.003,
                bloomIntensity: 0.06,
                bloomRadius: 7.0
            )
        }
    }

    // MARK: - Finish Helpers

    private static func applyBloom(to image: CIImage, intensity: CGFloat, radius: CGFloat) -> CIImage {
        guard intensity > 0.001, radius > 0.001 else { return image }

        let extent = image.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return image }

        let bloom = CIFilter.bloom()
        bloom.inputImage = image.clampedToExtent()
        bloom.intensity = Float(intensity)
        bloom.radius = Float(radius)

        return bloom.outputImage?.cropped(to: extent) ?? image
    }

    private static func applyVignette(to image: CIImage, strength: CGFloat, softness: CGFloat) -> CIImage {
        guard strength > 0.001 else { return image }

        let extent = image.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return image }

        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = Float(min(max(strength * 2.2, 0.0), 2.0))
        vignette.radius = Float(min(extent.width, extent.height) * (0.35 + 0.45 * softness))

        return vignette.outputImage?.cropped(to: extent) ?? image
    }

    private static func applyChromaticAberration(to image: CIImage, amount: CGFloat) -> CIImage {
        guard amount > 0.001 else { return image }

        let extent = image.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return image }

        let shift = amount * 14.0
        let clamped = image.clampedToExtent()
        let magentaSource = clamped.transformed(by: .init(translationX: shift, y: 0)).cropped(to: extent)
        let greenSource = clamped.transformed(by: .init(translationX: -shift, y: 0)).cropped(to: extent)

        let redChannel = isolateChannel(magentaSource, red: 1, green: 0, blue: 0)
        let blueChannel = isolateChannel(magentaSource, red: 0, green: 0, blue: 1)
        let greenChannel = isolateChannel(greenSource, red: 0, green: 1, blue: 0)

        let rb = additionComposite(redChannel, over: blueChannel)
        let aberrated = additionComposite(rb, over: greenChannel).cropped(to: extent)

        let mask = chromaticEdgeMask(for: image, amount: amount)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(aberrated, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private static func normalizeHighlights(in image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return image }

        var output = image

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = output
        // Keep a flatter export baseline so users can push contrast later in editing.
        highlightShadow.shadowAmount = 0.16
        highlightShadow.highlightAmount = 0.90
        output = highlightShadow.outputImage ?? output

        return output.cropped(to: extent)
    }

    private static func applyFilmGrain(to image: CIImage, amount: CGFloat, size: CGFloat, at time: CMTime?) -> CIImage {
        guard amount > 0.001 else { return image }

        let extent = image.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return image }
        guard let randomNoise = CIFilter.randomGenerator().outputImage else { return image }

        let seconds = max(0.0, CMTimeGetSeconds(time ?? .zero))
        let driftX = CGFloat(seconds * 41.0 + sin(seconds * 13.0) * 55.0)
        let driftY = CGFloat(seconds * 29.0 + cos(seconds * 11.0) * 55.0)

        let grainSize = min(max(size, 0.7), 2.4)
        var noise = randomNoise
            .transformed(by: .init(translationX: driftX, y: driftY))
            .transformed(by: .init(scaleX: 1.0 / grainSize, y: 1.0 / grainSize))
            .cropped(to: extent)

        let mono = CIFilter.colorControls()
        mono.inputImage = noise
        mono.saturation = 0
        mono.contrast = 1.35
        mono.brightness = 0
        noise = mono.outputImage ?? noise

        let blurRadius = max(0.0, (grainSize - 1.0) * 0.35)
        if blurRadius > 0.001 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = noise
            blur.radius = Float(blurRadius)
            noise = (blur.outputImage ?? noise).cropped(to: extent)
        }

        let alphaMapped = CIFilter.colorMatrix()
        alphaMapped.inputImage = noise
        alphaMapped.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        alphaMapped.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        alphaMapped.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        let mappedAmount = min(max(amount * 0.95, 0.0), 0.16)
        alphaMapped.aVector = CIVector(x: 0, y: 0, z: 0, w: mappedAmount)
        noise = alphaMapped.outputImage ?? noise

        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return image }
        blend.setValue(noise, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)

        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private static func chromaticEdgeMask(for image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent.integral
        var mask = image

        let mono = CIFilter.colorControls()
        mono.inputImage = mask
        mono.saturation = 0
        mono.contrast = 1.25
        mask = mono.outputImage ?? mask

        let edges = CIFilter.edges()
        edges.inputImage = mask
        edges.intensity = Float(2.6 + (amount * 12.0))
        mask = edges.outputImage ?? mask

        let soften = CIFilter.gaussianBlur()
        soften.inputImage = mask
        soften.radius = 0.8
        mask = (soften.outputImage ?? mask).cropped(to: extent)

        let shape = CIFilter.colorControls()
        shape.inputImage = mask
        shape.contrast = 5.0
        shape.brightness = -0.05
        mask = shape.outputImage ?? mask

        let strength = min(max(amount * 15.0, 0.0), 1.0)
        let alphaMask = CIFilter.colorMatrix()
        alphaMask.inputImage = mask
        alphaMask.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        alphaMask.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        alphaMask.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        alphaMask.aVector = CIVector(x: 0.299 * strength, y: 0.587 * strength, z: 0.114 * strength, w: 0)
        alphaMask.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return (alphaMask.outputImage ?? mask).cropped(to: extent)
    }

    private static func isolateChannel(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: red, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: green, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: blue, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? image
    }

    private static func additionComposite(_ image: CIImage, over background: CIImage) -> CIImage {
        guard let add = CIFilter(name: "CIAdditionCompositing") else { return background }
        add.setValue(image, forKey: kCIInputImageKey)
        add.setValue(background, forKey: kCIInputBackgroundImageKey)
        return add.outputImage ?? background
    }

    // MARK: - Sin City Helpers

    private static var sinCityColorCubeData: Data = {
        let size = 32
        var data = [Float32](repeating: 0, count: size * size * size * 4)

        for bi in 0..<size {
            for gi in 0..<size {
                for ri in 0..<size {
                    let r = Float(ri) / Float(size - 1)
                    let g = Float(gi) / Float(size - 1)
                    let b = Float(bi) / Float(size - 1)

                    let maxC = max(r, max(g, b))
                    let minC = min(r, min(g, b))
                    let delta = maxC - minC

                    var h: Float = 0
                    if delta > 0.0001 {
                        if maxC == r {
                            h = (g - b) / delta
                            if g < b { h += 6 }
                        } else if maxC == g {
                            h = (b - r) / delta + 2
                        } else {
                            h = (r - g) / delta + 4
                        }
                        h /= 6
                    }

                    let s = maxC > 0.0001 ? delta / maxC : 0
                    let v = maxC

                    let hueDistanceToRed = min(h, 1.0 - h)
                    let isTrueRedHue = hueDistanceToRed < 0.018
                    let isStrongColor = (s > 0.68 && v > 0.20)
                    let hasRedDominance = (r > (g * 1.45 + 0.04)) && (r > (b * 1.20 + 0.02))
                    let suppressOrangeBias = g < (r * 0.42)
                    let isRed = isTrueRedHue && isStrongColor && hasRedDominance && suppressOrangeBias

                    let mask: Float32 = isRed ? 1.0 : 0.0
                    let idx = (bi * size * size + gi * size + ri) * 4

                    data[idx + 0] = mask
                    data[idx + 1] = mask
                    data[idx + 2] = mask
                    data[idx + 3] = 1.0
                }
            }
        }

        let pointer = UnsafeMutablePointer<Float32>.allocate(capacity: data.count)
        pointer.initialize(from: data, count: data.count)
        return Data(bytesNoCopy: pointer, count: data.count * 4, deallocator: .free)
    }()

    private static func sinCityRedMask(image: CIImage) -> CIImage {
        let cubeDimension = 32
        guard let cube = CIFilter(name: "CIColorCube") else { return image }
        cube.setValue(cubeDimension, forKey: "inputCubeDimension")
        cube.setValue(sinCityColorCubeData, forKey: "inputCubeData")
        cube.setValue(image, forKey: kCIInputImageKey)
        return cube.outputImage ?? image
    }
}
