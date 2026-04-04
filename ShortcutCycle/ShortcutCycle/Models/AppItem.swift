import AppKit
import Foundation

/// Represents a single application that can be part of a group
public struct AppItem: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let bundleIdentifier: String
    public let name: String
    public var iconPath: String?
    
    public init(id: UUID = UUID(), bundleIdentifier: String, name: String, iconPath: String? = nil) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.iconPath = iconPath
    }
    
    /// Create an AppItem from a file URL pointing to an .app bundle
    public static func from(appURL: URL) -> AppItem? {
        guard let bundle = Bundle(url: appURL),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }
        
        let name = FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
        
        return AppItem(
            bundleIdentifier: bundleIdentifier,
            name: name,
            iconPath: appURL.path
        )
    }
}

public struct RunningAppQuickAddSource: Equatable {
    public let bundleIdentifier: String
    public let bundleURL: URL?
    public let activationPolicy: NSApplication.ActivationPolicy

    public init(
        bundleIdentifier: String,
        bundleURL: URL?,
        activationPolicy: NSApplication.ActivationPolicy = .regular
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.activationPolicy = activationPolicy
    }

    public init?(runningApplication: NSRunningApplication) {
        guard let bundleIdentifier = runningApplication.bundleIdentifier else {
            return nil
        }

        self.init(
            bundleIdentifier: bundleIdentifier,
            bundleURL: runningApplication.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            activationPolicy: runningApplication.activationPolicy
        )
    }
}

public enum RunningAppQuickAdd {
    public static func candidates(
        for groupApps: [AppItem],
        runningApps: [RunningAppQuickAddSource],
        excludedBundleIdentifiers: Set<String> = []
    ) -> [AppItem] {
        let existingBundleIdentifiers = Set(groupApps.map(\.bundleIdentifier))
        let excluded = existingBundleIdentifiers.union(excludedBundleIdentifiers)
        var seenBundleIdentifiers = Set<String>()

        let candidates = runningApps.compactMap { runningApp -> AppItem? in
            guard runningApp.activationPolicy == .regular else { return nil }
            guard !excluded.contains(runningApp.bundleIdentifier) else { return nil }
            guard seenBundleIdentifiers.insert(runningApp.bundleIdentifier).inserted else { return nil }
            guard let appURL = runningApp.bundleURL else { return nil }
            return AppItem.from(appURL: appURL)
        }

        return candidates.sorted { lhs, rhs in
            let lhsKey = lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let rhsKey = rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            if lhsKey == rhsKey {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }

            return lhsKey < rhsKey
        }
    }
}
