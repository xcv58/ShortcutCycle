import Foundation

public enum URLCommandFileValidation {
    public enum ValidationError: Equatable, LocalizedError {
        case emptyPath
        case invalidPath
        case pathOutsideContainer
        case invalidBackupName
        case backupOutsideDirectory
        case backupIndexOutOfRange
        case noBackupsAvailable

        public var errorDescription: String? {
            switch self {
            case .emptyPath:
                return "Path is empty."
            case .invalidPath:
                return "Path must be an absolute file path or file URL."
            case .pathOutsideContainer:
                return "Path must stay inside the app container."
            case .invalidBackupName:
                return "Backup name must be a simple filename without path separators."
            case .backupOutsideDirectory:
                return "Backup name resolves outside the backup directory."
            case .backupIndexOutOfRange:
                return "Backup index is out of range."
            case .noBackupsAvailable:
                return "No backup files are available."
            }
        }
    }

    public static func normalizedFileURL(
        rawPath: String,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if let candidate = URL(string: path), let scheme = candidate.scheme {
            guard scheme.caseInsensitiveCompare("file") == .orderedSame, candidate.isFileURL else {
                return nil
            }
            return canonicalURL(candidate)
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return canonicalURL(URL(fileURLWithPath: expandedPath))
        }
        return canonicalURL(cwd.appendingPathComponent(expandedPath))
    }

    public static func isDescendant(candidate: URL, root: URL) -> Bool {
        let normalizedRoot = canonicalURL(root)
        let normalizedCandidate = canonicalURL(candidate)
        let rootPath = normalizedRoot.path
        let candidatePath = normalizedCandidate.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    public static func validateImportURL(
        rawPath: String,
        home: URL,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> Result<URL, ValidationError> {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyPath) }
        guard let candidate = normalizedFileURL(rawPath: trimmed, cwd: cwd) else {
            return .failure(.invalidPath)
        }
        guard isDescendant(candidate: candidate, root: home) else {
            return .failure(.pathOutsideContainer)
        }
        return .success(candidate)
    }

    public static func validateBackupName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else { return false }
        guard !trimmed.contains("..") else { return false }
        return true
    }

    public static func resolveBackupURL(
        target: URLBackupTarget?,
        backupDirectory: URL,
        home: URL,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> Result<URL, ValidationError> {
        switch target {
        case .path(let rawPath):
            return validateImportURL(rawPath: rawPath, home: home, cwd: cwd)
        case .name(let rawName):
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard validateBackupName(name) else { return .failure(.invalidBackupName) }
            let candidate = canonicalURL(backupDirectory.appendingPathComponent(name, isDirectory: false))
            guard isDescendant(candidate: candidate, root: backupDirectory) else {
                return .failure(.backupOutsideDirectory)
            }
            return .success(candidate)
        case .index(let index):
            let backups = sortedBackupFiles(in: backupDirectory)
            let resolvedIndex = index - 1
            guard backups.indices.contains(resolvedIndex) else {
                return .failure(.backupIndexOutOfRange)
            }
            return .success(backups[resolvedIndex])
        case nil:
            guard let latest = sortedBackupFiles(in: backupDirectory).first else {
                return .failure(.noBackupsAvailable)
            }
            return .success(latest)
        }
    }

    private static func sortedBackupFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return leftDate > rightDate
            }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
