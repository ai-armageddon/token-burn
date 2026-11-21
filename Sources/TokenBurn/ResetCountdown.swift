import Foundation

struct ResetCountdown {
    enum Proximity { case unknown, due, withinHour, withinSixHours, withinDay, later }

    let proximity: Proximity
    let text: String
    let compactText: String

    init(reset: Date?, now: Date) {
        guard let reset else {
            (proximity, text, compactText) = (.unknown, "—", "—")
            return
        }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else {
            (proximity, text, compactText) = (.due, "due", "due")
            return
        }
        switch seconds {
        case ...3600: proximity = .withinHour
        case ...21600: proximity = .withinSixHours
        case ...86400: proximity = .withinDay
        default: proximity = .later
        }

        let minutes = Int(ceil(seconds / 60))
        let hours = minutes / 60
        let days = hours / 24
        if seconds < 60 {
            text = "<1m"
            compactText = text
        } else if hours == 0 {
            text = "\(minutes)m"
            compactText = text
        } else if days == 0 {
            let rest = minutes % 60
            text = rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
            compactText = (seconds / 3600).formatted(.number.precision(.fractionLength(0...1))) + "h"
        } else {
            let rest = hours % 24
            text = rest == 0 ? "\(days)d" : "\(days)d \(rest)h"
            compactText = (seconds / 86400).formatted(.number.precision(.fractionLength(0...1))) + "d"
        }
    }
}
