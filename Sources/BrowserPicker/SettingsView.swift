import AppKit
import BrowserPickerCore
import SwiftUI

struct SettingsView: View {
    let ruleStore: RuleStore
    let catalog: BrowserCatalog
    let defaultBrowser: DefaultBrowserService

    @State private var browsers: [Browser] = []
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
        let installed = browsers.contains { $0.id == rule.bundleID }
        return HStack {
            Text(rule.domain)
            Spacer()
            if !installed {
                Text("not installed").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Browser", selection: Binding(
                get: { rule.bundleID },
                set: { id in
                    if let browser = browsers.first(where: { $0.id == id }) {
                        ruleStore.changeBrowser(domain: rule.domain, to: browser)
                    }
                }
            )) {
                ForEach(browsers) { Text($0.name).tag($0.id) }
                if !installed {
                    Text(rule.browserName).tag(rule.bundleID).disabled(true)
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

    private func refresh() {
        browsers = catalog.browsers()
        defaultBrowser.refresh()
    }
}
