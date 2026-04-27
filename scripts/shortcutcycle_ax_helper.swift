#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

enum HelperError: Error, CustomStringConvertible {
    case appNotRunning
    case noWindow
    case noSheet
    case rowNotFound(String)
    case backupRowOutOfRange(Int)
    case buttonNotFound(String)
    case tabNotFound(String)
    case scrollAreaNotFound(String)
    case scrollFailed(String)
    case frameUnavailable(String)
    case unsupportedCommand(String)

    var description: String {
        switch self {
        case .appNotRunning:
            return "ShortcutCycle.app is not running"
        case .noWindow:
            return "Could not find a visible ShortcutCycle window"
        case .noSheet:
            return "Could not find an open ShortcutCycle sheet"
        case .rowNotFound(let name):
            return "Could not find sidebar row named '\(name)'"
        case .backupRowOutOfRange(let index):
            return "Backup row index \(index) is out of range"
        case .buttonNotFound(let title):
            return "Could not find button '\(title)'"
        case .tabNotFound(let title):
            return "Could not find tab '\(title)'"
        case .scrollAreaNotFound(let target):
            return "Could not find scroll area '\(target)'"
        case .scrollFailed(let direction):
            return "Could not scroll \(direction)"
        case .frameUnavailable(let target):
            return "Could not resolve frame for '\(target)'"
        case .unsupportedCommand(let command):
            return "Unsupported command '\(command)'"
        }
    }
}

typealias AXElement = AXUIElement

func axAttribute(_ element: AXElement, _ key: String) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    guard result == .success else { return nil }
    return value
}

func elementRole(_ element: AXElement) -> String {
    (axAttribute(element, kAXRoleAttribute) as? String) ?? ""
}

func elementTitle(_ element: AXElement) -> String {
    (axAttribute(element, kAXTitleAttribute) as? String) ?? ""
}

func elementDescription(_ element: AXElement) -> String {
    (axAttribute(element, kAXDescriptionAttribute) as? String) ?? ""
}

func stringValue(_ element: AXElement) -> String? {
    axAttribute(element, kAXValueAttribute) as? String
}

func descendants(of element: AXElement) -> [AXElement] {
    var result: [AXElement] = []
    for key in [kAXChildrenAttribute, kAXRowsAttribute] {
        if let children = axAttribute(element, key) as? [AXElement] {
            for child in children {
                result.append(child)
                result.append(contentsOf: descendants(of: child))
            }
        }
    }
    return result
}

func preferredShortcutCycleApp() throws -> NSRunningApplication {
    let runningApps = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == "com.xcv58.ShortcutCycle"
    }

    if let preferredPath = ProcessInfo.processInfo.environment["SHORTCUTCYCLE_AX_APP_PATH"],
       let app = runningApps.first(where: { $0.bundleURL?.path == preferredPath }) {
        return app
    }

    if let app = runningApps.first(where: { $0.isActive }) {
        return app
    }

    if let app = runningApps.first {
        return app
    }

    throw HelperError.appNotRunning
}

func shortcutCycleWindow() throws -> AXElement {
    let app = try preferredShortcutCycleApp()
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let windows = axAttribute(axApp, kAXWindowsAttribute) as? [AXElement],
          let window = windows.first else {
        throw HelperError.noWindow
    }
    return window
}

func firstOutline(in root: AXElement) -> AXElement? {
    ([root] + descendants(of: root)).first { elementRole($0) == kAXOutlineRole as String }
}

func rowContainsText(_ row: AXElement, target: String) -> Bool {
    let texts = ([row] + descendants(of: row)).compactMap(stringValue)
    return texts.contains(target)
}

func setSelected(_ element: AXElement) -> AXError {
    AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
}

func press(_ element: AXElement) -> AXError {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

func selectGroup(named name: String) throws {
    let row = try groupRow(named: name)
    let result = setSelected(row)
    guard result == .success else {
        throw HelperError.rowNotFound(name)
    }
}

func groupRow(named name: String) throws -> AXElement {
    let window = try shortcutCycleWindow()
    guard let outline = firstOutline(in: window),
          let rows = axAttribute(outline, kAXRowsAttribute) as? [AXElement],
          let row = rows.first(where: { rowContainsText($0, target: name) }) else {
        throw HelperError.rowNotFound(name)
    }
    return row
}

func openSheetIfPresent(in window: AXElement) -> AXElement? {
    ([window] + descendants(of: window)).first { elementRole($0) == kAXSheetRole as String }
}

func selectBackupRow(index: Int) throws {
    let row = try backupRow(index: index)
    let result = setSelected(row)
    guard result == .success else {
        throw HelperError.backupRowOutOfRange(index)
    }
}

func backupRow(index: Int) throws -> AXElement {
    let window = try shortcutCycleWindow()
    guard let sheet = openSheetIfPresent(in: window),
          let outline = firstOutline(in: sheet),
          let rows = axAttribute(outline, kAXRowsAttribute) as? [AXElement] else {
        throw HelperError.noSheet
    }

    let resolvedIndex = index - 1
    guard rows.indices.contains(resolvedIndex) else {
        throw HelperError.backupRowOutOfRange(index)
    }
    return rows[resolvedIndex]
}

func clickButton(named name: String) throws {
    let result = press(try button(named: name))
    guard result == .success else {
        throw HelperError.buttonNotFound(name)
    }
}

func button(named name: String) throws -> AXElement {
    let window = try shortcutCycleWindow()
    let candidates = [window] + descendants(of: window)
    guard let button = candidates.first(where: {
        elementRole($0) == kAXButtonRole as String &&
        (
            elementTitle($0) == name ||
            elementDescription($0) == name ||
            stringValue($0) == name
        )
    }) else {
        throw HelperError.buttonNotFound(name)
    }
    return button
}

func setTab(named name: String) throws {
    let tab = try tab(named: name)
    let result = press(tab)
    guard result == .success else {
        throw HelperError.tabNotFound(name)
    }
}

func tab(named name: String) throws -> AXElement {
    let window = try shortcutCycleWindow()
    let candidates = [window] + descendants(of: window)
    guard let tab = candidates.first(where: {
        elementRole($0) == kAXRadioButtonRole as String &&
        (
            elementTitle($0) == name ||
            elementDescription($0) == name ||
            stringValue($0) == name
        )
    }) else {
        throw HelperError.tabNotFound(name)
    }
    return tab
}

func framePayload(for element: AXElement, target: String) throws -> [String: Double] {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let rawPositionValue = axAttribute(element, kAXPositionAttribute),
          let rawSizeValue = axAttribute(element, kAXSizeAttribute) else {
        throw HelperError.frameUnavailable(target)
    }

    let positionValue = rawPositionValue as! AXValue
    let sizeValue = rawSizeValue as! AXValue
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size) else {
        throw HelperError.frameUnavailable(target)
    }

    let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1, height: 1)
    return [
        "x": Double(position.x),
        "y": Double(position.y),
        "width": Double(size.width),
        "height": Double(size.height),
        "screenX": Double(screenFrame.origin.x),
        "screenY": Double(screenFrame.origin.y),
        "screenWidth": Double(screenFrame.size.width),
        "screenHeight": Double(screenFrame.size.height)
    ]
}

func printFrame(_ element: AXElement, target: String) throws {
    let payload = try framePayload(for: element, target: target)
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func scrollArea(target: String, in window: AXElement) -> AXElement? {
    let scrollAreas = ([window] + descendants(of: window)).filter {
        elementRole($0) == kAXScrollAreaRole as String
    }

    switch target.lowercased() {
    case "first", "window", "general":
        return scrollAreas.first
    case "last", "content", "main":
        return scrollAreas.last
    default:
        return scrollAreas.first
    }
}

func numericValue(_ element: AXElement) -> Double? {
    if let value = axAttribute(element, kAXValueAttribute) as? Double {
        return value
    }
    if let value = axAttribute(element, kAXValueAttribute) as? NSNumber {
        return value.doubleValue
    }
    return nil
}

func scrollBySettingScrollBar(_ area: AXElement, direction: String) -> Bool {
    let scrollBars = descendants(of: area).filter {
        elementRole($0) == kAXScrollBarRole as String
    }
    guard let scrollBar = scrollBars.first else { return false }

    let current = numericValue(scrollBar) ?? 0
    let delta = direction.lowercased() == "up" ? -0.35 : 0.35
    let next = min(1, max(0, current + delta))
    return AXUIElementSetAttributeValue(
        scrollBar,
        kAXValueAttribute as CFString,
        NSNumber(value: next)
    ) == .success
}

func scroll(direction: String, count: Int, target: String) throws {
    let window = try shortcutCycleWindow()
    guard let area = scrollArea(target: target, in: window) else {
        throw HelperError.scrollAreaNotFound(target)
    }

    let action: String
    switch direction.lowercased() {
    case "up":
        action = "AXScrollUp"
    case "down":
        action = "AXScrollDown"
    default:
        throw HelperError.scrollFailed(direction)
    }

    for index in 0..<max(1, count) {
        let result = AXUIElementPerformAction(area, action as CFString)
        if result != .success && !scrollBySettingScrollBar(area, direction: direction) {
            throw HelperError.scrollFailed(direction)
        }
        if index < max(1, count) - 1 {
            Thread.sleep(forTimeInterval: 0.18)
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw HelperError.unsupportedCommand("")
    }

    switch command {
    case "select-group":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try selectGroup(named: arguments[1])
    case "frame-group":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try printFrame(try groupRow(named: arguments[1]), target: arguments[1])
    case "select-backup-row":
        guard arguments.count >= 2, let index = Int(arguments[1]) else {
            throw HelperError.unsupportedCommand(command)
        }
        try selectBackupRow(index: index)
    case "frame-backup-row":
        guard arguments.count >= 2, let index = Int(arguments[1]) else {
            throw HelperError.unsupportedCommand(command)
        }
        try printFrame(try backupRow(index: index), target: arguments[1])
    case "click-button":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try clickButton(named: arguments[1])
    case "frame-button":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try printFrame(try button(named: arguments[1]), target: arguments[1])
    case "set-tab":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try setTab(named: arguments[1])
    case "frame-tab":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        try printFrame(try tab(named: arguments[1]), target: arguments[1])
    case "scroll":
        guard arguments.count >= 2 else { throw HelperError.unsupportedCommand(command) }
        let count = arguments.count >= 3 ? Int(arguments[2]) ?? 1 : 1
        let target = arguments.count >= 4 ? arguments[3] : "first"
        try scroll(direction: arguments[1], count: count, target: target)
    default:
        throw HelperError.unsupportedCommand(command)
    }
} catch let error as HelperError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
