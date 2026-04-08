import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

enum SettingsChromePalette {
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .clear
    }

    static func sidebarBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: .underPageBackgroundColor) : .clear
    }

    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.88 : 0.75)
    }

    static func panelBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .separatorColor).opacity(0.18)
            : Color.secondary.opacity(0.08)
    }

    static func inlineFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.76)
            : Color.secondary.opacity(0.10)
    }

    static func chipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.45)
            : Color.gray.opacity(0.20)
    }

    static func badgeFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.40)
            : Color.gray.opacity(0.50)
    }

    static func neutralHoverFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.84)
            : Color.accentColor.opacity(0.10)
    }

    static func neutralHoverBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .separatorColor).opacity(0.24)
            : Color.accentColor.opacity(0.28)
    }

    static func dropZoneFill(for colorScheme: ColorScheme, targeted: Bool) -> Color {
        if targeted {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.10)
        }

        return colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.30)
            : .clear
    }

    static func dropZoneBorder(for colorScheme: ColorScheme, targeted: Bool) -> Color {
        if targeted {
            return colorScheme == .dark
                ? Color.accentColor.opacity(0.58)
                : .accentColor
        }

        return colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.72)
            : Color.gray.opacity(0.30)
    }
}

struct SettingsSectionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(SettingsChromePalette.panelBorder(for: colorScheme))
                .frame(height: 1)
        } else {
            Divider()
        }
    }
}

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme

    /// A deferred-write binding for columnVisibility.
    ///
    /// NSSplitViewController (backing NavigationSplitView) can write to this binding
    /// synchronously during its layout pass when the Groups tab becomes visible after a
    /// tab switch. The new .scrollContentBackground(.hidden) on the sidebar List triggers
    /// that layout re-evaluation. Writing to a @Published property during SwiftUI's
    /// render/commit phase fires objectWillChange synchronously, which AttributeGraph
    /// detects as a cycle. Deferring the write via Task breaks the synchronous path.
    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { store.columnVisibility },
            set: { newValue in
                Task { @MainActor in
                    store.columnVisibility = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
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
                .background(SettingsChromePalette.windowBackground(for: colorScheme))
            }
        }
        .navigationTitle("App Groups".localized(language: selectedLanguage))
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }
}
