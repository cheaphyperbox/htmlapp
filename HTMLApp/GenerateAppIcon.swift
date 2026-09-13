import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let width = 1024
let height = 1024
let bytesPerRow = width * 4
let byteCount = bytesPerRow * height

let pixels = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
defer { pixels.deallocate() }
pixels.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

guard let context = CGContext(
    data: pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create RGB icon context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

func gray(_ value: CGFloat) -> CGColor {
    CGColor(red: value, green: value, blue: value, alpha: 1)
}

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: 1)
}

func rectFromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}

func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(color)
    context.fillPath()
}

func strokeRounded(_ rect: CGRect, radius: CGFloat, color: CGColor, width: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokePath()
}

func drawText(_ text: String, x: CGFloat, yFromTop: CGFloat, size: CGFloat, color: CGColor = gray(1)) {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: CGFloat(height) - yFromTop - ascent)
    CTLineDraw(line, context)
}

func drawChevron(centerX: CGFloat, centerYFromTop: CGFloat) {
    let centerY = CGFloat(height) - centerYFromTop
    context.beginPath()
    context.move(to: CGPoint(x: centerX - 10, y: centerY + 19))
    context.addLine(to: CGPoint(x: centerX + 10, y: centerY))
    context.addLine(to: CGPoint(x: centerX - 10, y: centerY - 19))
    context.setStrokeColor(gray(0.40))
    context.setLineWidth(9)
    context.setLineJoin(.miter)
    context.strokePath()
}

// Opaque black background. App icons must not contain transparency.
context.setFillColor(gray(0))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// Header.
drawText("HTMLApp", x: 88, yFromTop: 102, size: 98)

let plusCenter = CGPoint(x: 842, y: CGFloat(height) - 176)
let plusRect = CGRect(x: plusCenter.x - 88, y: plusCenter.y - 88, width: 176, height: 176)
context.setFillColor(gray(0.17))
context.fillEllipse(in: plusRect)
context.setStrokeColor(gray(0.45))
context.setLineWidth(1.5)
context.strokeEllipse(in: plusRect)
context.setStrokeColor(gray(1))
context.setLineWidth(13)
context.setLineCap(.round)
context.beginPath()
context.move(to: CGPoint(x: plusCenter.x - 40, y: plusCenter.y))
context.addLine(to: CGPoint(x: plusCenter.x + 40, y: plusCenter.y))
context.move(to: CGPoint(x: plusCenter.x, y: plusCenter.y - 40))
context.addLine(to: CGPoint(x: plusCenter.x, y: plusCenter.y + 40))
context.strokePath()

// First saved HTML app.
fillRounded(rectFromTop(88, 294, 844, 214), radius: 33, color: gray(0.145))
fillRounded(rectFromTop(120, 326, 154, 154), radius: 34, color: rgb(0.53, 0.25, 0.26))
fillRounded(rectFromTop(306, 337, 264, 65), radius: 20, color: gray(1))
fillRounded(rectFromTop(306, 423, 540, 43), radius: 22, color: gray(0.50))
drawChevron(centerX: 883, centerYFromTop: 401)

// Second saved HTML app.
fillRounded(rectFromTop(88, 535, 844, 214), radius: 33, color: gray(0.145))
fillRounded(rectFromTop(120, 567, 154, 154), radius: 34, color: rgb(0.46, 0.63, 0.75))
fillRounded(rectFromTop(306, 578, 264, 65), radius: 20, color: gray(1))
fillRounded(rectFromTop(306, 664, 540, 43), radius: 22, color: gray(0.50))
drawChevron(centerX: 883, centerYFromTop: 642)

// Search field.
let searchRect = rectFromTop(88, 795, 844, 154)
fillRounded(searchRect, radius: 72, color: gray(0.17))
strokeRounded(searchRect, radius: 72, color: gray(0.82), width: 1.5)
drawText("Search...", x: 169, yFromTop: 817, size: 82)

guard let image = context.makeImage() else {
    fatalError("Could not create icon image")
}

let destinationURL = URL(fileURLWithPath: output) as CFURL
guard let destination = CGImageDestinationCreateWithURL(destinationURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write icon PNG")
}
