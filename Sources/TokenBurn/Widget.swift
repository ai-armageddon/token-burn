import SwiftUI
import AppKit
private enum PanelPage: Equatable {
    case deck, detail(UUID), edit(UUID), add
}

struct Widget: View {
    @ObservedObject var store: Store
    let resize: (CGSize) -> Void
    let minimize: () -> Void
    @AppStorage("TokenBurnCompactMode") private var prefersCompact = false
    private var compact: Bool { prefersCompact && page == .deck }
    private var size: CGSize { CGSize(width: compact ? 298 : 428, height: height) }
    @ViewState private var page: PanelPage = .deck
    @ViewState private var group = 0
    private var groupCount: Int { max(1, (store.visible.count + 4) / 5) }
    private var height: CGFloat {
        switch page {
        case .deck: return compact ? (groupCount > 1 ? 140 : 120) : 241
        case .detail: return 505
        case .edit, .add: return 535
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                HStack(spacing: 5) {
                    Canvas { context, _ in
                        for x in [0, 4] {
                            for y in [0, 4, 8] {
                                let dot = CGRect(x: x, y: y, width: 2, height: 2)
                                context.fill(Path(ellipseIn: dot), with: .color(.quiet))
                            }
                        }
                    }.frame(width: 7, height: 10).accessibilityHidden(true)
                    Image(nsImage: TokenBurnMark.image).resizable().renderingMode(.original)
                        .frame(width: compact ? 16 : 22, height: compact ? 16 : 22)
                        .accessibilityHidden(true)
                    if !compact { Text("TOKEN BURN").font(.system(size: 14, weight: .black)).tracking(-0.5) }
                    if !compact { Divider().frame(height: 12).padding(.horizontal, 2) }
                    Text("Deck").font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .foregroundStyle(Color.quiet)
                    Spacer(minLength: 0)
                }.frame(maxHeight: .infinity).overlay { WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity) }
                GlyphButton(symbol: "minus", help: "Minimize Token Burn", action: minimize)
                GlyphButton(symbol: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                            help: compact ? "Expand widget" : "Make widget compact") {
                    prefersCompact = !compact
                    page = .deck
                }
                GlyphButton(symbol: store.state.pinned ? "pin.fill" : "pin", help: store.state.pinned ? "Unpin window" : "Keep above other windows", lit: store.state.pinned) {
                    store.setPinned(!store.state.pinned)
                }
                GlyphButton(symbol: "arrow.clockwise", help: "Refresh all accounts") { store.refresh() }
                    .disabled(!store.refreshing.isEmpty)
                GlyphButton(symbol: "plus", help: "Add or restore an account", lit: page == .add) {
                    page = page == .add ? .deck : .add
                }
            }.padding(.horizontal, compact ? 9 : 15).frame(height: compact ? 30 : 44)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 6) {
                let accounts = Array(store.visible.dropFirst(min(group, groupCount - 1) * 5).prefix(5))
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    let duplicates = store.visible.filter { $0.provider == account.provider }.count > 1
                    RingTile(account: account, width: compact ? 54 : (store.visible.count >= 5 ? 76 : 95), compact: compact, subtitle: subtitle(account, duplicates: duplicates), selected: page == .detail(account.id), drop: { dragged in
                        withAnimation(.easeOut(duration: 0.16)) { store.move(dragged, to: account.id) }
                    }) {
                        page = page == .detail(account.id) ? .deck : .detail(account.id)
                    }
                    .overlay(alignment: .trailing) {
                        if index + 1 < accounts.count, accounts[index + 1].provider != account.provider {
                            Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: compact ? 38 : 62)
                                .offset(x: 3.5).allowsHitTesting(false)
                        }
                    }
                }
                if store.visible.isEmpty {
                    Button("Add an account") { page = .add }.buttonStyle(.bordered)
                }
            }.frame(maxWidth: .infinity).frame(height: compact ? 89 : 168)
            if !compact || groupCount > 1 {
                HStack(spacing: 5) {
                    Circle().fill(store.refreshing.isEmpty ? Color.quiet : Color.signal).frame(width: 5, height: 5)
                    Text(store.refreshing.isEmpty ? "\(store.visible.count) \(store.visible.count == 1 ? "account" : "accounts")" : "Refreshing…")
                    Spacer()
                    Text("AUTO 5 MIN").tracking(0.6).foregroundStyle(Color.quiet)
                    if groupCount > 1 {
                        Button { group -= 1 } label: { Image(systemName: "chevron.left") }.disabled(group == 0).help("Previous accounts")
                            .overlay {
                                if group > 0 {
                                    AccountDragArea(help: "Previous accounts", click: { group -= 1 }, drop: { dropOnPageArrow($0, step: -1) })
                                }
                            }
                        Text("\(group + 1) / \(groupCount)").monospacedDigit()
                        Button { group += 1 } label: { Image(systemName: "chevron.right") }.disabled(group + 1 >= groupCount).help("Next accounts")
                            .overlay {
                                if group + 1 < groupCount {
                                    AccountDragArea(help: "Next accounts", click: { group += 1 }, drop: { dropOnPageArrow($0, step: 1) })
                                }
                            }
                    }
                }.font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Color.quiet).buttonStyle(.plain)
                    .padding(.horizontal, 18).frame(height: compact ? 20 : 28)
            }
            if page != .deck {
                Divider()
                switch page {
                case .detail(let id):
                    if let account = store.state.accounts.first(where: { $0.id == id }) {
                        Detail(account: account, choose: { key in store.update(id) { $0.preferred = key } },
                               connectDesktop: { store.connectDesktop() }, connecting: store.connectingDesktop, message: store.desktopMessage,
                               signIn: { store.refreshProfile(account, signIn: true) }, profileBusy: store.refreshingProfiles.contains(id),
                               edit: { page = .edit(id) }, close: { page = .deck })
                    }
                case .edit(let id):
                    if let account = store.state.accounts.first(where: { $0.id == id }) {
                        AccountForm(store: store, original: account, done: navigate, close: { page = .detail(id) }).id(id)
                    }
                case .add:
                    AccountForm(store: store, original: nil, done: navigate, close: { page = .deck })
                case .deck: EmptyView()
                }
            }
        }.frame(width: size.width, height: size.height, alignment: .top)
            .foregroundStyle(Color.ink).background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false) }
            .preferredColorScheme(.dark)
            .onChange(of: size, initial: true) { _, value in resize(value) }
            .onChange(of: groupCount) { _, value in group = min(group, value - 1) }
            .onExitCommand { page = .deck }
            .alert("Account storage", isPresented: Binding(get: { store.storageIssue != nil }, set: { if !$0 { store.storageIssue = nil } })) {
                Button("OK") { store.storageIssue = nil }
            } message: { Text(store.storageIssue ?? "") }
    }

    private func dropOnPageArrow(_ id: UUID, step: Int) -> Bool {
        let next = group + step
        guard (0..<groupCount).contains(next) else { return false }
        let index = step > 0 ? next * 5 : next * 5 + 4
        let accounts = store.visible
        guard accounts.indices.contains(index), store.move(id, to: accounts[index].id) else { return false }
        group = next
        return true
    }

    private func navigate(_ id: UUID?) {
        if let id, let index = store.visible.firstIndex(where: { $0.id == id }) {
            group = index / 5
            page = .detail(id)
        } else { page = .deck }
    }

    private func subtitle(_ account: Account, duplicates: Bool) -> String {
        if account.stale { return "Last reading" }
        guard let meter = account.meter else { return account.isDesktopClaude ? "Connect" : (account.issue == nil ? "Connecting…" : "Check login") }
        let qualifier = account.manual ? "Manual" : account.reading?.estimated == true ? "Est." : ""
        let text: String
        if !account.label.isEmpty { text = account.provider.name }
        else if duplicates, account.isDesktopClaude { text = "Desktop" }
        else if duplicates, let identity = account.accountLabel { text = String(identity.split(separator: "@").first ?? Substring(identity)) }
        else { text = meter.title == "5-hour" ? "5h" : meter.title }
        return qualifier.isEmpty ? text : "\(qualifier) \(text)"
    }
}

private struct Detail: View {
    let account: Account
    let choose: (String) -> Void
    let connectDesktop: () -> Void
    let connecting: Bool
    let message: String?
    let signIn: () -> Void
    let profileBusy: Bool
    let edit: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProviderLogo(provider: account.provider, size: 23)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.system(size: 18, weight: .semibold, design: .default))
                    Text([account.label.isEmpty ? nil : account.provider.name, account.reading?.identity ?? account.claudeProfileEmail]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.quiet).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                GlyphButton(symbol: "pencil", help: "Edit account") { edit() }
                GlyphButton(symbol: "xmark", help: "Close details") { close() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.tierName ?? "Tier unknown").font(.system(size: 13, weight: .semibold))
                            Text(account.priceDetail).font(.caption).foregroundStyle(Color.quiet)
                        }
                        Spacer()
                        if account.customPrice == nil, let plan = account.listPlan {
                            Link("Pricing ↗", destination: plan.source).font(.caption)
                        }
                    }.padding(.vertical, 4)
                    if let issue = account.issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    if account.claudeProfileEmail != nil, account.reading == nil || account.issue != nil {
                        Button(profileBusy ? "Checking Claude login…" : "Sign in to Claude", action: signIn).disabled(profileBusy)
                    }
                    if account.isDesktopClaude && account.issue != nil {
                        Button(connecting ? "Connecting…" : "Connect Claude Desktop", action: connectDesktop).disabled(connecting)
                        if let message { Text(message).font(.caption).foregroundStyle(Color.quiet) }
                    }
                    if let bank = account.reading?.bankedResets?.available(at: Date()), bank.count > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.signal).frame(width: 7, height: 7)
                                Text("\(bank.count) banked " + (bank.count == 1 ? "reset" : "resets"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            ForEach(Array(bank.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.caption).foregroundStyle(Color.quiet)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                    ForEach(account.reading?.meters ?? []) { meter in
                        Button { choose(meter.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: account.meter?.id == meter.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(account.provider.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(meter.title).font(.system(size: 12, weight: .semibold))
                                        if account.meter?.id == meter.id || account.innerMeter?.id == meter.id {
                                            Text(account.meter?.id == meter.id ? "Outer ring" : "Inner ring")
                                                .font(.caption2).foregroundStyle(Color.quiet)
                                        }
                                    }
                                    if let reset = meter.reset {
                                        Text(reset <= Date() ? "Reset time passed · \(reset.formatted())" : "Resets \(reset.formatted())")
                                            .font(.system(size: 10)).foregroundStyle(Color.quiet)
                                    }
                                }
                                Spacer()
                                Text("\(meter.remainingText) left").monospacedDigit().foregroundStyle(account.provider.tint)
                            }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 35)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).help("Show \(meter.title.lowercased()) on the ring")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if let reading = account.reading {
                    let source = account.manual ? "Manual entry" : reading.estimated ? "Local estimate" : reading.source.uppercased()
                    Text("\(source) · \(reading.updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(Color.quiet)
                }
                Spacer()
                Link(destination: account.provider.dashboard) { Label("Usage page", systemImage: "arrow.up.right") }
                    .font(.caption).foregroundStyle(account.provider.tint)
            }
        }.padding(16).frame(maxHeight: .infinity, alignment: .top)
    }
}
