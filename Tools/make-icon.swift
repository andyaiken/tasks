// Draws the app icon — the "rhythm ring" — into App/Assets.xcassets/AppIcon.appiconset.
// Run from the repository root:  swift Tools/make-icon.swift
//
// A ring of five arcs in the urgency band colours (SPEC §5), going round clockwise
// from "not yet" at the top to "overdue", on navy, with a white dot at the centre.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let background: UInt32 = 0x1E2A44      // navy
let darkBackground: UInt32 = 0x0B1220  // near-black, for the iPhone's dark-mode icon
let bands: [UInt32] = [0x9AA0A6, 0x0A84FF, 0xE6B300, 0xFF9500, 0xFF3B30] // not yet → overdue

// Proportions of a 1024-point artboard.
let ringRadius: CGFloat = 313
let ringWidth: CGFloat = 108
let dotRadius: CGFloat = 60
let arcDegrees: CGFloat = 65 // of each 72° slot; the rest is the gap between arcs

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Draws the icon filling `rect`, with the given background and corner radius.
func drawIcon(in context: CGContext, rect: CGRect, background: UInt32, cornerRadius: CGFloat) {
    let scale = rect.width / 1024
    context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.setFillColor(color(background))
    context.fillPath()

    let centre = CGPoint(x: rect.midX, y: rect.midY)
    context.setLineWidth(ringWidth * scale)
    context.setLineCap(.butt)
    for (index, band) in bands.enumerated() {
        // Clockwise from 12 o'clock. The bitmap's y axis points up, so clockwise is decreasing angle.
        let start = CGFloat.pi / 2 - CGFloat(index) * 2 * .pi / CGFloat(bands.count)
        let end = start - arcDegrees * .pi / 180
        context.addArc(center: centre, radius: ringRadius * scale, startAngle: start, endAngle: end, clockwise: true)
        context.setStrokeColor(color(band))
        context.strokePath()
    }

    let dot = dotRadius * scale
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: 2 * dot, height: 2 * dot))
}

/// Renders a `pixels`-square PNG. iPhone icons must have no alpha channel; Mac icons need one.
func writePNG(_ pixels: Int, opaque: Bool, to url: URL, draw: (CGContext, CGFloat) -> Void) {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue
    ) else { fatalError("Couldn't create a \(pixels)px context") }
    draw(context, CGFloat(pixels))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Couldn't write \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.lastPathComponent)") }
    print("wrote \(url.lastPathComponent)")
}

let folder = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// iPhone: full-bleed squares; the system rounds the corners.
for (name, colour) in [("ios-1024.png", background), ("ios-1024-dark.png", darkBackground)] {
    writePNG(1024, opaque: true, to: folder.appending(path: name)) { context, size in
        drawIcon(in: context, rect: CGRect(x: 0, y: 0, width: size, height: size), background: colour, cornerRadius: 0)
    }
}

// Mac: the standard grid — an 824-point rounded square centred on a 1024 canvas.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "mac-\(points).png" : "mac-\(points)@2x.png"
        writePNG(pixels, opaque: false, to: folder.appending(path: name)) { context, size in
            let side = size * 824 / 1024
            let inset = (size - side) / 2
            drawIcon(
                in: context,
                rect: CGRect(x: inset, y: inset, width: side, height: side),
                background: background,
                cornerRadius: side * 0.225
            )
        }
    }
}
