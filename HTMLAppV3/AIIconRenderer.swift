import Foundation
import UIKit
import CoreGraphics

enum AIIconRenderer {
    private enum Paint {
        case solid(UIColor)
        case linear(UIColor, UIColor)
        case radial(UIColor, UIColor)
    }

    static func render(script: String) async -> Data? {
        let code = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        return await MainActor.run {
            renderLocally(code)
        }
    }

    @MainActor
    private static func renderLocally(_ script: String) -> Data? {
        let lines = script
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var width: CGFloat = 1024
        var height: CGFloat = 1024
        var sawSize = false

        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 3, parts[0].uppercased() == "SIZE",
                  let w = Double(parts[1]), let h = Double(parts[2]),
                  w >= 64, h >= 64, w <= 4096, h <= 4096 else { continue }
            width = CGFloat(w)
            height = CGFloat(h)
            sawSize = true
            break
        }
        guard sawSize else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        var drewSomething = false
        var drewForeground = false
        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)

            var pendingPaint: Paint?

            for line in lines {
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard let command = parts.first?.uppercased() else { continue }

                switch command {
                case "SIZE":
                    continue

                case "FILL_LINEAR":
                    let colors = parts.dropFirst().compactMap(cssColor)
                    if colors.count >= 2 {
                        pendingPaint = .linear(colors[0], colors[1])
                    } else if let first = colors.first {
                        pendingPaint = .solid(first)
                    }

                case "FILL_RADIAL":
                    let colors = parts.dropFirst().compactMap(cssColor)
                    if colors.count >= 2 {
                        pendingPaint = .radial(colors[0], colors[1])
                    } else if let first = colors.first {
                        pendingPaint = .solid(first)
                    }

                case "FILL_TEXTURE":
                    // The legacy remote renderer treated texture as an optional fill modifier.
                    // Keep scripts renderable locally by using any supplied colors as a subtle gradient.
                    let colors = parts.dropFirst().compactMap(cssColor)
                    if colors.count >= 2 {
                        pendingPaint = .linear(colors[0], colors[1])
                    } else if let first = colors.first {
                        pendingPaint = .solid(first)
                    } else {
                        pendingPaint = nil
                    }

                case "BG":
                    guard parts.count >= 2, let color = cssColor(parts[1]) else { continue }
                    color.setFill()
                    cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    drewSomething = true
                    pendingPaint = nil

                case "RECT":
                    guard parts.count >= 6,
                          let x = number(parts[1]), let y = number(parts[2]),
                          let w = number(parts[3]), let h = number(parts[4]),
                          let color = cssColor(parts[5]),
                          w >= 0, h >= 0 else { continue }
                    let path = UIBezierPath(rect: CGRect(x: x, y: y, width: w, height: h))
                    fill(path: path, paint: pendingPaint ?? .solid(color), context: cg)
                    pendingPaint = nil
                    drewSomething = true
                    drewForeground = true

                case "CIRCLE":
                    guard parts.count >= 5,
                          let cx = number(parts[1]), let cy = number(parts[2]),
                          let radius = number(parts[3]), radius >= 0,
                          let color = cssColor(parts[4]) else { continue }
                    let path = UIBezierPath(ovalIn: CGRect(
                        x: cx - radius,
                        y: cy - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    fill(path: path, paint: pendingPaint ?? .solid(color), context: cg)
                    pendingPaint = nil
                    drewSomething = true
                    drewForeground = true

                case "TRIANGLE":
                    guard parts.count >= 8,
                          let x1 = number(parts[1]), let y1 = number(parts[2]),
                          let x2 = number(parts[3]), let y2 = number(parts[4]),
                          let x3 = number(parts[5]), let y3 = number(parts[6]),
                          let color = cssColor(parts[7]) else { continue }
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x1, y: y1))
                    path.addLine(to: CGPoint(x: x2, y: y2))
                    path.addLine(to: CGPoint(x: x3, y: y3))
                    path.close()
                    fill(path: path, paint: pendingPaint ?? .solid(color), context: cg)
                    pendingPaint = nil
                    drewSomething = true
                    drewForeground = true

                case "LINE":
                    guard parts.count >= 7,
                          let x1 = number(parts[1]), let y1 = number(parts[2]),
                          let x2 = number(parts[3]), let y2 = number(parts[4]),
                          let thickness = number(parts[5]), thickness > 0,
                          let color = cssColor(parts[6]) else { continue }
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x1, y: y1))
                    path.addLine(to: CGPoint(x: x2, y: y2))
                    path.lineWidth = thickness
                    path.lineCapStyle = .round
                    stroke(path: path, paint: pendingPaint ?? .solid(color), context: cg)
                    pendingPaint = nil
                    drewSomething = true
                    drewForeground = true

                default:
                    continue
                }
            }
        }

        // The old renderer accepted BG-only scripts and shapes fully outside
        // the canvas, producing valid PNG data but blank-looking Home Screen icons.
        guard drewSomething, drewForeground, isVisibleArtwork(image) else { return nil }
        return image.pngData()
    }

    @MainActor
    private static func isVisibleArtwork(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let side = 36
        let rowBytes = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let canInspect = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ptr = raw.baseAddress,
                  let context = CGContext(data: ptr, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: rowBytes,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard canInspect else { return false }
        let background = Array(pixels[0..<4])
        var changedOpaquePixels = 0
        var nonTransparentPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha >= 200 { nonTransparentPixels += 1 }
            let difference = abs(Int(pixels[index]) - Int(background[0])) +
                             abs(Int(pixels[index + 1]) - Int(background[1])) +
                             abs(Int(pixels[index + 2]) - Int(background[2]))
            if alpha > 160 && difference >= 52 { changedOpaquePixels += 1 }
        }
        // At least a small visible figure and a mostly opaque icon canvas.
        return nonTransparentPixels >= side * side * 3 / 4 &&
               changedOpaquePixels >= side * side / 90
    }

    @MainActor
    private static func fill(path: UIBezierPath, paint: Paint, context: CGContext) {
        switch paint {
        case .solid(let color):
            color.setFill()
            path.fill()
        case .linear(let start, let end):
            context.saveGState()
            path.addClip()
            drawLinear(start: start, end: end, bounds: path.bounds, context: context)
            context.restoreGState()
        case .radial(let inner, let outer):
            context.saveGState()
            path.addClip()
            drawRadial(inner: inner, outer: outer, bounds: path.bounds, context: context)
            context.restoreGState()
        }
    }

    @MainActor
    private static func stroke(path: UIBezierPath, paint: Paint, context: CGContext) {
        switch paint {
        case .solid(let color):
            color.setStroke()
            path.stroke()
        case .linear(let start, let end):
            context.saveGState()
            context.addPath(path.cgPath)
            context.setLineWidth(path.lineWidth)
            context.setLineCap(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            drawLinear(start: start, end: end, bounds: path.bounds.insetBy(dx: -path.lineWidth, dy: -path.lineWidth), context: context)
            context.restoreGState()
        case .radial(let inner, let outer):
            context.saveGState()
            context.addPath(path.cgPath)
            context.setLineWidth(path.lineWidth)
            context.setLineCap(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            drawRadial(inner: inner, outer: outer, bounds: path.bounds.insetBy(dx: -path.lineWidth, dy: -path.lineWidth), context: context)
            context.restoreGState()
        }
    }

    @MainActor
    private static func drawLinear(start: UIColor, end: UIColor, bounds: CGRect, context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [start.cgColor, end.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.minY),
            end: CGPoint(x: bounds.maxX, y: bounds.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    @MainActor
    private static func drawRadial(inner: UIColor, outer: UIColor, bounds: CGRect, context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [inner.cgColor, outer.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(bounds.width, bounds.height) * 0.55
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }

    private static func number(_ value: String) -> CGFloat? {
        guard let value = Double(value), value.isFinite else { return nil }
        return CGFloat(value)
    }

    private static func cssColor(_ raw: String) -> UIColor? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let named: [String: String] = [
            "black": "#000000", "white": "#ffffff", "red": "#ff0000",
            "green": "#008000", "blue": "#0000ff", "gray": "#808080",
            "grey": "#808080", "orange": "#ff9500", "yellow": "#ffcc00",
            "purple": "#af52de", "pink": "#ff2d55", "teal": "#30b0c7",
            "indigo": "#5856d6", "brown": "#a2845e", "clear": "#00000000"
        ]
        let normalized = named[value] ?? value

        if normalized.hasPrefix("#") {
            let hex = String(normalized.dropFirst())
            let expanded: String
            switch hex.count {
            case 3:
                expanded = hex.map { "\($0)\($0)" }.joined() + "ff"
            case 4:
                expanded = hex.map { "\($0)\($0)" }.joined()
            case 6:
                expanded = hex + "ff"
            case 8:
                expanded = hex
            default:
                return nil
            }
            guard let rgba = UInt64(expanded, radix: 16) else { return nil }
            return UIColor(
                red: CGFloat((rgba >> 24) & 0xff) / 255,
                green: CGFloat((rgba >> 16) & 0xff) / 255,
                blue: CGFloat((rgba >> 8) & 0xff) / 255,
                alpha: CGFloat(rgba & 0xff) / 255
            )
        }

        if normalized.hasPrefix("rgb(") || normalized.hasPrefix("rgba(") {
            guard let open = normalized.firstIndex(of: "("),
                  let close = normalized.lastIndex(of: ")"),
                  open < close else { return nil }
            let values = normalized[normalized.index(after: open)..<close]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.count == 3 || values.count == 4,
                  let r = Double(values[0]), let g = Double(values[1]), let b = Double(values[2]) else { return nil }
            let a = values.count == 4 ? (Double(values[3]) ?? 1) : 1
            return UIColor(
                red: CGFloat(max(0, min(255, r)) / 255),
                green: CGFloat(max(0, min(255, g)) / 255),
                blue: CGFloat(max(0, min(255, b)) / 255),
                alpha: CGFloat(max(0, min(1, a)))
            )
        }

        return nil
    }
}
