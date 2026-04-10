import AppKit
import Foundation
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

class IconCache {
    static let shared = IconCache()

    private let lock = NSLock()
    private let lookupQueue = DispatchQueue(label: "ShortcutCycle.IconCache", qos: .userInitiated)
    private var cache: [String: NSImage] = [:]
    private var failedLookups: Set<String> = []
    private var pendingCallbacks: [String: [(NSImage?) -> Void]] = [:]

    private init() {}

    func cachedIcon(for appItem: AppItem) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        if failedLookups.contains(appItem.bundleIdentifier) {
            return nil
        }

        return cache[appItem.bundleIdentifier]
    }

    func getIcon(for appItem: AppItem) -> NSImage? {
        if let cached = cachedIcon(for: appItem) {
            return cached
        }

        let icon = Self.resolveIcon(for: appItem)

        lock.lock()
        if let icon {
            cache[appItem.bundleIdentifier] = icon
            failedLookups.remove(appItem.bundleIdentifier)
        } else {
            failedLookups.insert(appItem.bundleIdentifier)
        }
        lock.unlock()

        return icon
    }

    func loadIcon(for appItem: AppItem, completion: @escaping (NSImage?) -> Void) {
        if let cached = cachedIcon(for: appItem) {
            completion(cached)
            return
        }

        let key = appItem.bundleIdentifier
        var shouldStartLookup = false

        lock.lock()
        if failedLookups.contains(key) {
            lock.unlock()
            completion(nil)
            return
        }

        if pendingCallbacks[key] != nil {
            pendingCallbacks[key, default: []].append(completion)
        } else {
            pendingCallbacks[key] = [completion]
            shouldStartLookup = true
        }
        lock.unlock()

        guard shouldStartLookup else { return }

        lookupQueue.async { [appItem] in
            let icon = Self.resolveIcon(for: appItem)

            DispatchQueue.main.async {
                self.finishLookup(for: key, icon: icon)
            }
        }
    }

    func prefetchIcons(for apps: [AppItem]) {
        for app in apps {
            loadIcon(for: app) { _ in }
        }
    }

    private func finishLookup(for key: String, icon: NSImage?) {
        lock.lock()
        if let icon {
            cache[key] = icon
        } else {
            failedLookups.insert(key)
        }
        let callbacks = pendingCallbacks.removeValue(forKey: key) ?? []
        lock.unlock()

        for callback in callbacks {
            callback(icon)
        }
    }

    private static func resolveIcon(for appItem: AppItem) -> NSImage? {
        var icon: NSImage?

        // Try to get icon from running app first (most accurate)
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appItem.bundleIdentifier).first {
            icon = runningApp.icon
        }

        // Try path
        if icon == nil, let path = appItem.iconPath {
            icon = NSWorkspace.shared.icon(forFile: path)
        }

        // Try finding app by bundle ID
        if icon == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appItem.bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }

        return icon
    }
}
