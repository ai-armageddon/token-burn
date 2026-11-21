import Foundation

/// US web list rates checked November 20, 2026. These apply to identifiable plan
/// names only. Usage caps, balances and extra-credit spend are separate figures.
struct ListPlan {
    let name: String
    let dollars: Int
    let source: URL

    static func lookup(_ raw: String, provider: Provider) -> ListPlan? {
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        let rate: (String, Int)
        let url: String
        switch provider {
        case .claude:
            url = "https://support.claude.com/en/articles/11049762-choose-a-claude-plan"
            switch key {
            case "claudemax20x", "max20x": rate = ("Max 20x", 200)
            case "claudemax5x", "max5x": rate = ("Max 5x", 100)
            case "claudepro", "pro": rate = ("Pro", 20)
            case "claudefree", "free": rate = ("Free", 0)
            default: return nil
            }
        case .codex:
            if ["go", "chatgptgo", "plus", "chatgptplus", "free"].contains(key) {
                url = "https://openai.com/index/introducing-chatgpt-go/"
            } else {
                url = "https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers"
            }
            switch key {
            case "free": rate = ("Free", 0)
            case "go", "chatgptgo": rate = ("Go", 8)
            case "plus", "chatgptplus": rate = ("Plus", 20)
            case "promax", "pro500", "chatgptpro500": rate = ("Pro 500", 500)
            case "pro200", "chatgptpro200": rate = ("Pro 200", 200)
            case "prolite", "pro100", "chatgptpro100": rate = ("Pro 100", 100)
            default: return nil
            }
        case .grok:
            url = "https://x.ai/pricing"
            switch key {
            case "supergrok": rate = ("SuperGrok", 30)
            case "supergrokplus": rate = ("SuperGrok Plus", 100)
            default: return nil
            }
        case .opencodego:
            url = "https://opencode.ai/docs/console/go/"
            switch key {
            case "go", "opencodego": rate = ("Go", 10)
            case "goplus", "opencodegoplus": rate = ("Go Plus", 40)
            default: return nil
            }
        }
        return ListPlan(name: rate.0, dollars: rate.1, source: URL(string: url)!)
    }
}

extension Account {
    var tier: String? { customTier ?? reading?.plan }
    var listPlan: ListPlan? { tier.flatMap { ListPlan.lookup($0, provider: provider) } }
    var tierName: String? { listPlan?.name ?? tier }
    var priceText: String? { customPrice ?? listPlan.map { "$\($0.dollars)/mo list" } }
    var badgeAmount: Decimal? {
        guard let customPrice else { return listPlan.map { Decimal($0.dollars) } }
        // Accept a single billed amount; mixed or ambiguous descriptions keep their full text in details.
        let price = customPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:[A-Za-z]{3}\s*|US)?[$€£¥₹]?\s*([0-9]+(?:\.[0-9]{1,2})?)\s*(?:[A-Za-z]{3}\b)?(?:\s*(?:/|per\s+)\s*[A-Za-z]+)?$"#
        guard let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            .firstMatch(in: price, range: NSRange(price.startIndex..., in: price)),
              let range = Range(match.range(at: 1), in: price) else { return nil }
        return Decimal(string: String(price[range]), locale: Locale(identifier: "en_US_POSIX"))
    }

    var priceDetail: String {
        if let customPrice { return "\(customPrice) · Entered by you" }
        if let listPlan { return "US$\(listPlan.dollars)/month · US web list price" }
        return "Price unavailable · Set your price in Edit account"
    }
}
