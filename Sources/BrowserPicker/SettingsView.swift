import AppKit
import BrowserPickerCore
import SwiftUI

struct SettingsView: View {
    let ruleStore: RuleStore
    let catalog: BrowserCatalog
    let defaultBrowser: DefaultBrowserService

    @State private var targets: [BrowserTarget] = []
    @State private var blocked: [Browser] = []
    @State private var confirmRemoveAll = false

    var body: some View {
        Form {
            Section("Default browser") {
                if defaultBrowser.isDefault {
                    Label("Browser Picker is your default browser", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Browser Picker is not your default browser", systemImage: "exclamationmark.circle")
                        Spacer()
                        Button("Make default") { Task { await defaultBrowser.makeDefault() } }
                    }
                    if let error = defaultBrowser.lastError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !blocked.isEmpty {
                Section("Profiles") {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ListFormatter.localizedString(byJoining: blocked.map(\.name))) profiles need Full Disk Access")
                            Text("macOS protects these browsers’ profile lists, so each shows as a single row. Add Browser Picker under Full Disk Access to pick a profile.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock")
                    }
                    HStack {
                        Spacer()
                        Button("Open Full Disk Access Settings…", action: openFullDiskAccess)
                    }
                }
            }

            Section("Remembered sites") {
                if ruleStore.rules.isEmpty {
                    Text("No remembered sites. Tick “Remember” in the picker to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ruleStore.rules, id: \.domain) { rule in
                        ruleRow(rule)
                    }
                    HStack {
                        Spacer()
                        Button("Remove all…", role: .destructive) { confirmRemoveAll = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 320)
        .confirmationDialog("Remove all remembered sites?", isPresented: $confirmRemoveAll) {
            Button("Remove all", role: .destructive) { ruleStore.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every link will show the picker again.")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh() }
    }

    private func ruleRow(_ rule: DomainRule) -> some View {
        let resolved = targets.contains { $0.id == rule.targetID }
        let installed = targets.contains { $0.browser.id == rule.bundleID }
        // A rule without a profile on a browser listed by profile: shown as the browser's last-used profile.
        let lastUsed = !resolved && rule.profileID == nil && installed
        let unavailable: String? = resolved || lastUsed ? nil
            : !installed ? "not installed"
            : ProfileSource.forBundleID(rule.bundleID) == .arcSpaces ? "Space not found" : "profile not found"
        return HStack {
            Text(rule.domain)
            Spacer()
            if let unavailable {
                Text(unavailable).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Browser", selection: Binding(
                get: { rule.targetID },
                set: { id in
                    if let target = targets.first(where: { $0.id == id }) {
                        ruleStore.change(domain: rule.domain, to: target)
                    }
                }
            )) {
                ForEach(targets) { Text($0.label).tag($0.id) }
                if lastUsed, let browser = targets.first(where: { $0.browser.id == rule.bundleID })?.browser {
                    Text(BrowserTarget.lastUsed(browser).label).tag(rule.targetID)
                } else if let unavailable {
                    Text(rule.snapshotLabel).tag(rule.targetID).disabled(true)
                        .help(unavailable)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button {
                ruleStore.delete(domain: rule.domain)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
    }

    private func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh() {
        targets = catalog.targets()
        blocked = catalog.blockedBrowsers()
        defaultBrowser.refresh()
    }
}
