import Testing
import Foundation
@testable import TokenBurn

struct UsageTests {
    private func read(_ json: String, provider: Provider = .claude) throws -> [Observation] {
        try UsageFeed.parse(Data(json.utf8), provider: provider)
    }

    @Test func testMissingPrimaryAndEstimatedOpenCode() throws {
        let rows = try read(#"[{"provider":"opencodego","source":"local","usage":{"primary":null,"secondary":{"usedPercent":0,"windowMinutes":10080,"resetsAt":"2026-11-23T13:00:00.000Z"}}}]"#, provider: .opencodego)
        let reading = try #require(rows.first?.reading)
        #expect(reading.estimated)
        #expect(reading.meters.map(\.title) == ["Weekly"])
        #expect(reading.meters.first?.percent == 0)
        #expect(reading.meters.first?.reset != nil)
    }

    @Test func testDuplicateProviderKeepsCustomizationsAndCacheThroughErrors() throws {
        let data = #"[{"account":"studio","provider":"claude","usage":{"primary":{"usedPercent":17},"extraRateWindows":[{"id":"model","title":"Model","window":{"usedPercent":32}}]}},{"account":"home","provider":"claude","usage":{"primary":{"usedPercent":62}}}]"#
        let observations = try read(data)
        var state = SavedState()
        state.merge(observations, for: .claude)
        let first = try #require(state.accounts.firstIndex { $0.key == "studio" })
        state.accounts[first].label = "Paid"
        state.accounts[first].preferred = "model"
        let firstID = state.accounts[first].id
        let homeID = state.accounts.first { $0.key == "home" }?.id
        state.merge(observations.reversed(), for: .claude)
        state.merge([Observation(key: "studio", issue: "Sign in")], for: .claude)
        #expect(state.accounts.filter { $0.provider == .claude }.count == 2)
        #expect(state.accounts[first].id == firstID)
        #expect(state.accounts[first].name == "Paid")
        #expect(state.accounts[first].meter?.percent == 32)
        #expect(state.accounts[first].stale)
        #expect(state.accounts.first { $0.id == homeID }?.issue != nil)
        state.merge(observations, for: .claude)
        #expect(state.accounts[first].issue == nil)
    }

    @Test func testAnonymousErrorAndUnavailableDoNotInventZeroOrOverwriteManual() throws {
        var state = SavedState()
        let manual = Account(provider: .claude, label: "Personal", manual: true)
        state.accounts.append(manual)
        let error = try read(#"[{"provider":"claude","error":{"message":"Sign in first"}}]"#)
        state.merge(error, for: .claude)
        #expect(state.accounts.first?.meter == nil)
        #expect(state.accounts.last?.issue == nil)
        let bad = try read(#"[{"provider":"claude","usage":{"primary":{"usedPercent":-5}}}]"#)
        #expect(bad[0].reading == nil)
        let saved = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SavedState.self, from: saved).accounts.last?.id == manual.id)
    }

    @Test func discoveredExtrasStayOffTheWidgetUntilAdded() throws {
        let rows = try read(#"[{"provider":"claude","account":"home","usage":{"primary":{"usedPercent":2}}},{"provider":"claude","account":"work","usage":{"primary":{"usedPercent":14}}}]"#)
        var state = SavedState()
        state.merge(rows, for: .claude)
        let extra = try #require(state.accounts.firstIndex { $0.key == "work" })
        #expect(state.accounts.filter { $0.provider == .claude && !$0.hidden }.count == 1)
        #expect(state.accounts[extra].hidden)
        state.accounts[extra].hidden = false
        state.merge(rows.reversed(), for: .claude)
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        #expect(restored.accounts.filter { $0.provider == .claude && !$0.hidden }.count == 2)
    }

    @Test func migrateExistingAutomaticDuplicatesOnce() throws {
        var original = SavedState()
        original.accounts.append(Account(provider: .claude, key: "claude-desktop:second"))
        original.accounts.append(Account(provider: .claude, label: "Manual", manual: true))
        original.explicitExtraAccounts = nil
        var migrated = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(original))
        migrated.migrateAccountVisibility()
        #expect(migrated.accounts[4].hidden)
        #expect(!migrated.accounts[5].hidden)
        migrated.accounts[4].hidden = false
        migrated.migrateAccountVisibility()
        #expect(!migrated.accounts[4].hidden)
    }

    @Test func concentricRingsUseDistinctMeasuredWindows() throws {
        let rows = try read(#"[{"provider":"claude","usage":{"primary":{"usedPercent":2},"secondary":{"usedPercent":8}}}]"#)
        var account = Account(provider: .claude, reading: rows[0].reading)
        #expect(account.meter?.remainingText == "98%")
        #expect(account.innerMeter?.remainingText == "92%")
        account.preferred = "secondary"
        #expect(account.innerMeter?.id == "primary")
        account.reading?.meters.removeFirst()
        #expect(account.innerMeter == nil)
    }

    @Test func resetCountdownUsesTheClockAndExactBandBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func countdown(_ seconds: Double) -> ResetCountdown {
            ResetCountdown(reset: now.addingTimeInterval(seconds), now: now)
        }
        #expect(ResetCountdown(reset: nil, now: now).proximity == .unknown)
        #expect(countdown(-60).text == "due")
        #expect(countdown(0).proximity == .due)
        #expect(countdown(12).text == "<1m")
        #expect(countdown(60).text == "1m")
        #expect(countdown(3600).proximity == .withinHour)
        #expect(countdown(3601).proximity == .withinSixHours)
        #expect(countdown(5400).text == "1h 30m")
        #expect(countdown(21600).proximity == .withinSixHours)
        #expect(countdown(21601).proximity == .withinDay)
        #expect(countdown(86400).proximity == .withinDay)
        #expect(countdown(86401).proximity == .later)
        #expect(countdown(180000).text == "2d 2h")
        #expect(countdown(172800).compactText == "2d")
    }

    @Test func lowRingStartsBelowTwentyPercentRemaining() {
        for (used, low) in [(79.9, false), (80, false), (80.1, true), (100, true)] {
            #expect(Meter(id: "w", title: "Weekly", percent: used).isLow == low)
        }
    }

    @Test func tierPricingFollowsTheAccountAndSurvivesRefresh() throws {
        let rows = try read(#"[{"provider":"codex","usage":{"planObservation":{"rawPlan":"promax"},"secondary":{"usedPercent":7},"providerCost":{"used":18,"limit":30}}}]"#, provider: .codex)
        var state = SavedState()
        state.merge(rows, for: .codex)
        let index = try #require(state.accounts.firstIndex { $0.provider == .codex })
        #expect(state.accounts[index].tierName == "Pro 500")
        #expect(state.accounts[index].priceText == "$500/mo list")
        state.accounts[index].customPrice = "€450/year"
        state.merge(rows, for: .codex)
        let saved = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        #expect(saved.accounts[index].priceText == "€450/year")
        var openCode = Account(provider: .opencodego)
        #expect(openCode.priceText == nil)
        openCode.customTier = "Go Plus"
        #expect(openCode.priceText == "$40/mo list")
        openCode.customTier = "Custom"
        #expect(openCode.priceText == nil)
    }

    @Test func customOrderSurvivesRefreshAndHiddenAccounts() throws {
        var state = SavedState()
        let second = Account(provider: .claude, claudeProfileEmail: "second@example.com")
        state.accounts.append(second)
        let original = state.visibleAccounts.map(\.id)
        state.move(second.id, by: 1)
        let ordered = state.visibleAccounts.map(\.id)
        #expect(ordered[2] == second.id)
        #expect(ordered[1] == original[2])
        state.merge([Observation(issue: "Primary login offline")], for: .claude)
        #expect(state.accounts.first(where: { $0.id == second.id })?.issue == nil)
        state.accounts[0].hidden = true
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        #expect(restored.visibleAccounts.map(\.id) == Array(ordered.dropFirst()))
    }

    @Test func draggingToAnotherTileShiftsItsNeighborsAndPreservesHiddenSlots() {
        var state = SavedState()
        let hidden = Account(provider: .claude, hidden: true)
        state.accounts.append(hidden)
        let ids = state.visibleAccounts.map(\.id)
        state.accountOrder = [ids[0], hidden.id, ids[1], ids[2], ids[3]]
        let movedLater = state.move(ids[0], to: ids[3])
        #expect(movedLater)
        #expect(state.visibleAccounts.map(\.id) == [ids[1], ids[2], ids[3], ids[0]])
        #expect(state.accountOrder?[1] == hidden.id)
        let movedHidden = state.move(hidden.id, to: ids[0])
        #expect(!movedHidden)
        let movedToSelf = state.move(ids[1], to: ids[1])
        #expect(!movedToSelf)
        let movedEarlier = state.move(ids[0], to: ids[1])
        #expect(movedEarlier)
        #expect(state.visibleAccounts.map(\.id) == ids)
    }

    @Test func cornerBadgeHonorsTierAndEnteredPrice() {
        var pro = Account(provider: .claude, customTier: "Pro")
        #expect(pro.badgeAmount == 20)
        pro.customTier = "Max 20x"
        #expect(pro.badgeAmount == 200)
        #expect(Account(provider: .codex, customTier: "Pro 500").badgeAmount == 500)
        pro.customPrice = "€19.95/month"
        #expect(pro.badgeAmount == Decimal(string: "19.95"))
        pro.customPrice = "$20 then $40/mo"
        #expect(pro.badgeAmount == nil)
        #expect(Account(provider: .opencodego).badgeAmount == nil)
    }

    @Test func remainingAllowanceUsesExistingStoredPercent() throws {
        let meter = try JSONDecoder().decode(Meter.self, from: Data(#"{"id":"primary","title":"Weekly","percent":7}"#.utf8))
        #expect(meter.remainingText == "93%")
        #expect(Meter(id: "w", title: "W", percent: 99.6).remainingText == "<1%")
        #expect(Meter(id: "w", title: "W", percent: 100).remainingText == "0%")
        #expect(Meter(id: "w", title: "W", percent: 0).remainingText == "100%")
    }

    @Test func bankedGrantsExpireIndividuallyAndUsedResetsDisappear() throws {
        let row = #"{"provider":"codex","usage":{"primary":{"usedPercent":8},"codexResetCredits":{"credits":[{"title":"Later","status":"available","expires_at":"2031-02-01T10:00:00Z"},{"title":"Earlier","status":"available","expires_at":"2031-01-01T10:00:00Z"},{"title":"Redeemed","status":"used","expires_at":"2031-02-06T00:00:00Z"}]}}}"#
        let bank = try #require(try read("[" + row + "]", provider: .codex).first?.reading?.bankedResets)
        #expect(bank.available(at: .distantPast).lines.first?.hasPrefix("Earlier") == true)
        #expect(bank.available(at: .distantPast).count == 2)
        #expect(bank.available(at: try #require(UsageFeed.date("2031-01-01T10:00:00Z"))).count == 1)
        #expect(bank.available(at: .distantFuture).count == 0)
    }

    @Test func missingClaudeResetInventoryHasSourceSpecificExplanation() throws {
        for source in ["claude", "cli", "oauth", "web"] {
            let rows = try read("""
                [{"provider":"claude","source":"\(source)","usage":{"primary":{"usedPercent":1}}}]
                """)
            let account = Account(provider: .claude, reading: rows.first?.reading)
            #expect(account.claudeResetNote != nil)
            #expect(account.claudeResetNote?.contains("CLI") == ["cli", "claude"].contains(source))
            #expect(account.reading?.bankedResets == nil)
        }
    }

    @Test func claudeBankSummaryStaysAccountScoped() throws {
        let data = #"[{"provider":"claude","account":"one","usage":{"primary":{"usedPercent":2},"details":[{"rows":[{"label":"Limit Reset Credits","value":"2 available","secondaryValue":"Expires Dec 1 at 08:00"}]}]}},{"provider":"claude","account":"two","usage":{"primary":{"usedPercent":14}}}]"#
        let rows = try read(data)
        #expect(rows[0].reading?.bankedResets?.available(at: Date()).count == 2)
        #expect(rows[0].reading?.bankedResets?.expiryNote == "Expires Dec 1 at 08:00")
        #expect(rows[1].reading?.bankedResets == nil)
    }
}
