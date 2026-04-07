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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// A grid item representing a single app with icon and name
struct AppGridItemView: View {
    let app: AppItem
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                AppIconThumbnailView(app: app, size: 56, fallbackFontSize: 42)
    
                Text(app.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((isHovered || isSelected) ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(app.bundleIdentifier)
        .accessibilityLabel(app.name)
    }
}

/// Drop zone for adding apps from Finder
struct AppDropZoneView: View {
    @Binding var apps: [AppItem]
    @State private var isTargeted = false
    let onAppAdded: (AppItem) -> Void
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    
    var body: some View {
        Button(action: openFilePicker) {
            VStack(spacing: 10) {
                Image(systemName: "plus.app")
                    .font(.system(size: 28))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text("Drop or click to add apps".localized(language: selectedLanguage))
                    .font(.caption.weight(.medium))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .foregroundColor(isTargeted ? .accentColor : .gray.opacity(0.3))
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help("Select applications to add to this group".localized(language: selectedLanguage))
        .accessibilityLabel("Add Apps".localized(language: selectedLanguage))
        .accessibilityHint("Select applications to add to this group".localized(language: selectedLanguage))
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
