import AppKit
import BrowserPickerCore
import SwiftUI

struct PickerView: View {
    @Bindable var model: PickerModel
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.domain ?? "Open link")
                    .font(.headline)
                Text(model.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.url.absoluteString)
            }

            if model.targets.isEmpty {
                Text("No browsers found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(model.targets.enumerated()), id: \.element.id) { index, target in
                        row(target, index: index)
                    }
                }
            }

            Toggle("Remember for \(model.domain ?? "this domain")", isOn: $model.remember)
                .toggleStyle(.checkbox)
                .disabled(!model.canRemember)
        }
        .padding(12)
        .frame(width: 320)
    }

    private func row(_ target: BrowserTarget, index: Int) -> some View {
        let highlighted = index == model.highlightIndex
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: target.browser.appURL.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(target.label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(highlighted ? .white.opacity(0.9) : .secondary)
                    .frame(minWidth: 18)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(highlighted ? 0 : 1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { if $0 { model.setHighlight(index) } }
        .onTapGesture { onChoose(index) }
    }
}
