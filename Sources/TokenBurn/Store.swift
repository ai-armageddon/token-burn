import AppKit
import Combine

struct SavedState: Codable {
    var accounts = Provider.allCases.map { Account(provider: $0) }
    var pinned = true
    var explicitExtraAccounts: Bool? = true

    mutating func migrateAccountVisibility() {
        guard explicitExtraAccounts != true else { return }
        var primaryProviders = Set<Provider>()
        for i in accounts.indices where !accounts[i].manual {
            if !primaryProviders.insert(accounts[i].provider).inserted {
                accounts[i].hidden = true
            }
        }
        explicitExtraAccounts = true
    }

    mutating func merge(_ observations: [Observation], for provider: Provider) {
        let existing = accounts.indices.filter { accounts[$0].provider == provider && !accounts[$0].manual }
        if observations.count == 1, let observation = observations.first, observation.key == nil, observation.reading == nil {
            for index in existing { accounts[index].issue = observation.issue }
            return
        }
        var seen = Set<UUID>()
        for observation in observations {
            if observation.key == nil, observation.reading == nil {
                for index in existing where !accounts[index].isDesktopClaude {
                    accounts[index].issue = observation.issue
                    seen.insert(accounts[index].id)
                }
                continue
            }
            let match = existing.first { accounts[$0].key == observation.key }
            let empty = existing.first { accounts[$0].key == nil && accounts[$0].reading == nil && !seen.contains(accounts[$0].id) }
            let index: Int
            if let found = match ?? empty { index = found }
            else {
                index = accounts.endIndex
                accounts.append(Account(provider: provider, hidden: true))
            }
            accounts[index].key = observation.key
            if let reading = observation.reading { accounts[index].reading = reading }
            accounts[index].issue = observation.issue
            seen.insert(accounts[index].id)
        }
        for index in existing where !seen.contains(accounts[index].id) {
            accounts[index].issue = "This account was absent from the latest refresh. Check its login in CodexBar."
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: SavedState
    @Published private(set) var refreshing = Set<Provider>()
    @Published var storageIssue: String?
    private let file: URL
    private var canSave = true
    private var timer: Timer?
    private var expiryTimer: Timer?
    @Published var connectingDesktop = false
    @Published var desktopMessage: String?
    var visible: [Account] {
        Provider.allCases.flatMap { provider in state.accounts.filter { $0.provider == provider && !$0.hidden } }
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Token Burn", isDirectory: true)
        file = directory.appendingPathComponent("accounts.json")
        state = SavedState()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
                state.migrateAccountVisibility()
            }
        } catch {
            canSave = false
            storageIssue = "Could not load saved accounts. Check \(file.path) before restarting."
        }
    }

    func start() {
        scheduleExpiry()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func connectDesktop() {
        guard !connectingDesktop else { return }
        connectingDesktop = true
        desktopMessage = nil
        Task {
            let message = await Task.detached(priority: .userInitiated) { DesktopClaude.connect() }.value
            connectingDesktop = false
            desktopMessage = message
            refresh()
        }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        let dates = state.accounts.flatMap { $0.reading?.bankedResets?.dates ?? [] }
        guard let first = dates.filter({ $0 > Date() }).min() else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, first.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
                self?.scheduleExpiry()
            }
        }
    }

    func showAccount(_ id: UUID) {
        guard let account = state.accounts.first(where: { $0.id == id }) else { return }
        update(id) { $0.hidden = false }
        if account.isDesktopClaude {
            if refreshing.contains(.claude) { retryDesktop = true } else { refresh(.claude) }
        }
    }

    private var retryDesktop = false

    func refresh() {
        for provider in Provider.allCases { refresh(provider) }
    }

    private func refresh(_ provider: Provider) {
        guard refreshing.insert(provider).inserted else { return }
        let desktopKeys = Set(state.accounts.filter { $0.isDesktopClaude && !$0.hidden }.compactMap(\.key))
        Task {
            let result = await Task.detached(priority: .utility) { UsageFeed.fetch(provider, desktopKeys: desktopKeys) }.value
            state.merge(result, for: provider)
            scheduleExpiry()
            refreshing.remove(provider)
            save()
            if provider == .claude && retryDesktop {
                retryDesktop = false
                refresh(.claude)
            }
        }
    }

    func setPinned(_ value: Bool) { state.pinned = value; save() }

    func update(_ id: UUID, _ change: (inout Account) -> Void) {
        guard let index = state.accounts.firstIndex(where: { $0.id == id }) else { return }
        change(&state.accounts[index])
        save()
    }

    func add(_ account: Account) {
        state.accounts.append(account)
        save()
    }

    private func save() {
        guard canSave else { return }
        do {
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            storageIssue = nil
        } catch { storageIssue = "Could not save your changes to \(file.path)." }
    }
}
