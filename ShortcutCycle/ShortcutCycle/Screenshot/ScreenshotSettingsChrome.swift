#if DEBUG
import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct ScreenshotSettingsWindowChrome<Content: View>: View {
    let selectedLanguage: String
    let selectedTab: ScreenshotSettingsTabsView.Tab
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ScreenshotSettingsTabsView(selectedLanguage: selectedLanguage, selectedTab: selectedTab)
                Spacer()
            }
            .frame(height: 42)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            content()
        }
    }
}

struct ScreenshotSettingsTabsView: View {
    enum Tab {
        case groups
        case general
    }

    let selectedLanguage: String
    let selectedTab: Tab

    var body: some View {
        HStack(spacing: 4) {
            tab("Groups".localized(language: selectedLanguage), isSelected: selectedTab == .groups)
            tab("General".localized(language: selectedLanguage), isSelected: selectedTab == .general)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func tab(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
            )
    }
}

struct ScreenshotGroupSidebar: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme

    let selectedGroupID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.groups) { group in
                        ScreenshotGroupSidebarRow(
                            group: group,
                            isSelected: group.id == selectedGroupID
                        )
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                Label("Add Group", systemImage: "plus")
                    .font(.body)
                Spacer()
            }
            .padding(10)
        }
        .background(SettingsChromePalette.sidebarBackground(for: colorScheme))
    }
}

struct ScreenshotGroupSidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    let group: AppGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if ScreenshotMode.usesSyntheticControls {
                ScreenshotAccentSwitch(isOn: group.isEnabled, size: .mini)
            } else {
                Toggle("", isOn: .constant(group.isEnabled))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                    .controlSize(.mini)
            }

            Image(systemName: "folder.fill")
                .foregroundStyle(group.isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(group.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                if let shortcut = group.shortcutDisplayString {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsChromePalette.chipFill(for: colorScheme))
                        .clipShape(Capsule(style: .continuous))
                } else {
                    Text("No shortcut".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text("\(group.apps.count)")
                .font(colorScheme == .dark ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(SettingsChromePalette.badgeFill(for: colorScheme)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? SettingsChromePalette.neutralHoverFill(for: colorScheme)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? SettingsChromePalette.neutralHoverBorder(for: colorScheme) : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(group.isEnabled ? 1.0 : 0.68)
    }
}
#endif
