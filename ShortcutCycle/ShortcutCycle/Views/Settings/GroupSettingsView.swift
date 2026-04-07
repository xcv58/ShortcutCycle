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
                ContentUnavailableView {
                    Label("No Group Selected".localized(language: selectedLanguage), systemImage: "folder")
                } description: {
                    Text("Select a group from the sidebar or create a new one.".localized(language: selectedLanguage))
                } actions: {
                    if store.groups.isEmpty {
                        Button("Add Group".localized(language: selectedLanguage)) {
                            store.columnVisibility = .all
                            store.isAddingGroup = true
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("App Groups".localized(language: selectedLanguage))
    }
}
