# Token Burn

Token Burn is a macOS app for tracking AI subscriptions. Its main view, the **Deck**, keeps your accounts visible across desktops. Each ring shows the percentage of allowance left for Claude, Codex, OpenCode Go or Grok. Each provider logo sits inside its allowance rings. The outer ring shows the selected window and the inner ring shows a second reported window when available. Dividers separate providers. The arc is green at 20% remaining or above, and red below 20%. An unknown balance has a gray ring.

## Run

Requires macOS 14 or later. Install the Xcode Command Line Tools to build from source. Automatic readings use the CodexBar CLI (tested with 0.84.0) and your existing provider logins. The app also supports manually entered usage.

```sh
./build.sh
open "dist/Token Burn.app"
```

Drag the dotted grip or title to move the panel. Drag the bottom-right grip to make the widget smaller or larger. Its scale is saved across launches. The diagonal arrows switch between full and compact layouts. Click the minus button to minimize, then choose **Restore Deck** from its menu-bar icon. The pin keeps it above other windows. The green usage rings in the menu bar open the Deck controls.

## Accounts and readings

- Hover over a ring for a summary. Click it for the account, plan, usage windows, reset times and last update. Select a window to display its remaining percentage on the ring. An orange dot means the account has banked resets. Hover or expand for the count and reported expirations. Claude may report only the next expiry.
- Drag an account tile onto another tile to move it into that position. A click opens details. With multiple pages, drop on a page arrow to move across the page boundary. The arrows in **+ → Connected accounts** also change the order. Each account keeps its position across refreshes and restarts.
- Each tile shows its numeric price in a colored corner badge when a single price is known. The clock beside the badge counts down to the outer ring’s reset and updates every minute. Green means within an hour, amber within six hours, blue within a day and purple beyond a day. A dash means the provider did not supply a reset time. A past reset shows “due” until a new reading arrives. Hover for the exact local reset time, currency, billing period and price source.
- To add a separate Claude login, enter the email in **+ → Connected accounts → Add Claude login** and finish the Claude browser authorization. Each login uses its own Claude Code profile. Token Burn checks the email before displaying its allowances.
- Full-size rings display the account tier and price. Compact rings include them on hover. A price marked **list** is the published US monthly web rate for a recognized tier. The pencil lets you enter your billed price with its currency and interval, or supply a missing tier. Clearing a field restores automatic display.
- Click the pencil to name the account. Click **+** to see connected accounts, add discovered accounts or bring back hidden rings, or add a manual account with a label, remaining percentage and optional reset.
- To show a distinct Claude Desktop login, use **+ → Connected accounts → Add**. If it says **Connect**, open its details and click **Connect Claude Desktop** to authorize CodexBar in macOS Keychain.
- For additional automatic accounts, add the provider login to CodexBar where the provider supports multiple accounts, then click **Refresh accounts**. Only one account per provider appears by default. Use **Add** to show any additional discovered account. Token Burn discovers the named accounts returned by `codexbar usage --provider … --all-accounts` and falls back to the active login when no token accounts are configured. The provider's own dashboard opens in your default browser, using that browser's signed-in account.
- Automatic readings refresh at launch and every five minutes while the app is running. OpenCode tracks the Go subscription. A local estimate is marked **Est.** on the ring. For account-wide OpenCode Go readings, configure the Go API key in CodexBar.
- A failed refresh preserves the last reading and shows its age in details. An unreported allowance shows a dash. Manual readings keep their entered value after the reset until you update them.
- Settings, labels and cached readings are saved in `~/Library/Application Support/Token Burn/accounts.json`. Provider authentication is handled by CodexBar.

Run `./test.sh` to check account reconciliation and usage decoding.

[CodexBar CLI and account setup](https://github.com/steipete/CodexBar/blob/main/docs/cli.md)

Provider marks come from the CodexBar provider icon set and the [OpenCode brand assets](https://opencode.ai/brand).
