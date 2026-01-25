import SwiftUI

/// Main settings window view with sidebar and detail
struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @State private var showAccessibilityAlert = false
    
    var body: some View {
        NavigationSplitView {
            GroupListView()
                .frame(minWidth: 200)
        } detail: {
            if let selectedId = store.selectedGroupId {
                GroupEditView(groupId: selectedId)
            } else {
                ContentUnavailableView(
                    "No Group Selected",
                    systemImage: "folder",
                    description: Text("Select a group from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            checkAccessibility()
        }
        .alert("Accessibility Permission Required", isPresented: $showAccessibilityAlert) {
            Button("Open System Preferences") {
                AccessibilityHelper.shared.openAccessibilityPreferences()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("App Shortcuts needs accessibility permission to register global keyboard shortcuts and switch between applications.")
        }
    }
    
    private func checkAccessibility() {
        if !AccessibilityHelper.shared.hasAccessibilityPermission {
            showAccessibilityAlert = true
        }
    }
}

#Preview {
    MainView()
        .environmentObject(GroupStore())
}

// MARK: - App Switcher HUD View (Inline for compilation)

struct AppSwitcherHUDView: View {
    let apps: [NSRunningApplication]
    let activeApp: NSRunningApplication
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(apps, id: \.processIdentifier) { app in
                VStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 48))
                            .frame(width: 64, height: 64)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(app.localizedName ?? "App")
                        .font(.caption)
                        .foregroundColor(isAvailable(app) ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(width: 80)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive(app) ? Color.gray.opacity(0.3) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: isActive(app) ? 1 : 0)
                )
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 20)
    }
    
    private func isActive(_ app: NSRunningApplication) -> Bool {
        return app.processIdentifier == activeApp.processIdentifier
    }
    
    private func isAvailable(_ app: NSRunningApplication) -> Bool {
        return !app.isTerminated
    }
}
