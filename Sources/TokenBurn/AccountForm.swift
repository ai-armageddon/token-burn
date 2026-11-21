import SwiftUI
import AppKit

struct AccountForm: View {
    @ObservedObject var store: Store
    let original: Account?
    let done: (UUID?) -> Void
    let close: () -> Void
    @ViewState private var live = true
    @ViewState private var loginEmail = ""
    @ViewState private var provider: Provider
    @ViewState private var label: String
    @ViewState private var tier: String
    @ViewState private var price: String
    @ViewState private var percent: String
    @ViewState private var period: String
    @ViewState private var hasReset: Bool
    @ViewState private var reset: Date
    @ViewState private var connectionMessage: String?

    init(store: Store, original: Account?, done: @escaping (UUID?) -> Void, close: @escaping () -> Void) {
        self.store = store
        self.original = original
        self.done = done
        self.close = close
        _provider = State(initialValue: original?.provider ?? .claude)
        _label = State(initialValue: original?.label ?? "")
        _tier = State(initialValue: original?.customTier ?? "")
        _price = State(initialValue: original?.customPrice ?? "")
        _percent = State(initialValue: original?.meter.map { $0.remaining.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)) } ?? "")
        _period = State(initialValue: original?.meter?.title ?? "Weekly")
        _reset = State(initialValue: original?.meter?.reset ?? Date().addingTimeInterval(86400))
        _hasReset = State(initialValue: original?.meter?.reset != nil)
    }

    private var manual: Bool { original?.manual ?? !live }
    private var validPercent: Double? {
        guard let n = Double(percent.trimmingCharacters(in: .whitespaces)), n.isFinite, (0...100).contains(n) else { return nil }
        return n
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(original == nil ? "Add an account" : "Edit account").font(.system(size: 18, weight: .semibold, design: .default))
                Spacer()
                GlyphButton(symbol: "xmark", help: "Cancel") { close() }
            }
            if original == nil {
                Picker("Account source", selection: $live) {
                    Text("Connected accounts").tag(true)
                    Text("Manual entry").tag(false)
                }.pickerStyle(.segmented).labelsHidden()
            }
            if original == nil && live {
                Text("Use the arrows to order your accounts. Choose Add to show another account.")
                    .font(.callout).foregroundStyle(Color.quiet).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.visible + store.state.accounts.filter(\.hidden)) { account in
                            HStack {
                                ProviderLogo(provider: account.provider, size: 14)
                                Text(account.name).font(.caption).fontWeight(.semibold)
                                Text(account.accountLabel ?? (account.manual ? "Manual" : "Default account"))
                                    .font(.caption).foregroundStyle(Color.quiet).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if !account.hidden {
                                    GlyphButton(symbol: "chevron.up", help: "Move \(account.name) earlier") {
                                        store.move(account.id, by: -1)
                                    }.disabled(store.visible.first?.id == account.id)
                                    GlyphButton(symbol: "chevron.down", help: "Move \(account.name) later") {
                                        store.move(account.id, by: 1)
                                    }.disabled(store.visible.last?.id == account.id)
                                }
                                Button(account.hidden ? "Add" : "View") {
                                    if account.hidden { store.showAccount(account.id) }
                                    done(account.id)
                                }.buttonStyle(.link).font(.caption)
                            }.padding(.vertical, 2)
                        }
                    }
                }
                HStack {
                    TextField("Claude account email", text: $loginEmail).textFieldStyle(.roundedBorder)
                    Button("Add Claude login") {
                        done(store.addClaudeProfile(loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }.disabled(!loginEmail.contains("@") || loginEmail.contains(" "))
                }
                if let connectionMessage { Text(connectionMessage).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("Open CodexBar") {
                        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.steipete.codexbar")
                            ?? (FileManager.default.fileExists(atPath: "/Applications/CodexBar.app") ? URL(fileURLWithPath: "/Applications/CodexBar.app") : nil) {
                            NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
                                if error != nil { DispatchQueue.main.async { connectionMessage = "Open CodexBar from Applications to manage logins." } }
                            }
                        } else { NSWorkspace.shared.open(URL(string: "https://codexbar.app")!) }
                    }
                    Spacer()
                    Button("Refresh accounts") { store.refresh() }.disabled(!store.refreshing.isEmpty)
                }
            } else {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                        GridRow {
                            Text("Provider")
                            if original == nil {
                                Picker("Provider", selection: $provider) {
                                    ForEach(Provider.allCases) { Text($0.name).tag($0) }
                                }.labelsHidden()
                            } else { Text(provider.name).foregroundStyle(provider.tint) }
                        }
                        GridRow {
                            Text("Label")
                            TextField("e.g. Personal, Studio", text: $label)
                        }
                        GridRow {
                            Text("Plan tier")
                            TextField(original?.reading?.plan ?? "e.g. Go Plus", text: $tier)
                        }
                        GridRow {
                            Text("Your price")
                            TextField("e.g. $20/mo or €180/year", text: $price)
                        }
                        if manual {
                            GridRow {
                                Text("Window")
                                Picker("Window", selection: $period) {
                                    ForEach(["Session", "Daily", "Weekly", "Monthly"], id: \.self) { Text($0) }
                                }.labelsHidden()
                            }
                            GridRow {
                                Text("Remaining")
                                HStack { TextField("0–100", text: $percent).frame(width: 65); Text("%") }
                            }
                            GridRow {
                                Text("Reset")
                                HStack {
                                    Toggle("Set reset", isOn: $hasReset).toggleStyle(.checkbox).labelsHidden()
                                    if hasReset { DatePicker("Reset date", selection: $reset).labelsHidden() }
                                }
                            }
                        }
                    }.font(.callout).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    if let original {
                        Button("Hide account") { store.update(original.id) { $0.hidden = true }; done(nil) }.buttonStyle(.link)
                    }
                    Spacer()
                    Button("Cancel") { close() }
                    Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(manual && validPercent == nil)
                }
            }
        }.tint(Color.signal).padding(16).frame(maxHeight: .infinity, alignment: .top)
    }

    private func save() {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let tierInput = tier.trimmingCharacters(in: .whitespacesAndNewlines)
        let priceInput = price.trimmingCharacters(in: .whitespacesAndNewlines)
        let customTier = tierInput.isEmpty ? nil : tierInput
        let customPrice = priceInput.isEmpty ? nil : priceInput
        var reading: Reading?
        if manual {
            guard let number = validPercent else { return }
            reading = Reading(meters: [Meter(id: "manual", title: period, percent: 100 - number, reset: hasReset ? reset : nil)],
                              updated: Date(), source: "manual", estimated: false)
        }
        if let original {
            store.update(original.id) {
                $0.label = name
                $0.customTier = customTier
                $0.customPrice = customPrice
                if let reading { $0.reading = reading }
            }
            done(original.id)
        } else {
            let account = Account(provider: provider, label: name, manual: true, reading: reading, customTier: customTier, customPrice: customPrice)
            store.add(account)
            done(account.id)
        }
    }
}
