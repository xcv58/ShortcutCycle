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
