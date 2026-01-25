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
