import SwiftUI

// Select the property wrapper when the command-line SDK also exposes a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    init(rgb: Int) {
        self.init(red: Double(rgb >> 16 & 255)/255, green: Double(rgb >> 8 & 255)/255, blue: Double(rgb & 255)/255)
    }
    static let surface = Color(rgb: 0x101011)
    static let ink = Color(rgb: 0xF6F6F5)
    static let quiet = Color(rgb: 0xA1A1A5)
    static let healthyRing = Color(rgb: 0x22D86A)
    static let lowRing = Color(rgb: 0xFF393E)
    static let signal = Color(rgb: 0xFF641E)
}
extension Provider {
    var tint: Color { .ink }
}

struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat

    private static let images = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider -> (Provider, NSImage)? in
        guard let url = Bundle.module.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "ProviderLogos"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (provider, image)
    })

    var body: some View {
        if let image = Self.images[provider] {
            Image(nsImage: image).resizable().renderingMode(.original)
                .scaledToFit().frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// Three forward-leaning cuts form the app and menu-bar mark.
struct BurnMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<3 {
            let left = CGFloat(i) * 0.29
            let top = CGFloat(2 - i) * 0.16
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(left, 1))
            path.addLine(to: point(left + 0.18 * (1 - top), top))
            path.addLine(to: point(left + 0.20 + 0.18 * (1 - top), top))
            path.addLine(to: point(left + 0.20, 1))
            path.closeSubpath()
        }
        return path
    }
}

struct GlyphButton: View {
    let symbol: String
    let help: String
    var lit = false
    var action: () -> Void
    @ViewState private var over = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(lit ? Color.signal : over ? .ink : .quiet)
                .frame(width: 27, height: 26)
                .background(over ? .white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help).onHover { over = $0 }
    }
}

private extension ResetCountdown {
    var color: Color {
        switch proximity {
        case .unknown, .due: return .quiet
        case .withinHour: return .healthyRing
        case .withinSixHours: return Color(rgb: 0xFFBC26)
        case .withinDay: return Color(rgb: 0x44ADFF)
        case .later: return Color(rgb: 0xB680FF)
        }
    }
}

private struct AllowanceArc: View {
    let meter: Meter?
    let lineWidth: CGFloat
    let stale: Bool

    var body: some View {
        let color: Color = meter.map { $0.isLow ? Color.lowRing : .healthyRing } ?? .quiet
        ZStack {
            Circle().stroke(color.opacity(meter?.isLow == true ? 0.48 : 0.16), lineWidth: lineWidth)
            if let meter, meter.remaining > 0 {
                Circle().trim(from: 0, to: meter.remaining / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90)).opacity(stale ? 0.55 : 1)
            }
        }
    }
}

struct RingTile: View {
    let account: Account
    let width: CGFloat
    let compact: Bool
    let subtitle: String
    let selected: Bool
    let drop: (UUID) -> Bool
    let action: () -> Void
    @ViewState private var over = false
    var body: some View {
        let meter = account.meter
        let diameter: CGFloat = compact ? 38 : 52
        let bank = account.reading?.bankedResets?.available(at: Date())
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: compact ? 2 : 4) {
                    if let amount = account.badgeAmount {
                        let color: Color = amount >= 500 ? Color(rgb: 0xB680FF) : amount >= 200 ? .signal : amount >= 100 ? Color(rgb: 0xFFBC26) : Color(rgb: 0x44ADFF)
                        Text(NSDecimalNumber(decimal: amount).stringValue)
                            .fontWeight(.bold).foregroundStyle(color).padding(.horizontal, compact ? 2 : 3).padding(.vertical, 1)
                            .overlay { Capsule().strokeBorder(color.opacity(0.65), lineWidth: 0.7) }
                    }
                    TimelineView(.everyMinute) { timeline in
                        let countdown = ResetCountdown(reset: meter?.reset, now: timeline.date)
                        HStack(spacing: 1) {
                            Image(systemName: "clock").imageScale(.small)
                            Text(compact ? countdown.compactText : countdown.text)
                        }.foregroundStyle(countdown.color)
                    }
                }.font(.system(size: compact ? 7.5 : 9, weight: .semibold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: compact ? 12 : 14).padding(.bottom, compact ? 3 : 5)
                ZStack {
                    AllowanceArc(meter: meter, lineWidth: compact ? 3 : 4, stale: account.stale)
                    if let inner = account.innerMeter {
                        AllowanceArc(meter: inner, lineWidth: compact ? 2.5 : 3, stale: account.stale || (inner.reset ?? .distantFuture) <= Date())
                            .padding(compact ? 5 : 7)
                    }
                    ProviderLogo(provider: account.provider, size: compact ? 15 : 21)
                }.frame(width: diameter, height: diameter)
                .overlay(alignment: .topTrailing) {
                    if let bank, bank.count > 0 {
                        Circle().fill(Color.signal).frame(width: 9, height: 9)
                            .overlay { Circle().stroke(Color.surface, lineWidth: 2) }
                            .offset(x: 2, y: -2)
                    }
                }.padding(.bottom, compact ? 5 : 7)
                if !compact {
                    Text(account.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.83)
                        .foregroundStyle(Color.ink)
                }
                Text(meter.map { "\($0.remainingText) left" } ?? "—")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.82)
                if !compact {
                    Text(subtitle).font(.system(size: 9, weight: .medium, design: .monospaced)).lineLimit(1)
                        .foregroundStyle((account.issue != nil || account.stale) ? .orange : Color.quiet)
                        .padding(.top, 1)
                    VStack(spacing: 1) {
                        Text(account.tierName ?? "Tier unknown").fontWeight(.medium)
                        if let price = account.priceText { Text(price) }
                    }
                    .font(.system(size: 10)).foregroundStyle(Color.quiet)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(height: 26, alignment: .top).padding(.top, 3)
                }
            }.padding(.horizontal, 2).frame(width: width, height: compact ? 79 : 157)
                .background(selected || over ? Color.white.opacity(selected ? 0.10 : 0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .overlay {
            AccountDragArea(source: account.id, help: tooltip, click: action, drop: drop)
                .accessibilityHidden(true)
        }
        .onHover { over = $0 }
        .accessibilityLabel("\(account.name), \(account.meter?.remainingText ?? "unknown") left, \(subtitle)")
        .accessibilityHint(tooltip)
        .help(tooltip)
    }
    private var tooltip: String {
        var parts = [account.name, account.tierName ?? "Tier unknown", account.priceDetail]
        if let reading = account.reading {
            if let identity = reading.identity { parts.append(identity) }
            parts += reading.meters.map { meter in
                let ring = meter.id == account.meter?.id ? "Outer ring · " : meter.id == account.innerMeter?.id ? "Inner ring · " : ""
                return ring + "\(meter.title) · \(meter.remainingText) left" + (meter.reset.map { " · resets \($0.formatted())" } ?? "")
            }
            if let bank = reading.bankedResets?.available(at: Date()), bank.count > 0 {
                parts.append("\(bank.count) banked " + (bank.count == 1 ? "reset" : "resets"))
                parts += bank.lines
            }
            parts.append((reading.estimated ? "Local estimate · " : "") + "Updated " + reading.updated.formatted())
        }
        if let issue = account.issue { parts.append(issue) }
        parts.append("Drag to change the account order.")
        return parts.joined(separator: "\n")
    }
}
