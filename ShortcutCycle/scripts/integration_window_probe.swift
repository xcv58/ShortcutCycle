import AppKit
import CoreGraphics
import Foundation

enum ProbeCommand: String {
    case appPath = "app-path"
    case describeRunning = "describe-running"
    case pids
    case running
    case waitVisibleWindow = "wait-visible-window"
}

func writeError(_ message: String) {
    if let data = (message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func runningApplications(bundleIdentifier: String) -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
}

func describeRunningApplications(bundleIdentifier: String) -> [String] {
    runningApplications(bundleIdentifier: bundleIdentifier).map { application in
        let name = application.localizedName ?? bundleIdentifier
        return "\(name) pid=\(application.processIdentifier) active=\(application.isActive) hidden=\(application.isHidden) finishedLaunching=\(application.isFinishedLaunching)"
    }
}

func hasVisibleRegularWindow(bundleIdentifier: String) -> Bool {
    let processIdentifiers = Set(runningApplications(bundleIdentifier: bundleIdentifier).map(\.processIdentifier))
    guard !processIdentifiers.isEmpty else { return false }

    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return false
    }

    return windows.contains { window in
        guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
              processIdentifiers.contains(ownerPID) else {
            return false
        }

        let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
        guard layer == 0 else { return false }

        let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1.0
        guard alpha > 0.01 else { return false }

        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else {
            return false
        }

        return width > 1.0 && height > 1.0
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3,
      let command = ProbeCommand(rawValue: arguments[1]) else {
    writeError("Usage: integration_window_probe.swift <app-path|describe-running|pids|running|wait-visible-window> <bundle-id> [timeout-seconds]")
    exit(64)
}

let bundleIdentifier = arguments[2]

switch command {
case .appPath:
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        exit(1)
    }

    print(url.path)
    exit(0)
case .describeRunning:
    let descriptions = describeRunningApplications(bundleIdentifier: bundleIdentifier)
    guard !descriptions.isEmpty else {
        exit(1)
    }

    for description in descriptions {
        print(description)
    }
    exit(0)
case .pids:
    let pids = runningApplications(bundleIdentifier: bundleIdentifier).map(\.processIdentifier)
    guard !pids.isEmpty else {
        exit(1)
    }

    for pid in pids {
        print(pid)
    }
    exit(0)
case .running:
    exit(runningApplications(bundleIdentifier: bundleIdentifier).isEmpty ? 1 : 0)
case .waitVisibleWindow:
    let timeout = arguments.count >= 4 ? (Double(arguments[3]) ?? 15.0) : 15.0
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if hasVisibleRegularWindow(bundleIdentifier: bundleIdentifier) {
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    writeError("Timed out waiting for a visible regular window for \(bundleIdentifier)")
    exit(1)
}
