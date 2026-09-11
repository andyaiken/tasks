// Places a Mac window capture on a plain background at 2880 × 1800, the size
// App Store Connect accepts for Mac screenshots.
//
//   swift Tools/compose-mac-screenshot.swift <window.png> <output.png>
//
// Take the window capture with ⌘⇧4, then Space, then click the window. The capture's
// transparent margin and shadow are kept; the window is scaled to fit and centred.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift Tools/compose-mac-screenshot.swift <window.png> <output.png>")
    exit(1)
}

let canvasWidth = 2880
let canvasHeight = 1800
let background = CGColor(srgbRed: 0xE9 / 255, green: 0xEC / 255, blue: 0xF2 / 255, alpha: 1) // soft grey-blue
let maxHeightShare: CGFloat = 0.88 // of the canvas, leaving a margin top and bottom

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let window = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    print("Couldn't read \(arguments[1])")
    exit(1)
}

// Opaque output: App Store Connect doesn't want transparency in screenshots.
guard let context = CGContext(
    data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    print("Couldn't create the canvas")
    exit(1)
}
context.setFillColor(background)
context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

let scale = min(
    CGFloat(canvasHeight) * maxHeightShare / CGFloat(window.height),
    CGFloat(canvasWidth) * 0.9 / CGFloat(window.width)
)
let width = CGFloat(window.width) * scale
let height = CGFloat(window.height) * scale
context.interpolationQuality = .high
context.draw(window, in: CGRect(
    x: (CGFloat(canvasWidth) - width) / 2,
    y: (CGFloat(canvasHeight) - height) / 2,
    width: width,
    height: height
))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    print("Couldn't write \(arguments[2])")
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    print("Couldn't write \(arguments[2])")
    exit(1)
}
print("wrote \(arguments[2]) (\(canvasWidth) × \(canvasHeight), window scaled \(String(format: "%.0f", scale * 100))%)")
