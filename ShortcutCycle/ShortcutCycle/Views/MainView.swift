
import SwiftUI

/// Main settings window view with sidebar and detail
struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @State private var showAccessibilityAlert = false
    
    var body: some View {
        TabView {
            GroupSettingsView()
                .tabItem {
                    Label("Groups", systemImage: "rectangle.stack.3.hexagon")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
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
            Text("ShortcutCycle needs accessibility permission to register global keyboard shortcuts and switch between applications.")
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

// MARK: - Subviews (Consolidated)

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    
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
        .navigationTitle("App Groups")
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @AppStorage("showDockIcon") private var showDockIcon = true
    
    var body: some View {
        VStack {
            Text("ShortcutCycle Settings")
                .font(.title)
            
            Spacer()
            
            Form {
                Section {
                    Toggle("Show HUD when switching", isOn: $showHUD)
                    
                    if showHUD {
                        Toggle("Show shortcut in HUD", isOn: $showShortcutInHUD)
                            .padding(.leading)
                    }
                } header: {
                    Text("HUD Settings")
                } footer: {
                    Text("Manage how the Heads-Up Display (HUD) appears when you cycle through applications.")
                }
                
                Section {
                    Toggle("Show Icon in Dock", isOn: $showDockIcon)
                        .toggleStyle(.switch)
                } header: {
                    Text("Application Settings")
                } footer: {
                    Text("Control the visibility of the ShortcutCycle icon in the Dock.")
                }
            }
        }
        .padding()
        .navigationTitle("General")
        .onChange(of: showDockIcon) { newValue in
            if newValue {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .onAppear {
            // Set initial activation policy based on stored value
            if showDockIcon {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - HUD Views

struct AppSwitcherHUDView: View {
    let apps: [NSRunningApplication]
    let activeApp: NSRunningApplication
    let shortcutString: String?
    
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @Environment(\.colorScheme) var colorScheme
    
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
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Adaptive tint based on color scheme
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.3))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // Active App Name
            VStack(spacing: 4) {
                Text(activeApp.localizedName ?? "App")
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundColor(.primary)
                
                if showShortcutInHUD, let shortcut = shortcutString {
                    Text(shortcut)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .padding(40)
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
            .saturation(isActive ? 1.1 : 0.8)
            .opacity(isActive ? 1.0 : 0.7)
            .blur(radius: 0)
            .padding(12)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                        
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 0)
                    }
                }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}
