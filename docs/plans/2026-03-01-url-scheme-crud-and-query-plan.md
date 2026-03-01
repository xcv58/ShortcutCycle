# URL Scheme CRUD & Query Commands Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 8 new URL commands (create-group, delete-group, rename-group, reorder-group, add-app, remove-app, list-groups, get-group) to the `shortcutcycle://` URL scheme.

**Architecture:** All 8 commands follow the same pattern as existing URL commands: parse in `URLScheme.swift` (ShortcutCycleCore), route in `ShortcutCycleApp.swift` (executable target). Query commands write JSON to a file. Tests go in `ShortcutCycleTests.swift`.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, SPM

---

### Task 1: Add new command cases to `ShortcutCycleURLCommand` enum

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/Models/URLScheme.swift:22-36`

**Step 1: Add the 8 new cases**

Add after the existing `restoreBackup` case (line 35):

```swift
public enum ShortcutCycleURLCommand: Equatable {
    // ... existing cases ...
    case restoreBackup(URLBackupTarget?)
    // New: Group CRUD
    case createGroup(name: String)
    case deleteGroup(URLGroupTarget)
    case renameGroup(URLGroupTarget, newName: String)
    case reorderGroup(URLGroupTarget, position: Int)
    // New: App management
    case addApp(URLGroupTarget, bundleId: String)
    case removeApp(URLGroupTarget, bundleId: String)
    // New: Query
    case listGroups(output: String)
    case getGroup(URLGroupTarget, output: String)
}
```

**Step 2: Run tests to verify existing tests still pass**

Run: `cd ShortcutCycle && swift test`
Expected: All 321 tests pass (adding enum cases is additive, no breakage)

**Step 3: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/Models/URLScheme.swift
git commit -m "feat: add URL command cases for group CRUD, app management, and query"
```

---

### Task 2: Add parser logic for Group CRUD commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/Models/URLScheme.swift:51-94` (the `switch action` block in `parse()`)
- Test: `ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift`

**Step 1: Write failing tests for create-group, delete-group, rename-group, reorder-group parsing**

Add to `ShortcutCycleTests.swift` after the existing URL parser tests:

```swift
// MARK: - URL Parser: Group CRUD

func testParseCreateGroupURL() {
    let url = URL(string: "shortcutcycle://create-group?name=Editors")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .createGroup(name: "Editors"))
}

func testParseCreateGroupEmptyNameReturnsNil() {
    let url = URL(string: "shortcutcycle://create-group?name=")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}

func testParseCreateGroupNoNameReturnsNil() {
    let url = URL(string: "shortcutcycle://create-group")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}

func testParseDeleteGroupURL() {
    let url = URL(string: "shortcutcycle://delete-group?group=Browsers")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .deleteGroup(.name("Browsers")))
}

func testParseDeleteGroupRequiresTarget() {
    let url = URL(string: "shortcutcycle://delete-group")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}

func testParseRenameGroupURL() {
    let url = URL(string: "shortcutcycle://rename-group?group=Browsers&newName=Web")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .renameGroup(.name("Browsers"), newName: "Web"))
}

func testParseRenameGroupToAliasURL() {
    let url = URL(string: "shortcutcycle://rename-group?group=Browsers&to=Web")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .renameGroup(.name("Browsers"), newName: "Web"))
}

func testParseRenameGroupRequiresNewName() {
    let url = URL(string: "shortcutcycle://rename-group?group=Browsers")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}

func testParseReorderGroupURL() {
    let url = URL(string: "shortcutcycle://reorder-group?group=Browsers&position=1")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .reorderGroup(.name("Browsers"), position: 1))
}

func testParseReorderGroupToAliasURL() {
    let url = URL(string: "shortcutcycle://reorder-group?group=Browsers&to=2")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .reorderGroup(.name("Browsers"), position: 2))
}

func testParseReorderGroupRequiresPosition() {
    let url = URL(string: "shortcutcycle://reorder-group?group=Browsers")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}
```

**Step 2: Run tests to verify they fail**

Run: `cd ShortcutCycle && swift test`
Expected: New tests fail (parser doesn't handle these actions yet)

**Step 3: Implement parser cases**

In `URLScheme.swift`, add a helper for parsing the "newName" / "to" parameter, then add cases in the `switch action` block.

Add helper method after existing `parseBackupTarget`:

```swift
private static func parseNewName(from query: [String: String]) -> String? {
    let raw = (query["newname"] ?? query["to"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw, !raw.isEmpty else { return nil }
    return raw
}

private static func parsePosition(from query: [String: String]) -> Int? {
    let raw = query["position"] ?? query["to"]
    guard let raw, let pos = Int(raw), pos > 0 else { return nil }
    return pos
}
```

Add parser cases in the `switch action` block (before the `default` case):

```swift
case "create-group":
    let name = (query["name"] ?? query["group"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let name, !name.isEmpty else { return nil }
    return .createGroup(name: name)
case "delete-group":
    guard let target else { return nil }
    return .deleteGroup(target)
case "rename-group":
    guard let target, let newName = parseNewName(from: query) else { return nil }
    return .renameGroup(target, newName: newName)
case "reorder-group":
    guard let target, let position = parsePosition(from: query) else { return nil }
    return .reorderGroup(target, position: position)
```

**Note on `rename-group` and `reorder-group` `to=` alias conflict:** Both commands accept `to=` but expect different value types (string vs int). `parseNewName` reads `newname` first, then `to`. `parsePosition` reads `position` first, then `to`. Since these are separate commands, there's no conflict — `rename-group?to=Web` returns a string, `reorder-group?to=2` returns an int.

**Note on `create-group` name parameter:** The `parseGroupTarget` helper reads `group` and `name` query params for group targeting. For `create-group`, we want the `name` param to be the new group name, not a group target. Since `create-group` doesn't use `target`, we read `name` directly from query dict (also accepting `group` as alias).

**Step 4: Run tests to verify they pass**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass including the 11 new ones

**Step 5: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/Models/URLScheme.swift ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift
git commit -m "feat: parse group CRUD URL commands (create, delete, rename, reorder)"
```

---

### Task 3: Add parser logic for App Management commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/Models/URLScheme.swift`
- Test: `ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift`

**Step 1: Write failing tests**

```swift
// MARK: - URL Parser: App Management

func testParseAddAppURL() {
    let url = URL(string: "shortcutcycle://add-app?group=Browsers&bundleId=com.google.Chrome")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
}

func testParseAddAppWithAppAlias() {
    let url = URL(string: "shortcutcycle://add-app?group=Browsers&app=com.google.Chrome")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
}

func testParseAddAppWithBundleAlias() {
    let url = URL(string: "shortcutcycle://add-app?group=Browsers&bundle=com.google.Chrome")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
}

func testParseAddAppRequiresGroupAndBundleId() {
    let noGroup = URL(string: "shortcutcycle://add-app?bundleId=com.google.Chrome")!
    XCTAssertNil(ShortcutCycleURLParser.parse(noGroup))

    let noBundleId = URL(string: "shortcutcycle://add-app?group=Browsers")!
    XCTAssertNil(ShortcutCycleURLParser.parse(noBundleId))
}

func testParseRemoveAppURL() {
    let url = URL(string: "shortcutcycle://remove-app?group=Browsers&bundleId=com.google.Chrome")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .removeApp(.name("Browsers"), bundleId: "com.google.Chrome"))
}

func testParseRemoveAppRequiresGroupAndBundleId() {
    let noGroup = URL(string: "shortcutcycle://remove-app?bundleId=com.google.Chrome")!
    XCTAssertNil(ShortcutCycleURLParser.parse(noGroup))

    let noBundleId = URL(string: "shortcutcycle://remove-app?group=Browsers")!
    XCTAssertNil(ShortcutCycleURLParser.parse(noBundleId))
}
```

**Step 2: Run tests to verify they fail**

Run: `cd ShortcutCycle && swift test`
Expected: 6 new tests fail

**Step 3: Implement parser cases**

Add helper:

```swift
private static func parseBundleId(from query: [String: String]) -> String? {
    let raw = (query["bundleid"] ?? query["app"] ?? query["bundle"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw, !raw.isEmpty else { return nil }
    return raw
}
```

Add cases in the `switch action` block:

```swift
case "add-app":
    guard let target, let bundleId = parseBundleId(from: query) else { return nil }
    return .addApp(target, bundleId: bundleId)
case "remove-app":
    guard let target, let bundleId = parseBundleId(from: query) else { return nil }
    return .removeApp(target, bundleId: bundleId)
```

**Step 4: Run tests to verify they pass**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/Models/URLScheme.swift ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift
git commit -m "feat: parse add-app and remove-app URL commands"
```

---

### Task 4: Add parser logic for Query commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/Models/URLScheme.swift`
- Test: `ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift`

**Step 1: Write failing tests**

```swift
// MARK: - URL Parser: Query Commands

func testParseListGroupsURL() {
    let url = URL(string: "shortcutcycle://list-groups")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .listGroups(output: "/tmp/shortcutcycle-result.json"))
}

func testParseListGroupsWithOutputURL() {
    let url = URL(string: "shortcutcycle://list-groups?output=/tmp/groups.json")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .listGroups(output: "/tmp/groups.json"))
}

func testParseGetGroupURL() {
    let url = URL(string: "shortcutcycle://get-group?group=Browsers")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .getGroup(.name("Browsers"), output: "/tmp/shortcutcycle-result.json"))
}

func testParseGetGroupWithOutputURL() {
    let url = URL(string: "shortcutcycle://get-group?group=Browsers&output=/tmp/detail.json")!
    XCTAssertEqual(ShortcutCycleURLParser.parse(url), .getGroup(.name("Browsers"), output: "/tmp/detail.json"))
}

func testParseGetGroupRequiresTarget() {
    let url = URL(string: "shortcutcycle://get-group")!
    XCTAssertNil(ShortcutCycleURLParser.parse(url))
}
```

**Step 2: Run tests to verify they fail**

Run: `cd ShortcutCycle && swift test`
Expected: 5 new tests fail

**Step 3: Implement parser cases**

Add a constant and helper:

```swift
public static let defaultQueryOutputPath = "/tmp/shortcutcycle-result.json"

private static func parseOutputPath(from query: [String: String]) -> String {
    let raw = query["output"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let raw, !raw.isEmpty { return raw }
    return defaultQueryOutputPath
}
```

Add cases in the `switch action` block:

```swift
case "list-groups":
    return .listGroups(output: parseOutputPath(from: query))
case "get-group":
    guard let target else { return nil }
    return .getGroup(target, output: parseOutputPath(from: query))
```

**Step 4: Run tests to verify they pass**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/Models/URLScheme.swift ShortcutCycle/ShortcutCycleTests/ShortcutCycleTests.swift
git commit -m "feat: parse list-groups and get-group query URL commands"
```

---

### Task 5: Add router logic for Group CRUD commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift` (the `switch command` block in `ShortcutCycleURLRouter.handle()`)

**Step 1: Add routing for create-group, delete-group, rename-group, reorder-group**

In the `switch command` block in `ShortcutCycleURLRouter.handle()`, add after the existing `restoreBackup` case:

```swift
case .createGroup(let name):
    _ = store.addGroup(name: name)
    NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
case .deleteGroup(let target):
    guard let group = resolveGroup(target, in: store) else { return }
    let alert = NSAlert()
    alert.messageText = "Delete '\(group.name)'?"
    alert.informativeText = "This will permanently remove the group and its shortcut."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    store.deleteGroup(group)
case .renameGroup(let target, let newName):
    guard var group = resolveGroup(target, in: store) else { return }
    group.name = newName
    store.updateGroup(group)
case .reorderGroup(let target, let position):
    guard let group = resolveGroup(target, in: store) else { return }
    guard let currentIndex = store.groups.firstIndex(where: { $0.id == group.id }) else { return }
    let clampedDestination = min(max(position - 1, 0), store.groups.count - 1)
    // moveGroups uses Swift's Array.move(fromOffsets:toOffset:) convention
    let toOffset = clampedDestination > currentIndex ? clampedDestination + 1 : clampedDestination
    store.moveGroups(from: IndexSet(integer: currentIndex), to: toOffset)
```

**Step 2: Run tests to verify nothing breaks**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass (router is in executable target, not tested directly)

**Step 3: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift
git commit -m "feat: route group CRUD URL commands (create, delete, rename, reorder)"
```

---

### Task 6: Add router logic for App Management commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift`

**Step 1: Add routing for add-app and remove-app**

`add-app` needs to resolve a bundleId to an `AppItem`. Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` to find the app, then `AppItem.from(appURL:)` to create the item. If the app isn't installed, fail silently.

`remove-app` finds the app in the group by bundleIdentifier and removes it.

```swift
case .addApp(let target, let bundleId):
    guard let group = resolveGroup(target, in: store) else { return }
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
          let appItem = AppItem.from(appURL: appURL) else {
        return
    }
    store.addApp(appItem, to: group.id)
case .removeApp(let target, let bundleId):
    guard let group = resolveGroup(target, in: store) else { return }
    guard let appItem = group.apps.first(where: { $0.bundleIdentifier == bundleId }) else { return }
    store.removeApp(appItem, from: group.id)
```

**Step 2: Run tests**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift
git commit -m "feat: route add-app and remove-app URL commands"
```

---

### Task 7: Add router logic for Query commands

**Files:**
- Modify: `ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift`

**Step 1: Add a helper to write JSON query results to a file**

Add a private helper in `ShortcutCycleURLRouter`:

```swift
private static func writeQueryResult(_ data: Any, command: String, to outputPath: String) {
    let result: [String: Any] = [
        "command": command,
        "success": true,
        "data": data
    ]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
    try? jsonData.write(to: url, options: .atomic)
}
```

**Step 2: Add routing for list-groups and get-group**

```swift
case .listGroups(let output):
    let groupsData = store.groups.enumerated().map { index, group in
        [
            "id": group.id.uuidString,
            "name": group.name,
            "isEnabled": group.isEnabled,
            "appCount": group.apps.count,
            "index": index + 1
        ] as [String: Any]
    }
    writeQueryResult(groupsData, command: "list-groups", to: output)
case .getGroup(let target, let output):
    guard let group = resolveGroup(target, in: store) else { return }
    let appsData = group.apps.map { app in
        [
            "bundleId": app.bundleIdentifier,
            "name": app.name
        ]
    }
    let groupData: [String: Any] = [
        "id": group.id.uuidString,
        "name": group.name,
        "isEnabled": group.isEnabled,
        "apps": appsData
    ]
    writeQueryResult(groupData, command: "get-group", to: output)
```

**Step 3: Run tests**

Run: `cd ShortcutCycle && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add ShortcutCycle/ShortcutCycle/ShortcutCycleApp.swift
git commit -m "feat: route list-groups and get-group query URL commands"
```

---

### Task 8: Update URL_SCHEME.md documentation

**Files:**
- Modify: `URL_SCHEME.md`

**Step 1: Add documentation for all 8 new commands**

Add new sections after existing command docs for:
- Group CRUD: `create-group`, `delete-group`, `rename-group`, `reorder-group`
- App management: `add-app`, `remove-app`
- Query: `list-groups`, `get-group` (with output format examples)

Keep the same formatting style as existing docs. Include examples.

**Step 2: Commit**

```bash
git add URL_SCHEME.md
git commit -m "docs: add CRUD and query commands to URL scheme reference"
```

---

### Task 9: Manual smoke test

**Step 1: Build and run the app**

```bash
cd ShortcutCycle && swift build
```

Then launch the built app.

**Step 2: Test group CRUD**

```bash
open "shortcutcycle://create-group?name=TestGroup"
open "shortcutcycle://rename-group?group=TestGroup&to=RenamedGroup"
open "shortcutcycle://reorder-group?group=RenamedGroup&position=1"
open "shortcutcycle://delete-group?group=RenamedGroup"
```

**Step 3: Test app management**

```bash
open "shortcutcycle://create-group?name=TestApps"
open "shortcutcycle://add-app?group=TestApps&bundleId=com.apple.Safari"
open "shortcutcycle://add-app?group=TestApps&bundleId=com.apple.finder"
open "shortcutcycle://remove-app?group=TestApps&bundleId=com.apple.finder"
```

**Step 4: Test queries**

```bash
open "shortcutcycle://list-groups"
sleep 0.5
cat /tmp/shortcutcycle-result.json | python3 -m json.tool

open "shortcutcycle://get-group?group=TestApps&output=/tmp/testapps.json"
sleep 0.5
cat /tmp/testapps.json | python3 -m json.tool
```

**Step 5: Clean up test group**

```bash
open "shortcutcycle://delete-group?group=TestApps"
```
