import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    var body: some View {
        NavigationSplitView(columnVisibility: $store.columnVisibility) {
            GroupListView()
                .frame(minWidth: 220)
        } detail: {
            if let selectedId = store.selectedGroupId {
                GroupEditView(groupId: selectedId)
                    .id(selectedId)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    
                    Text("No Group Selected".localized(language: selectedLanguage))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select a group from the sidebar or create a new one.".localized(language: selectedLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("App Groups".localized(language: selectedLanguage))
    }
}
