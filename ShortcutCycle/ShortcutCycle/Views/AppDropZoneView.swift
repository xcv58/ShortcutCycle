import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import AppKit
import UniformTypeIdentifiers

struct AppIconThumbnailView: View {
    let app: AppItem
    let size: CGFloat
    let fallbackFontSize: CGFloat
    let onIconResolved: (() -> Void)?
    @State private var icon: NSImage?
    @State private var hasReportedResolution = false

    private var displayedIcon: NSImage? {
        icon ?? IconCache.shared.cachedIcon(for: app)
    }

    var body: some View {
        Group {
            if let displayedIcon {
                Image(nsImage: displayedIcon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: fallbackFontSize))
                    .foregroundColor(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .task(id: app.id) {
            hasReportedResolution = false
            loadIconIfNeeded()
        }
    }

    @MainActor
    private func loadIconIfNeeded() {
        if let cachedIcon = IconCache.shared.cachedIcon(for: app) {
            icon = cachedIcon
            reportResolutionIfNeeded()
            return
        }

        icon = nil
        IconCache.shared.loadIcon(for: app) { loadedIcon in
            icon = loadedIcon
            reportResolutionIfNeeded()
        }
    }

    @MainActor
    private func reportResolutionIfNeeded() {
        guard !hasReportedResolution else { return }
        hasReportedResolution = true
        onIconResolved?()
    }
}

/// A row representing a single app in the group list
struct AppRowView: View {
    let app: AppItem
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            AppIconThumbnailView(app: app, size: 32, fallbackFontSize: 24, onIconResolved: nil)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove app from group")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            colorScheme == .dark
                ? SettingsChromePalette.panelBackground(for: colorScheme)
                : Color(nsColor: .controlBackgroundColor)
        )
        .cornerRadius(8)
    }
}

/// A grid item representing a single app with icon and name
struct AppGridItemView: View {
    let app: AppItem
    let isPlaceholder: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onDelete: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onIconResolved: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var isHovered = false

    init(
        app: AppItem,
        isPlaceholder: Bool = false,
        canMoveEarlier: Bool = false,
        canMoveLater: Bool = false,
        onDelete: @escaping () -> Void,
        onMoveEarlier: @escaping () -> Void = {},
        onMoveLater: @escaping () -> Void = {},
        onIconResolved: (() -> Void)? = nil
    ) {
        self.app = app
        self.isPlaceholder = isPlaceholder
        self.canMoveEarlier = canMoveEarlier
        self.canMoveLater = canMoveLater
        self.onDelete = onDelete
        self.onMoveEarlier = onMoveEarlier
        self.onMoveLater = onMoveLater
        self.onIconResolved = onIconResolved
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AppIconThumbnailView(app: app, size: 56, fallbackFontSize: 42, onIconResolved: onIconResolved)

                if isHovered && !isPlaceholder {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel(removeActionLabel)
                }
            }

            Text(app.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 88)
        }
        .opacity(isPlaceholder ? 0.12 : 1)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isPlaceholder
                    ? (colorScheme == .dark
                        ? SettingsChromePalette.neutralHoverFill(for: colorScheme).opacity(0.45)
                        : Color.secondary.opacity(0.05))
                    : (isHovered
                        ? (colorScheme == .dark
                            ? SettingsChromePalette.neutralHoverFill(for: colorScheme)
                            : Color.accentColor.opacity(0.1))
                        : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isPlaceholder
                        ? (colorScheme == .dark
                            ? SettingsChromePalette.neutralHoverBorder(for: colorScheme)
                            : Color.secondary.opacity(0.18))
                        : ((colorScheme == .dark && isHovered)
                            ? SettingsChromePalette.neutralHoverBorder(for: colorScheme)
                            : Color.clear),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .onHover { hovering in
            isHovered = isPlaceholder ? false : hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityActions {
            if canMoveEarlier {
                Button(moveEarlierActionLabel, action: onMoveEarlier)
            }
            if canMoveLater {
                Button(moveLaterActionLabel, action: onMoveLater)
            }
            Button(removeActionLabel, action: onDelete)
        }
        .contextMenu {
            if canMoveEarlier {
                Button(moveEarlierActionLabel, systemImage: "arrow.left", action: onMoveEarlier)
            }
            if canMoveLater {
                Button(moveLaterActionLabel, systemImage: "arrow.right", action: onMoveLater)
            }
            Divider()
            Button(removeActionLabel, systemImage: "trash", role: .destructive, action: onDelete)
        }
        .help(app.bundleIdentifier)
    }

    private var moveEarlierActionLabel: String {
        String(
            format: "Move %@ earlier".localized(language: selectedLanguage),
            app.name
        )
    }

    private var moveLaterActionLabel: String {
        String(
            format: "Move %@ later".localized(language: selectedLanguage),
            app.name
        )
    }

    private var removeActionLabel: String {
        String(
            format: "Remove %@ from group".localized(language: selectedLanguage),
            app.name
        )
    }
}

/// Drop zone for adding apps from Finder
struct AppDropZoneView: View {
    @Binding var apps: [AppItem]
    @State private var isTargeted = false
    let onAppAdded: (AppItem) -> Void
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: openFilePicker) {
            VStack(spacing: 10) {
                Image(systemName: "plus.app")
                    .font(.system(size: 28))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text("Drop or click to add apps".localized(language: selectedLanguage))
                    .font(.caption)
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SettingsChromePalette.dropZoneFill(for: colorScheme, targeted: isTargeted))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        SettingsChromePalette.dropZoneBorder(for: colorScheme, targeted: isTargeted),
                        style: StrokeStyle(lineWidth: colorScheme == .dark ? 2 : 2, dash: [8])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drop or click to add apps".localized(language: selectedLanguage))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select applications to add to this group".localized(language: selectedLanguage)
        panel.prompt = "Add".localized(language: selectedLanguage)
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let appItem = AppItem.from(appURL: url) {
                    onAppAdded(appItem)
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension == "app" else {
                    return
                }
                
                if let appItem = AppItem.from(appURL: url) {
                    DispatchQueue.main.async {
                        onAppAdded(appItem)
                    }
                }
            }
        }
        return true
    }
}

#Preview("App Row") {
    AppRowView(
        app: AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari"),
        onDelete: {}
    )
    .frame(width: 300)
    .padding()
}

#Preview("Drop Zone") {
    struct PreviewWrapper: View {
        @State var apps: [AppItem] = []
        
        var body: some View {
            AppDropZoneView(apps: $apps) { _ in }
                .frame(width: 300)
                .padding()
        }
    }
    
    return PreviewWrapper()
}
