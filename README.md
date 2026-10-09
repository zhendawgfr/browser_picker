# Browser Picker

A small macOS menu bar app that becomes your default web browser and decides, for every `http`/`https` link, whether to open it straight away in a remembered browser or ask you which browser to use.

## What it does

- Registers as a web browser, so macOS sends it every `http`/`https` link you click in other apps.
- Links whose domain you have remembered open straight in the chosen browser, with no UI.
- Any other link shows a small keyboard-first picker at the cursor listing your installed browsers.
- Runs in the menu bar only (no Dock icon). Everything stays on your Mac: no network, no link history.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or the Xcode command line tools: `xcode-select --install`)

## Build and install

```bash
git clone <repo-url> browser_picker   # or use your existing checkout
cd browser_picker
scripts/build-app.sh
```

The script builds a release binary, assembles `Browser Picker.app`, signs it ad hoc, and installs it to `~/Applications/Browser Picker.app`. A running copy is quit first. Run the tests with `swift test`.

## Make it your default browser

1. Open `~/Applications/Browser Picker.app`. It has no Dock icon; look for the menu bar item.
2. Choose **Settings…** from the menu bar item.
3. Click **Make default** and confirm the macOS prompt(s) (one for `http`, one for `https`).

Settings then shows "Browser Picker is your default browser". If the app is missing from System Settings → Desktop & Dock → Default web browser, see "Design risks" in `openspec/changes/add-browser-picker/design.md`.

## Using it

- Click a link anywhere. With no remembered rule, a picker appears at the cursor: press `1`–`9`, use the arrow keys and Return, or click. `Esc` or clicking elsewhere cancels.
- Tick **Remember for `<domain>`** (or press `R`) to send that domain, and its subdomains, to the chosen browser from now on. The most specific rule wins.
- Hold **Option (⌥)** while clicking a link to show the picker even when a rule exists; the remembered browser is highlighted.
- Opening the app again from Finder or Spotlight shows Settings.

## Managing rules

Settings → **Remembered sites** lists every rule. Change a rule's browser, delete one, or **Remove all…**. A rule whose browser is no longer installed is kept, labelled "not installed", and applies again if the browser returns.

Rules are stored locally in `UserDefaults` (`dev.evgenyivanov.BrowserPicker`, key `domainRules`). No link history is kept and nothing is sent over the network.

## Known limitation

If Browser Picker is not running when you Option-click a link, macOS launches it and you may release Option before the link arrives, so a remembered browser opens instead of the picker. The app stays running after the first launch, so this is rare.

## Roll back

1. Pick another browser in System Settings → Desktop & Dock → Default web browser.
2. Quit Browser Picker from its menu bar item.
3. Delete `~/Applications/Browser Picker.app`.
4. Optional: `defaults delete dev.evgenyivanov.BrowserPicker` removes saved rules.
