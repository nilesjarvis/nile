#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: render-app-icon.swift <source.svg> <output.png>\n".utf8)
    )
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let pixelSize = 1_024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

guard sourceURL.pathExtension.lowercased() == "svg",
      let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Could not load SVG source at \(sourceURL.path)")
}

guard let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create opaque icon drawing context")
}

context.setFillColor(
    CGColor(
        colorSpace: colorSpace,
        components: [18 / 255, 59 / 255, 93 / 255, 1]
    )!
)
context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
sourceImage.draw(
    in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
    from: CGRect(origin: .zero, size: sourceImage.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let image = context.makeImage() else {
    fatalError("Could not render app icon")
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write app icon")
}
