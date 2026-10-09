import Foundation
import Observation

public enum PickerKey: Equatable, Sendable {
    case digit(Int)
    case up, down, confirm, escape
    case character(Character)
}

public enum PickerAction: Equatable, Sendable {
    case choose(Browser, remember: Bool)
    case cancel
    case none
}

@MainActor
@Observable
public final class PickerModel {
    public let url: URL
    public let domain: String?
    public let browsers: [Browser]
    public private(set) var highlightIndex: Int
    public var remember = false

    public var canRemember: Bool { domain != nil }

    public init(url: URL, browsers: [Browser], highlight: Browser.ID? = nil) {
        self.url = url
        self.domain = DomainKey.key(for: url)
        self.browsers = browsers
        self.highlightIndex = browsers.firstIndex { $0.id == highlight } ?? 0
    }

    public func toggleRemember() {
        if canRemember { remember.toggle() }
    }

    public func setHighlight(_ index: Int) {
        if browsers.indices.contains(index) { highlightIndex = index }
    }

    /// Mouse click on a row.
    public func choose(index: Int) -> PickerAction {
        guard browsers.indices.contains(index) else { return .none }
        return .choose(browsers[index], remember: remember && canRemember)
    }

    public func handle(_ key: PickerKey) -> PickerAction {
        switch key {
        case .escape:
            return .cancel
        case _ where browsers.isEmpty:
            return .none
        case .digit(let n):
            return (1...9).contains(n) ? choose(index: n - 1) : .none
        case .up:
            highlightIndex = max(highlightIndex - 1, 0)
            return .none
        case .down:
            highlightIndex = min(highlightIndex + 1, browsers.count - 1)
            return .none
        case .confirm:
            return choose(index: highlightIndex)
        case .character(let c):
            if c.lowercased() == "r" { toggleRemember() }
            return .none
        }
    }
}
