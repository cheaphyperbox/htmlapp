import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let canvasSize = 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 24
) else {
    fatalError("Could not create icon bitmap")
}

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

func roundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func roundedFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

func drawText(_ text: String, x: CGFloat, yFromTop: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) {
    let font = roundedFont(size: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    string.draw(at: NSPoint(x: x, y: CGFloat(canvasSize) - yFromTop - textSize.height))
}

func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(canvasSize) - y - height, width: width, height: height)
}

func drawChevron(centerX: CGFloat, centerYFromTop: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = 9
    path.lineCapStyle = .square
    path.lineJoinStyle = .miter
    path.move(to: NSPoint(x: centerX - 9, y: CGFloat(canvasSize) - centerYFromTop + 18))
    path.line(to: NSPoint(x: centerX + 10, y: CGFloat(canvasSize) - centerYFromTop))
    path.line(to: NSPoint(x: centerX - 9, y: CGFloat(canvasSize) - centerYFromTop - 18))
    NSColor(calibratedWhite: 0.40, alpha: 1).setStroke()
    path.stroke()
}

NSColor.black.setFill()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

// Title and add button.
drawText("HTMLApp", x: 88, yFromTop: 102, size: 98, weight: .regular)

let plusCenter = NSPoint(x: 842, y: CGFloat(canvasSize) - 176)
NSColor(calibratedWhite: 0.17, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: plusCenter.x - 88, y: plusCenter.y - 88, width: 176, height: 176)).fill()
NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: plusCenter.x - 88, y: plusCenter.y - 88, width: 176, height: 176))
ring.lineWidth = 1.5
ring.stroke()
let plus = NSBezierPath()
plus.lineWidth = 13
plus.lineCapStyle = .round
plus.move(to: NSPoint(x: plusCenter.x - 40, y: plusCenter.y))
plus.line(to: NSPoint(x: plusCenter.x + 40, y: plusCenter.y))
plus.move(to: NSPoint(x: plusCenter.x, y: plusCenter.y - 40))
plus.line(to: NSPoint(x: plusCenter.x, y: plusCenter.y + 40))
NSColor.white.setStroke()
plus.stroke()

// First app card.
roundedRect(topRect(x: 88, y: 294, width: 844, height: 214), radius: 33, color: NSColor(calibratedWhite: 0.145, alpha: 1))
roundedRect(topRect(x: 120, y: 326, width: 154, height: 154), radius: 34, color: NSColor(calibratedRed: 0.53, green: 0.25, blue: 0.26, alpha: 1))
roundedRect(topRect(x: 306, y: 337, width: 264, height: 65), radius: 20, color: .white)
roundedRect(topRect(x: 306, y: 423, width: 540, height: 43), radius: 22, color: NSColor(calibratedWhite: 0.50, alpha: 1))
drawChevron(centerX: 883, centerYFromTop: 401)

// Second app card.
roundedRect(topRect(x: 88, y: 535, width: 844, height: 214), radius: 33, color: NSColor(calibratedWhite: 0.145, alpha: 1))
roundedRect(topRect(x: 120, y: 567, width: 154, height: 154), radius: 34, color: NSColor(calibratedRed: 0.46, green: 0.63, blue: 0.75, alpha: 1))
roundedRect(topRect(x: 306, y: 578, width: 264, height: 65), radius: 20, color: .white)
roundedRect(topRect(x: 306, y: 664, width: 540, height: 43), radius: 22, color: NSColor(calibratedWhite: 0.50, alpha: 1))
drawChevron(centerX: 883, centerYFromTop: 642)

// Search field.
roundedRect(topRect(x: 88, y: 795, width: 844, height: 154), radius: 72, color: NSColor(calibratedWhite: 0.17, alpha: 1))
let border = NSBezierPath(roundedRect: topRect(x: 88, y: 795, width: 844, height: 154), xRadius: 72, yRadius: 72)
border.lineWidth = 1.5
NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
border.stroke()
drawText("Search...", x: 169, yFromTop: 817, size: 82, weight: .regular)

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
