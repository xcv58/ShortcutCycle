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
        VStack(spacing: 20) {
            // Icons Row
            HStack(spacing: 20) {
                ForEach(apps, id: \.processIdentifier) { app in
                    if let icon = app.icon {
                        HUDItemView(icon: icon, isActive: isActive(app))
                    }
                }
            }
            .padding(.horizontal, 32) // Increased horizontal padding
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous) // Reduced curve (was Capsule)
                    .fill(.ultraThinMaterial)
                    // Add a dark tint for better contrast on any wallpaper
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.3))) 
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            
            // Active App Name (Floating below)
            Text(activeApp.localizedName ?? "App")
                .font(.title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(Capsule().fill(Color.black.opacity(0.2)))
                )
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .padding(40) // Padding around the whole HUD to allow shadows/glows to breathe
    }
    
    private func isActive(_ app: NSRunningApplication) -> Bool {
        return app.processIdentifier == activeApp.processIdentifier
    }
}

struct HUDItemView: View {
    let icon: NSImage
    let isActive: Bool
    
    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72, height: 72)
            .scaleEffect(isActive ? 1.15 : 1.0)
            .saturation(isActive ? 1.1 : 0.8) // Dim inactive apps slightly
            .opacity(isActive ? 1.0 : 0.7)
            .blur(radius: 0)
            .padding(12)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            .shadow(color: .white.opacity(0.5), radius: 8, x: 0, y: 0) // Glow effect
                    }
                }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}
