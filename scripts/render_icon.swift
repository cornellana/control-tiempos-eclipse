#!/usr/bin/swift
/// render_icon.swift — Generates the ControlTiemposEclipse app icon (1024×1024, no alpha).
///
/// Motif: total solar eclipse diamond ring.
///   • Deep-space dark gradient background.
///   • Thin luminous corona (gold #b8985a) around the black moon disk.
///   • Single brilliant diamond flash on the upper-right limb with 4 diffraction spikes.
///   • Faint star field for depth.
///
/// Usage (from project root):
///   swift scripts/render_icon.swift
///
/// Output:
///   MyApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png  (RGB 8-bit, no alpha)
///
/// Requirements: macOS 12+, Xcode Command Line Tools.

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Canvas constants

let SIZE   = 1024
let CX     = CGFloat(SIZE) / 2     // 512
let CY     = CGFloat(SIZE) / 2     // 512
let MOON_R: CGFloat = 358          // Moon disk radius — fills ~70 % of the half-width

// sRGB colour space used throughout.
guard let CS = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("sRGB unavailable") }

// MARK: - Helpers

/// Creates an sRGB CGColor from 0-255 integer components.
func c(_ r: Int, _ g: Int, _ b: Int, a: CGFloat = 1.0) -> CGColor {
    CGColor(colorSpace: CS,
            components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}

/// Builds a CGGradient from parallel arrays of CGColor and CGFloat location.
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
}

// MARK: - Bitmap context (RGB, noneSkipLast = no alpha channel)

guard let ctx = CGContext(
    data: nil,
    width: SIZE, height: SIZE,
    bitsPerComponent: 8,
    bytesPerRow: SIZE * 4,
    space: CS,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Cannot create CGBitmapContext") }

// Flip to screen coordinates (y increases downward) so the PNG saves correctly.
ctx.translateBy(x: 0, y: CGFloat(SIZE))
ctx.scaleBy(x: 1, y: -1)

// MARK: - 1. Deep-space background

let bgGrad = gradient(
    [c(14, 8, 28), c(6, 3, 14), c(0, 0, 0)],
    [0.0,          0.55,        1.0]
)
ctx.drawRadialGradient(bgGrad,
    startCenter: CGPoint(x: CX, y: CY), startRadius: 0,
    endCenter:   CGPoint(x: CX, y: CY), endRadius: CX * 1.2,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// MARK: - 2. Outer diffuse corona halo (broad, very dim)

let haloGrad = gradient(
    [c(0,0,0, a:0), c(0,0,0, a:0), c(184,152,90, a:0.06), c(184,152,90, a:0.03), c(0,0,0, a:0)],
    [0.0,           0.50,          0.68,                   0.82,                   1.0]
)
ctx.drawRadialGradient(haloGrad,
    startCenter: CGPoint(x: CX, y: CY), startRadius: 0,
    endCenter:   CGPoint(x: CX, y: CY), endRadius: CX,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// MARK: - 3. Bright corona ring just outside the moon limb

// Normalised moon radius = MOON_R / CX ≈ 0.699
let mf = MOON_R / CX   // moon fraction of the gradient radius

let ringGrad = gradient(
    [
        c(  0,  0,  0, a:0.00),   // centre (under moon, invisible)
        c(  0,  0,  0, a:0.00),   // approaching limb
        c(245,225,160, a:0.92),   // limb edge — warm white-gold burst
        c(255,250,230, a:1.00),   // just outside limb — peak brightness
        c(220,185,110, a:0.65),   // inner corona gold
        c(184,152, 90, a:0.30),   // #b8985a mid corona
        c( 90, 72, 40, a:0.08),   // outer corona dim
        c(  0,  0,  0, a:0.00),   // fade to transparent
    ],
    [0.0,    mf-0.06, mf, mf+0.02, mf+0.06, mf+0.12, mf+0.20, 1.0]
)
ctx.drawRadialGradient(ringGrad,
    startCenter: CGPoint(x: CX, y: CY), startRadius: 0,
    endCenter:   CGPoint(x: CX, y: CY), endRadius: CX,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// MARK: - 4. Moon disk (solid black)

ctx.setFillColor(c(0, 0, 0))
ctx.fillEllipse(in: CGRect(x: CX - MOON_R, y: CY - MOON_R,
                             width: MOON_R * 2, height: MOON_R * 2))

// MARK: - 5. Diamond flash — upper-right limb

// In screen-space (y down): upper-right = +cos, -sin for angle above horizontal.
let flashAngle: CGFloat = .pi / 4    // 45° above the positive x-axis
let FX = CX + cos(flashAngle) * MOON_R
let FY = CY - sin(flashAngle) * MOON_R    // minus → upward in screen coords

// Outer glow (warm gold → transparent)
let flashGlow = gradient(
    [c(255,255,255, a:1.00), c(255,245,190, a:0.85), c(184,152,90, a:0.40), c(0,0,0, a:0)],
    [0.0,                    0.14,                   0.42,                   1.0]
)
ctx.drawRadialGradient(flashGlow,
    startCenter: CGPoint(x: FX, y: FY), startRadius: 0,
    endCenter:   CGPoint(x: FX, y: FY), endRadius: 90,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// MARK: - 6. Diffraction spikes (4-armed cross + diagonal cross = 8 arms)

// Each spike is drawn as a thin rectangle clipped to a rotated context, filled with
// a linear gradient (bright centre, transparent ends). Ref: classic lens diffraction pattern.
let spikeAngles:   [CGFloat] = [0, .pi/2, .pi/4, 3 * .pi/4]
let spikeLengths:  [CGFloat] = [210, 175, 195, 185]
let spikeHalfW:   CGFloat   = 2.0

let spikeGrad = gradient(
    [c(0,0,0, a:0), c(255,250,220, a:0.55), c(255,255,255, a:0.88),
     c(255,250,220, a:0.55), c(0,0,0, a:0)],
    [0.0,           0.30,                   0.50,
     0.70,                   1.0]
)

for (spikeAngle, len) in zip(spikeAngles, spikeLengths) {
    ctx.saveGState()
    ctx.translateBy(x: FX, y: FY)
    ctx.rotate(by: spikeAngle)

    let clipRect = CGRect(x: -len, y: -spikeHalfW, width: len * 2, height: spikeHalfW * 2)
    ctx.addRect(clipRect)
    ctx.clip()

    ctx.drawLinearGradient(spikeGrad,
        start: CGPoint(x: -len, y: 0),
        end:   CGPoint(x:  len, y: 0),
        options: [])

    ctx.restoreGState()
}

// MARK: - 7. Diamond core (brilliant white dot on top of everything)

let coreGrad = gradient(
    [c(255,255,255, a:1.0), c(255,255,250, a:0.85), c(255,255,255, a:0)],
    [0.0,                   0.35,                   1.0]
)
ctx.drawRadialGradient(coreGrad,
    startCenter: CGPoint(x: FX, y: FY), startRadius: 0,
    endCenter:   CGPoint(x: FX, y: FY), endRadius: 24,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// MARK: - 8. Faint star field (subtle white dots)

// (normalised x, normalised y, pixel radius)
let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (0.07, 0.10, 1.3), (0.18, 0.05, 0.9), (0.87, 0.08, 1.1),
    (0.94, 0.28, 0.8), (0.04, 0.75, 1.0), (0.11, 0.90, 0.8),
    (0.88, 0.85, 1.2), (0.78, 0.96, 0.9), (0.52, 0.03, 1.0),
    (0.97, 0.52, 0.8), (0.03, 0.48, 1.1), (0.30, 0.97, 0.9),
    (0.72, 0.04, 0.7), (0.95, 0.72, 1.0),
]
ctx.setFillColor(c(255, 255, 255, a: 0.55))
for (nx, ny, r) in stars {
    let sx = nx * CGFloat(SIZE), sy = ny * CGFloat(SIZE)
    ctx.fillEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
}

// MARK: - 9. Export as PNG (no alpha, sRGB)

guard let image = ctx.makeImage() else { fatalError("Cannot create CGImage from context") }

// Resolve output path relative to the directory where the script is invoked.
// Run from the project root: swift scripts/render_icon.swift
let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outURL = projectRoot
    .appendingPathComponent("MyApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("Cannot create image destination at \(outURL.path)") }

// PNG metadata: no dpi embedding (system uses asset catalog scale).
let props: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 1.0]
CGImageDestinationAddImage(dest, image, props as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fatalError("Cannot write PNG") }

print("✓ AppIcon 1024×1024 written to:")
print("  \(outURL.path)")
