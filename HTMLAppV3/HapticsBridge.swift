import Foundation
import UIKit

enum HTMLHapticsBridge {
    static func perform(pattern: [Int]) {
        let values = pattern.isEmpty ? [8] : Array(pattern.prefix(12))
        var delay: Double = 0
        for (index, rawValue) in values.enumerated() {
            let duration = max(0, min(rawValue, 1000))
            if index.isMultiple(of: 2), duration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let style: UIImpactFeedbackGenerator.FeedbackStyle
                    if duration >= 60 { style = .heavy }
                    else if duration >= 25 { style = .medium }
                    else { style = .light }
                    let generator = UIImpactFeedbackGenerator(style: style)
                    generator.prepare()
                    generator.impactOccurred()
                }
            }
            delay += Double(duration) / 1000.0
        }
    }
}
