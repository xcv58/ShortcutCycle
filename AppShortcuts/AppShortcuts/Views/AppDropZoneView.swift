import SwiftUI
import UniformTypeIdentifiers

/// A row representing a single app in the group list
struct AppRowView: View {
    let app: AppItem
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let iconPath = app.iconPath,
               let icon = NSWorkspace.shared.icon(forFile: iconPath + "/Contents/Resources/AppIcon.icns") as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            
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

/// Drop zone for adding apps from Finder
struct AppDropZoneView: View {
    @Binding var apps: [AppItem]
    @State private var isTargeted = false
    let onAppAdded: (AppItem) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.app")
                .font(.system(size: 24))
                .foregroundColor(isTargeted ? .accentColor : .secondary)
            
            Text("Drop apps here")
                .font(.caption)
                .foregroundColor(isTargeted ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
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
