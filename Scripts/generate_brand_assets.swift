import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct BrandAssetError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func loadImage(at path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw BrandAssetError(message: "Unable to read image: \(path)")
    }
    return image
}

func alphaBounds(of image: CGImage, threshold: UInt8 = 8) throws -> CGRect {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    let madeContext = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let context = CGContext(
            data: rawBuffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    guard madeContext else {
        throw BrandAssetError(message: "Unable to inspect image alpha channel")
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > threshold {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        throw BrandAssetError(message: "Image has no visible pixels")
    }

    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
}

func crop(_ image: CGImage, to bounds: CGRect, padding: CGFloat = 0) throws -> CGImage {
    let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let paddedBounds = bounds
        .insetBy(dx: -padding, dy: -padding)
        .intersection(imageRect)
        .integral

    guard let cropped = image.cropping(to: paddedBounds) else {
        throw BrandAssetError(message: "Unable to crop image")
    }
    return cropped
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(
        url,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw BrandAssetError(message: "Unable to create PNG: \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw BrandAssetError(message: "Unable to write PNG: \(path)")
    }
}

func makeApplicationIcon(from source: CGImage) throws -> CGImage {
    let canvasSize = 1_024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw BrandAssetError(message: "Unable to create app icon canvas")
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

    let cardRect = CGRect(x: 92, y: 96, width: 840, height: 840)
    let cardPath = CGPath(
        roundedRect: cardRect,
        cornerWidth: 188,
        cornerHeight: 188,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -13),
        blur: 28,
        color: CGColor(gray: 0.08, alpha: 0.14)
    )
    context.addPath(cardPath)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 0.94, green: 0.965, blue: 1, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!

    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.midX, y: cardRect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(cardPath)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.88))
    context.setLineWidth(3)
    context.strokePath()

    let visibleMark = try crop(source, to: alphaBounds(of: source), padding: 10)
    let targetWidth: CGFloat = 694
    let targetHeight = targetWidth * CGFloat(visibleMark.height) / CGFloat(visibleMark.width)
    let targetRect = CGRect(
        x: (CGFloat(canvasSize) - targetWidth) / 2,
        y: (CGFloat(canvasSize) - targetHeight) / 2 + 20,
        width: targetWidth,
        height: targetHeight
    )
    context.draw(visibleMark, in: targetRect)

    guard let icon = context.makeImage() else {
        throw BrandAssetError(message: "Unable to finish app icon")
    }
    return icon
}

guard CommandLine.arguments.count == 5 else {
    FileHandle.standardError.write(
        Data("Usage: generate_brand_assets.swift <square-source> <wordmark-source> <app-icon-output> <wordmark-output>\n".utf8)
    )
    exit(2)
}

do {
    let squareLogo = try loadImage(at: CommandLine.arguments[1])
    let wordmark = try loadImage(at: CommandLine.arguments[2])
    let appIcon = try makeApplicationIcon(from: squareLogo)
    let croppedWordmark = try crop(
        wordmark,
        to: alphaBounds(of: wordmark),
        padding: 12
    )

    try writePNG(appIcon, to: CommandLine.arguments[3])
    try writePNG(croppedWordmark, to: CommandLine.arguments[4])
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
