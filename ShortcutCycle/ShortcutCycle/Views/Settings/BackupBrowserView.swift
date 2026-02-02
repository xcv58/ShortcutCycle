import SwiftUI

/// A file entry representing a backup on disk
struct BackupFile: Identifiable, Equatable {
    let id: URL
    let url: URL
    let date: Date
    let displayName: String
    let isValid: Bool

    static func == (lhs: BackupFile, rhs: BackupFile) -> Bool {
        lhs.url == rhs.url
    }
}

/// NSViewRepresentable to anchor the NSSharingServicePicker
struct SharePickerAnchor: NSViewRepresentable {
    let url: URL
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            DispatchQueue.main.async {
                let picker = NSSharingServicePicker(items: [url])
                picker.delegate = context.coordinator
                picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
                isPresented = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, NSSharingServicePickerDelegate {}
}

struct BackupBrowserView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    @State private var backupFiles: [BackupFile] = []
    @State private var invalidSelection = false
    @State private var selectedID: URL? = nil         // "After" (primary)
    @State private var compareID: URL? = nil          // "Before" (comparison)
    @State private var selectedExport: SettingsExport?
    @State private var compareExport: SettingsExport?
    @State private var diff: BackupDiff?
    @State private var showRestoreConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showSharePicker = false

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Index helpers

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return backupFiles.firstIndex(where: { $0.id == id })
    }

    private var compareIndex: Int? {
        guard let id = compareID else { return nil }
        return backupFiles.firstIndex(where: { $0.id == id })
    }

    private func selectedFile() -> BackupFile? {
        guard let idx = selectedIndex else { return nil }
        return backupFiles[idx]
    }

    private func compareFile() -> BackupFile? {
        guard let idx = compareIndex else { return nil }
        return backupFiles[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Automatic Backups".localized(language: selectedLanguage))
                    .font(.headline)
                Spacer()
                Button("Done".localized(language: selectedLanguage)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Main content
            HSplitView {
                // Left: backup list
                sidebarView
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

                // Right: preview + diff
                detailView
                    .frame(minWidth: 350, idealWidth: 450)
            }
        }
        .frame(minWidth: 650, minHeight: 450)
        .frame(idealWidth: 700, idealHeight: 500)
        .onAppear { loadBackupFiles() }
        .alert("Restore Backup?".localized(language: selectedLanguage), isPresented: $showRestoreConfirmation) {
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {}
            Button("Restore".localized(language: selectedLanguage), role: .destructive) { performRestore() }
        } message: {
            Text("This will replace all current groups and settings with the selected backup. This action cannot be undone.".localized(language: selectedLanguage))
        }
        .alert("Delete Backup?".localized(language: selectedLanguage), isPresented: $showDeleteConfirmation) {
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {}
            Button("Delete".localized(language: selectedLanguage), role: .destructive) { performDelete() }
        } message: {
            Text("This backup file will be permanently deleted.".localized(language: selectedLanguage))
        }
    }

    // MARK: - Sidebar

    private var sidebarSelection: Binding<URL?> {
        Binding<URL?>(
            get: { selectedID },
            set: { newID in
                guard let newID, let idx = backupFiles.firstIndex(where: { $0.id == newID }) else { return }
                if NSEvent.modifierFlags.contains(.option), newID != selectedID {
                    setCompareBackup(at: idx)
                } else {
                    selectBackup(at: idx)
                }
            }
        )
    }

    @ViewBuilder
    private func sidebarRow(for file: BackupFile) -> some View {
        HStack(spacing: 6) {
            if file.id == compareID {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(file.displayName)
                        .font(.callout.weight(file.id == selectedID ? .semibold : .regular))
                    if !file.isValid {
                        Text("(invalid)".localized(language: selectedLanguage))
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .opacity(file.isValid ? 1.0 : 0.5)
            }
        }
        .tag(file.id)
        .listRowBackground(
            file.id == compareID ? Color.orange.opacity(0.15) : Color.clear
        )
        .listRowSeparator(.visible)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: sidebarSelection) {
                ForEach(backupFiles) { file in
                    sidebarRow(for: file)
                }
            }
            .listStyle(.sidebar)

            Text("⌥-click to compare with a different backup".localized(language: selectedLanguage))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            Divider()

            HStack {
                Button(action: openBackupFolder) {
                    Label("Open Backup Folder".localized(language: selectedLanguage), systemImage: "folder")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Delete".localized(language: selectedLanguage), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
            }
            .padding(8)
        }
    }

    // MARK: - Detail

    private var detailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let export = selectedExport, let file = selectedFile() {
                    previewSection(export: export, file: file)
                }

                if let diff = diff, let cFile = compareFile() {
                    diffSection(diff: diff, compareFile: cFile)
                }

                if invalidSelection {
                    Text("This backup file is invalid or corrupted.".localized(language: selectedLanguage))
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedExport == nil {
                    ContentUnavailableView("No Backup Selected".localized(language: selectedLanguage), systemImage: "doc.text", description: Text("Select a backup from the sidebar to preview its contents.".localized(language: selectedLanguage)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if let file = selectedFile(), selectedExport != nil {
                HStack(spacing: 8) {
                    Button {
                        showSharePicker = true
                    } label: {
                        Label("Share".localized(language: selectedLanguage), systemImage: "square.and.arrow.up")
                    }
                    .background(SharePickerAnchor(url: file.url, isPresented: $showSharePicker))

                    Button("Restore".localized(language: selectedLanguage)) { showRestoreConfirmation = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }

    private func previewSection(export: SettingsExport, file: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\("Preview:".localized(language: selectedLanguage)) \(file.displayName)")
                .font(.title3.weight(.semibold))

            let totalApps = export.groups.reduce(0) { $0 + $1.apps.count }
            Text("\(export.groups.count) Groups · \(totalApps) Apps")
                .foregroundColor(.secondary)

            ForEach(export.groups) { group in
                HStack(spacing: 4) {
                    Text(group.name + ":")
                        .fontWeight(.medium)
                    Text(group.apps.map(\.name).joined(separator: ", "))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .font(.callout)
            }

            if let settings = export.settings {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings".localized(language: selectedLanguage)).font(.caption.weight(.medium)).foregroundColor(.secondary)
                    Text("HUD: \(settings.showHUD ? "on" : "off"), Theme: \(settings.appTheme ?? "system"), Language: \(settings.selectedLanguage ?? "system")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func diffSection(diff: BackupDiff, compareFile: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Text("Changes from".localized(language: selectedLanguage))
                    .font(.title3.weight(.semibold))
                Picker("", selection: Binding<URL?>(
                    get: { compareID },
                    set: { newID in
                        if let newID, let idx = backupFiles.firstIndex(where: { $0.id == newID }) {
                            setCompareBackup(at: idx)
                        }
                    }
                )) {
                    ForEach(backupFiles) { file in
                        Text(file.displayName).tag(Optional(file.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            if !diff.hasChanges {
                Text("No changes".localized(language: selectedLanguage))
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Group diffs
            let changedGroups = diff.groupDiffs.filter { $0.status != .unchanged }
            if !changedGroups.isEmpty {
                Text("Groups".localized(language: selectedLanguage)).font(.caption.weight(.medium)).foregroundColor(.secondary)
                ForEach(changedGroups) { gd in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            statusIcon(gd.status)
                            Text(gd.groupName)
                                .fontWeight(.medium)
                            Text("(\(statusLabel(gd.status)))")
                                .foregroundColor(statusColor(gd.status))
                                .font(.caption)
                        }
                        let changedApps = gd.appChanges.filter { $0.status != .unchanged }
                        ForEach(changedApps) { ac in
                            HStack(spacing: 4) {
                                statusIcon(ac.status)
                                Text(ac.appName)
                                Text("(\(statusLabel(ac.status)))")
                                    .foregroundColor(statusColor(ac.status))
                                    .font(.caption)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
            }

            // Setting diffs
            if !diff.settingChanges.isEmpty {
                Text("Settings".localized(language: selectedLanguage)).font(.caption.weight(.medium)).foregroundColor(.secondary)
                ForEach(diff.settingChanges) { sc in
                    HStack(spacing: 4) {
                        Text(sc.key + ":")
                            .fontWeight(.medium)
                        Text(sc.oldValue)
                            .foregroundColor(.red)
                            .strikethrough()
                        Text("→")
                        Text(sc.newValue)
                            .foregroundColor(.green)
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusIcon(_ status: DiffStatus) -> some View {
        switch status {
        case .added:   return Text("+").foregroundColor(.green).fontWeight(.bold)
        case .removed: return Text("−").foregroundColor(.red).fontWeight(.bold)
        case .modified: return Text("~").foregroundColor(.orange).fontWeight(.bold)
        case .unchanged: return Text(" ").fontWeight(.bold)
        }
    }

    private func statusLabel(_ status: DiffStatus) -> String {
        switch status {
        case .added: return "added".localized(language: selectedLanguage)
        case .removed: return "removed".localized(language: selectedLanguage)
        case .modified: return "modified".localized(language: selectedLanguage)
        case .unchanged: return "unchanged".localized(language: selectedLanguage)
        }
    }

    private func statusColor(_ status: DiffStatus) -> Color {
        switch status {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .unchanged: return .secondary
        }
    }

    // MARK: - Data Loading

    private func loadBackupFiles() {
        let dir = store.backupDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        backupFiles = files
            .filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            .compactMap { url -> BackupFile? in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let name = Self.displayDateFormatter.string(from: date)
                let valid: Bool
                if let data = try? Data(contentsOf: url) {
                    switch SettingsExport.validate(data: data) {
                    case .success: valid = true
                    case .failure: valid = false
                    }
                } else {
                    valid = false
                }
                return BackupFile(id: url, url: url, date: date, displayName: name, isValid: valid)
            }
            .sorted { $0.date > $1.date }

        // Auto-select latest
        if !backupFiles.isEmpty {
            selectBackup(at: 0)
        }
    }

    private func selectBackup(at index: Int) {
        selectedID = backupFiles[index].id
        compareID = index + 1 < backupFiles.count ? backupFiles[index + 1].id : nil

        // Load selected export
        selectedExport = loadExport(at: index)
        invalidSelection = selectedExport == nil && index < backupFiles.count

        // Load compare export and compute diff
        if let cIdx = compareIndex {
            compareExport = loadExport(at: cIdx)
            if let sel = selectedExport, let cmp = compareExport {
                diff = BackupDiff.compute(before: cmp, after: sel)
            } else {
                diff = nil
            }
        } else {
            compareExport = nil
            diff = nil
        }
    }

    private func setCompareBackup(at index: Int) {
        guard index >= 0, index < backupFiles.count, backupFiles[index].id != selectedID else { return }
        compareID = backupFiles[index].id
        compareExport = loadExport(at: index)
        if let sel = selectedExport, let cmp = compareExport {
            diff = BackupDiff.compute(before: cmp, after: sel)
        } else {
            diff = nil
        }
    }

    private func loadExport(at index: Int) -> SettingsExport? {
        guard index >= 0, index < backupFiles.count else { return nil }
        guard let data = try? Data(contentsOf: backupFiles[index].url) else { return nil }
        switch SettingsExport.validate(data: data) {
        case .success(let export): return export
        case .failure: return nil
        }
    }

    // MARK: - Actions

    private func openBackupFolder() {
        NSWorkspace.shared.open(store.backupDirectory)
    }

    private func performRestore() {
        guard let export = selectedExport else { return }
        store.applyImport(export)
        dismiss()
    }

    private func performDelete() {
        guard let sid = selectedID, let idx = selectedIndex else { return }
        let file = backupFiles[idx]
        try? FileManager.default.removeItem(at: file.url)
        backupFiles.remove(at: idx)
        selectedID = nil
        selectedExport = nil
        compareID = nil
        compareExport = nil
        diff = nil

        // Re-select if possible
        if !backupFiles.isEmpty {
            selectBackup(at: min(idx, backupFiles.count - 1))
        }
    }
}
