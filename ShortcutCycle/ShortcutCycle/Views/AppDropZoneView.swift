import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import UniformTypeIdentifiers

struct AppIconThumbnailView: View {
    let app: AppItem
    let size: CGFloat
    let fallbackFontSize: CGFloat

    var body: some View {
        Group {
            if let icon = IconCache.shared.getIcon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: fallbackFontSize))
                    .foregroundColor(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// A row representing a single app in the group list
struct AppRowView: View {
    let app: AppItem
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            AppIconThumbnailView(app: app, size: 32, fallbackFontSize: 24)
            
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
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    init(app: AppItem, isPlaceholder: Bool = false, onDelete: @escaping () -> Void) {
        self.app = app
        self.isPlaceholder = isPlaceholder
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AppIconThumbnailView(app: app, size: 56, fallbackFontSize: 42)

                if isHovered && !isPlaceholder {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
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
        .help(app.bundleIdentifier)
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
        .onTapGesture {
            openFilePicker()
        }
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
