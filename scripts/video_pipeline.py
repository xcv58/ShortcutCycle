#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote

import yaml
from PIL import Image, ImageColor, ImageDraw, ImageFilter, ImageFont


SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent
VIDEO_ROOT = REPO_ROOT / "marketing" / "video"
FIXTURES_DIR = VIDEO_ROOT / "fixtures"
PROFILES_DIR = VIDEO_ROOT / "profiles"
SCENES_DIR = VIDEO_ROOT / "scenes"
SETS_DIR = VIDEO_ROOT / "sets"
TEMPLATES_DIR = VIDEO_ROOT / "templates"
VIDEOS_DIR = VIDEO_ROOT / "videos"
ARTIFACTS_ROOT = REPO_ROOT / ".artifacts" / "video"
RAW_DIR = ARTIFACTS_ROOT / "raw"
CARDS_DIR = ARTIFACTS_ROOT / "cards"
RENDERS_DIR = ARTIFACTS_ROOT / "renders"
REPORTS_DIR = ARTIFACTS_ROOT / "reports"
BIN_DIR = ARTIFACTS_ROOT / "bin"
DEFAULT_PROFILE_ID = "default"
DEFAULT_TEMPLATE_BG = "#0A0E15"
FIXED_LAST_MODIFIED = 796_953_600
DEFAULT_REGULAR_FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
DEFAULT_BOLD_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
OVERVIEW_BACKGROUND_PATH = REPO_ROOT / "scripts" / "assets" / "background.jpeg"

KNOWN_APP_BUNDLES = {
    "com.apple.ActivityMonitor": Path("/System/Applications/Utilities/Activity Monitor.app"),
    "com.apple.Chess": Path("/System/Applications/Chess.app"),
    "com.apple.calculator": Path("/System/Applications/Calculator.app"),
    "com.apple.clock": Path("/System/Applications/Clock.app"),
    "com.apple.Console": Path("/System/Applications/Utilities/Console.app"),
    "com.apple.Dictionary": Path("/System/Applications/Dictionary.app"),
    "com.apple.FontBook": Path("/System/Applications/Font Book.app"),
    "com.apple.Image_Capture": Path("/System/Applications/Image Capture.app"),
    "com.apple.Preview": Path("/System/Applications/Preview.app"),
    "com.apple.QuickTimePlayerX": Path("/System/Applications/QuickTime Player.app"),
    "com.apple.ScriptEditor2": Path("/System/Applications/Utilities/Script Editor.app"),
    "com.apple.Terminal": Path("/System/Applications/Utilities/Terminal.app"),
    "com.apple.TV": Path("/System/Applications/TV.app"),
    "com.apple.TextEdit": Path("/System/Applications/TextEdit.app"),
    "com.apple.helpviewer": Path("/System/Applications/Tips.app"),
    "com.apple.news": Path("/System/Applications/News.app"),
    "com.apple.stocks": Path("/System/Applications/Stocks.app"),
    "com.apple.systempreferences": Path("/System/Applications/System Settings.app"),
    "com.apple.weather": Path("/System/Applications/Weather.app"),
}

SYNTHETIC_OVERVIEW_SOURCES: dict[str, dict[str, Any]] = {
    "com.apple.weather": {
        "owner_name": "Weather",
        "bundle_id": "com.apple.weather",
        "launch_app": "Weather",
        "crop_rel": [0.35, 0.30, 0.97, 0.97],
    },
    "com.apple.clock": {
        "owner_name": "Clock",
        "bundle_id": "com.apple.clock",
        "launch_app": "Clock",
    },
    "com.apple.helpviewer": {
        "owner_name": "Tips",
        "bundle_id": "com.apple.helpviewer",
        "launch_app": "Tips",
    },
    "com.apple.calculator": {
        "owner_name": "Calculator",
        "bundle_id": "com.apple.calculator",
        "launch_app": "Calculator",
    },
    "com.apple.stocks": {
        "owner_name": "Stocks",
        "bundle_id": "com.apple.stocks",
        "launch_app": "Stocks",
    },
    "com.apple.news": {
        "owner_name": "News",
        "bundle_id": "com.apple.news",
        "launch_app": "News",
    },
    "com.apple.TV": {
        "owner_name": "TV",
        "bundle_id": "com.apple.TV",
        "launch_app": "TV",
        "crop_rel": [0.18, 0.08, 0.97, 0.90],
    },
    "com.apple.Preview": {
        "owner_name": "Preview",
        "bundle_id": "com.apple.Preview",
        "launch_app": "Preview",
        "crop_rel": [0.04, 0.04, 0.98, 0.98],
    },
    "com.apple.TextEdit": {
        "owner_name": "TextEdit",
        "bundle_id": "com.apple.TextEdit",
        "launch_app": "TextEdit",
    },
    "com.apple.Dictionary": {
        "owner_name": "Dictionary",
        "bundle_id": "com.apple.Dictionary",
        "launch_app": "Dictionary",
    },
    "com.apple.FontBook": {
        "owner_name": "Font Book",
        "bundle_id": "com.apple.FontBook",
        "launch_app": "Font Book",
    },
}

SHORTCUT_KEY_CODES = {
    "1": 18,
    "2": 19,
    "3": 20,
    "4": 21,
    "5": 23,
    "6": 22,
    "7": 26,
    "8": 28,
    "9": 25,
    "0": 29,
}

MODIFIER_KEY_CODES = {
    "command": 55,
    "shift": 56,
    "option": 58,
    "control": 59,
}

MODIFIER_BITS = {
    "command": 256,
    "shift": 512,
    "option": 2048,
    "control": 4096,
}


class PipelineError(RuntimeError):
    pass


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    capture_output: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        capture_output=capture_output,
        check=False,
    )
    if check and result.returncode != 0:
        raise PipelineError(
            f"Command failed ({result.returncode}): {' '.join(command)}\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return result


def ensure_directories() -> None:
    for directory in (RAW_DIR, CARDS_DIR, RENDERS_DIR, REPORTS_DIR, BIN_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def now_run_id() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def require_file(path: Path, description: str) -> Path:
    if not path.is_file():
        raise PipelineError(f"Missing {description}: {path}")
    return path


def require_path(path: Path, description: str) -> Path:
    if not path.exists():
        raise PipelineError(f"Missing {description}: {path}")
    return path


def load_yaml(path: Path) -> dict[str, Any]:
    require_file(path, "manifest")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise PipelineError(f"Expected mapping in {path}")
    return data


def load_profile(profile_id: str) -> dict[str, Any]:
    data = load_yaml(PROFILES_DIR / f"{profile_id}.yaml")
    parent_id = data.get("inherits")
    if not parent_id:
        return data
    parent = load_profile(parent_id)
    merged = dict(parent)
    merged.update(data)
    return merged


def load_scene(scene_id: str) -> dict[str, Any]:
    return load_yaml(SCENES_DIR / f"{scene_id}.yaml")


def load_video(video_id: str) -> dict[str, Any]:
    return load_yaml(VIDEOS_DIR / f"{video_id}.yaml")


def load_template(template_id: str) -> dict[str, Any]:
    return load_yaml(TEMPLATES_DIR / f"{template_id}.yaml")


def load_fixture(fixture_id: str) -> dict[str, Any]:
    return load_yaml(FIXTURES_DIR / f"{fixture_id}.yaml")


def load_set(set_id: str) -> dict[str, Any]:
    return load_yaml(SETS_DIR / f"{set_id}.yaml")


def app_bundle_path(profile: dict[str, Any]) -> Path:
    return require_path(REPO_ROOT / profile["app_bundle_path"], "integration app bundle")


def bundle_id(profile: dict[str, Any]) -> str:
    return str(profile["bundle_id"])


def expand_repo_path(path_value: str) -> Path:
    path = Path(path_value).expanduser()
    if path.is_absolute():
        return path
    return REPO_ROOT / path


def preferences_path(profile: dict[str, Any]) -> Path:
    raw_path = profile.get("preferences_path")
    if not raw_path:
        raise PipelineError("Profile is missing preferences_path for direct fixture seeding")
    return expand_repo_path(str(raw_path))


def output_size(profile: dict[str, Any]) -> tuple[int, int]:
    width, height = profile["output_size"]
    return int(width), int(height)


def frame_rate(profile: dict[str, Any]) -> int:
    return int(profile["frame_rate"])


def raw_scene_path(scene_id: str, run_id: str) -> Path:
    return RAW_DIR / run_id / f"{scene_id}.mp4"


def cards_video_dir(video_id: str, run_id: str) -> Path:
    return CARDS_DIR / run_id / video_id


def render_output_path(video_id: str, run_id: str) -> Path:
    return RENDERS_DIR / run_id / f"{video_id}.mp4"


def report_output_path(video_id: str, run_id: str) -> Path:
    return REPORTS_DIR / run_id / f"{video_id}.json"


def integration_container_root(profile: dict[str, Any]) -> Path:
    return Path.home() / "Library" / "Containers" / bundle_id(profile)


def integration_query_result_path(profile: dict[str, Any]) -> Path:
    return integration_container_root(profile) / "Data" / "tmp" / "shortcutcycle-result.json"


def shortcutcycle_process_count() -> int:
    result = run(["pgrep", "-x", "ShortcutCycle"], capture_output=True, check=False)
    if result.returncode != 0:
        return 0
    return len([line for line in result.stdout.splitlines() if line.strip()])


def quit_integration_app(profile: dict[str, Any]) -> None:
    run(["pkill", "-x", "ShortcutCycle"], capture_output=True, check=False)
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if shortcutcycle_process_count() == 0:
            time.sleep(0.4)
            return
        time.sleep(0.2)

    run(["pkill", "-9", "-x", "ShortcutCycle"], capture_output=True, check=False)
    time.sleep(0.6)


def launch_integration_app(profile: dict[str, Any]) -> None:
    bundle = app_bundle_path(profile)
    run(["open", "-n", str(bundle)], check=True)

    deadline = time.monotonic() + float(profile.get("launch_settle_seconds", 3.0)) + 5.0
    while time.monotonic() < deadline:
        if shortcutcycle_process_count() > 0:
            time.sleep(float(profile.get("launch_settle_seconds", 3.0)))
            return
        time.sleep(0.2)
    raise PipelineError("Timed out waiting for ShortcutCycle to launch")


def shortcut_payload(shortcut: str) -> str:
    parts = shortcut.split("+")
    if len(parts) < 2:
        raise PipelineError(f"Unsupported shortcut format: {shortcut}")

    key = parts[-1]
    modifiers = parts[:-1]
    if key not in SHORTCUT_KEY_CODES:
        raise PipelineError(f"Unsupported shortcut key: {shortcut}")

    carbon_modifiers = 0
    for modifier in modifiers:
        if modifier not in MODIFIER_BITS:
            raise PipelineError(f"Unsupported shortcut modifier: {shortcut}")
        carbon_modifiers |= MODIFIER_BITS[modifier]

    return json.dumps(
        {
            "carbonKeyCode": SHORTCUT_KEY_CODES[key],
            "carbonModifiers": carbon_modifiers,
        },
        separators=(",", ":"),
    )


def prefs_payload_for_fixture(fixture: dict[str, Any]) -> dict[str, Any]:
    settings = fixture.get("settings", {})
    plist: dict[str, Any] = {
        "ShortcutCycle.Groups": json.dumps(
            [
                {
                    "id": group["id"],
                    "name": group["name"],
                    "apps": [
                        {
                            "id": app["id"],
                            "bundleIdentifier": app["bundle_id"],
                            "name": app["name"],
                        }
                        for app in group["apps"]
                    ],
                    "isEnabled": bool(group.get("is_enabled", True)),
                    "openAppIfNeeded": bool(group.get("open_app_if_needed", False)),
                    "lastModified": FIXED_LAST_MODIFIED,
                }
                for group in fixture["groups"]
            ],
            separators=(",", ":"),
        ).encode("utf-8"),
        "showHUD": bool(settings.get("show_hud", True)),
        "showShortcutInHUD": bool(settings.get("show_shortcut_in_hud", True)),
        "selectedLanguage": str(settings.get("language", "system")),
        "appTheme": str(settings.get("appearance", "system")),
        "hasDismissedWelcome": True,
        "hasAutoOpenedWelcomeSettings": True,
    }

    for group in fixture["groups"]:
        plist[f"KeyboardShortcuts_group-{group['id']}"] = shortcut_payload(group["shortcut"])

    return plist


def iso8601_timestamp(timestamp: int) -> str:
    return datetime.utcfromtimestamp(timestamp).strftime("%Y-%m-%dT%H:%M:%SZ")


def settings_export_payload_for_fixture(fixture: dict[str, Any]) -> dict[str, Any]:
    settings = fixture.get("settings", {})
    export_groups: list[dict[str, Any]] = []
    shortcuts: dict[str, dict[str, int]] = {}

    for group in fixture["groups"]:
        export_groups.append(
            {
                "id": group["id"],
                "name": group["name"],
                "apps": [
                    {
                        "id": app["id"],
                        "bundleIdentifier": app["bundle_id"],
                        "name": app["name"],
                    }
                    for app in group["apps"]
                ],
                "isEnabled": bool(group.get("is_enabled", True)),
                "lastModified": iso8601_timestamp(FIXED_LAST_MODIFIED),
                "openAppIfNeeded": bool(group.get("open_app_if_needed", False)),
            }
        )
        shortcuts[group["id"]] = json.loads(shortcut_payload(group["shortcut"]))

    return {
        "version": 3,
        "exportDate": iso8601_timestamp(FIXED_LAST_MODIFIED),
        "groups": export_groups,
        "settings": {
            "showHUD": bool(settings.get("show_hud", True)),
            "showShortcutInHUD": bool(settings.get("show_shortcut_in_hud", True)),
            "selectedLanguage": str(settings.get("language", "system")),
            "appTheme": str(settings.get("appearance", "system")),
        },
        "shortcuts": shortcuts,
    }


def fixture_import_path(profile: dict[str, Any]) -> Path:
    return integration_container_root(profile) / "Data" / "tmp" / "shortcutcycle-fixture.json"


def seed_fixture(profile: dict[str, Any], fixture_id: str) -> None:
    fixture = load_fixture(fixture_id)
    payload = prefs_payload_for_fixture(fixture)
    if profile.get("settings_window_frame"):
        payload["NSWindow Frame settings"] = str(profile["settings_window_frame"])
    destination = preferences_path(profile)
    destination.parent.mkdir(parents=True, exist_ok=True)

    existing: dict[str, Any] = {}
    if destination.exists():
        with destination.open("rb") as handle:
            loaded = plistlib.load(handle)
        if isinstance(loaded, dict):
            existing = dict(loaded)

    for key in list(existing):
        if key.startswith("KeyboardShortcuts_group-"):
            existing.pop(key, None)

    existing.update(payload)

    with tempfile.NamedTemporaryFile("wb", suffix=".plist", delete=False) as handle:
        plistlib.dump(existing, handle, sort_keys=True)
        temp_path = Path(handle.name)

    try:
        shutil.move(str(temp_path), str(destination))
    finally:
        temp_path.unlink(missing_ok=True)

    run(["killall", "cfprefsd"], capture_output=True, check=False)


def open_url(profile: dict[str, Any], url: str) -> None:
    bundle = app_bundle_path(profile)
    subprocess.Popen(
        ["open", "-a", str(bundle), url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def launch_app(bundle_identifier: str) -> None:
    subprocess.Popen(
        ["open", "-b", bundle_identifier],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def open_file(path_value: str, bundle_identifier: str | None = None) -> None:
    path = expand_repo_path(path_value)
    require_file(path, f"automation asset file {path_value}")
    command = ["open"]
    if bundle_identifier:
        command.extend(["-a", application_name(bundle_identifier)])
    command.append(str(path))
    run(command, capture_output=True, check=True)


def application_name(bundle_identifier: str) -> str:
    result = run(
        ["osascript", "-e", f'tell application id "{bundle_identifier}" to get name'],
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def position_front_window(bundle_identifier: str, bounds: list[int]) -> None:
    app_name = application_name(bundle_identifier)
    x, y, width, height = (int(value) for value in bounds)
    wait_for_window(app_name)
    run(
        ["osascript", "-e", f'tell application id "{bundle_identifier}" to activate'],
        capture_output=True,
        check=True,
    )
    helper_path = compile_window_frame_helper()
    result = run(
        [str(helper_path), bundle_identifier, str(x), str(y), str(width), str(height)],
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        return

    run_osascript(
        [
            f'tell application id "{bundle_identifier}" to activate',
            'tell application "System Events"',
            f'tell process "{app_name}"',
            "if (count of windows) is 0 then error number -1728",
            f"set position of window 1 to {{{x}, {y}}}",
            f"try\nset size of window 1 to {{{width}, {height}}}\nend try",
            "end tell",
            "end tell",
        ]
    )


def run_osascript(lines: list[str]) -> None:
    if not lines:
        return
    command = ["osascript"]
    for line in lines:
        command.extend(["-e", line])
    run(command, capture_output=True, check=True)


def hide_other_apps(except_bundle_ids: list[str]) -> None:
    visible_names = sorted({application_name(bundle_id) for bundle_id in except_bundle_ids})
    if not visible_names:
        return

    escaped_names = [name.replace('"', '\\"') for name in visible_names]
    except_list = ", ".join(f'"{name}"' for name in escaped_names)
    run_osascript(
        [
            'tell application "System Events"',
            'set visibleProcNames to name of every application process whose background only is false',
            'repeat with procName in visibleProcNames',
            f'if ({except_list}) does not contain (contents of procName) then',
            'try',
            'set visible of application process (contents of procName) to false',
            'end try',
            'end if',
            'end repeat',
            'end tell',
        ]
    )
    time.sleep(0.3)


def run_prepare_step(step: dict[str, Any]) -> None:
    step_type = str(step["type"])
    if step_type == "sleep":
        time.sleep(float(step["seconds"]))
        return
    if step_type == "activate-app":
        run(
            ["osascript", "-e", f'tell application id "{str(step["bundle_id"])}" to activate'],
            capture_output=True,
            check=True,
        )
        return
    if step_type == "quit-app":
        run(
            ["osascript", "-e", f'tell application id "{str(step["bundle_id"])}" to quit'],
            capture_output=True,
            check=False,
        )
        return
    if step_type == "open-file":
        open_file(str(step["path"]), str(step.get("bundle_id")) if step.get("bundle_id") else None)
        return
    if step_type == "osascript":
        raw_lines = step.get("lines", [])
        if not isinstance(raw_lines, list):
            raise PipelineError("osascript prepare step expects a list of lines")
        run_osascript([str(line) for line in raw_lines])
        return
    if step_type == "hide-other-apps":
        raw_bundle_ids = step.get("except_bundle_ids", [])
        if not isinstance(raw_bundle_ids, list):
            raise PipelineError("hide-other-apps prepare step expects except_bundle_ids list")
        hide_other_apps([str(bundle_id) for bundle_id in raw_bundle_ids])
        return
    raise PipelineError(f"Unsupported prepare step: {step_type}")


def run_prepare_steps(steps: list[dict[str, Any]]) -> None:
    for step in steps:
        run_prepare_step(step)


def stage_windows(scene: dict[str, Any]) -> None:
    bounds = scene.get("window_bounds")
    layouts = scene.get("window_layouts", {})
    if not bounds and not layouts:
        return

    raw_targets = scene.get("window_stage_apps")
    if not isinstance(raw_targets, list) or not raw_targets:
        raw_targets = scene.get("launch_apps", [])
    if not raw_targets and isinstance(layouts, dict):
        raw_targets = list(layouts.keys())

    for bundle_identifier in raw_targets:
        bundle_id_value = str(bundle_identifier)
        resolved_bounds = layouts.get(bundle_id_value, bounds)
        if not resolved_bounds:
            continue
        position_front_window(bundle_id_value, resolved_bounds)
        time.sleep(0.2)

    initial_app = scene.get("initial_frontmost_app")
    if initial_app:
        run(
            ["osascript", "-e", f'tell application id "{str(initial_app)}" to activate'],
            capture_output=True,
            check=True,
        )
        time.sleep(0.3)


def result_file_path(profile: dict[str, Any]) -> Path:
    return integration_query_result_path(profile)


def url_command(profile: dict[str, Any], command: str) -> None:
    open_url(profile, f"shortcutcycle://{command}")


def url_query(profile: dict[str, Any], command: str, *, timeout: float = 5.0) -> dict[str, Any]:
    result_path = result_file_path(profile)
    previous_mtime = result_path.stat().st_mtime if result_path.exists() else 0.0
    url_command(profile, command)

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if result_path.exists():
            current_mtime = result_path.stat().st_mtime
            if current_mtime >= previous_mtime:
                try:
                    payload = json.loads(result_path.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    time.sleep(0.1)
                    continue
                if payload.get("command") == command.split("?", 1)[0]:
                    return payload
        time.sleep(0.15)
    raise PipelineError(f"Timed out waiting for URL query result: {command}")


def setting_url_command(key: str, value: str) -> str:
    return f"set-setting?key={quote(key)}&value={quote(value)}"


def group_selector(group_id: str) -> str:
    return f"id={quote(group_id)}"


def compile_shortcut_helper() -> Path:
    ensure_directories()
    source_path = BIN_DIR / "post_shortcut_sequence.swift"
    binary_path = BIN_DIR / "post_shortcut_sequence"
    source = """import Cocoa
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 7 else {
    fputs("usage: post_shortcut_sequence <modifierName> <modifierKeyCode> <keyCode> <tapCount> <preHoldMicros> <betweenTapMicros> <postHoldMicros>\\n", stderr)
    exit(2)
}

guard
    let modifierKeyCode = Int(arguments[1]),
    let keyCode = Int(arguments[2]),
    let tapCount = Int(arguments[3]),
    let preHoldMicros = UInt32(arguments[4]),
    let betweenTapMicros = UInt32(arguments[5]),
    let postHoldMicros = UInt32(arguments[6])
else {
    fputs("invalid numeric arguments\\n", stderr)
    exit(2)
}

let flags: CGEventFlags
switch arguments[0] {
case "option":
    flags = [.maskAlternate]
case "command":
    flags = [.maskCommand]
case "shift":
    flags = [.maskShift]
case "control":
    flags = [.maskControl]
default:
    fputs("unsupported modifier\\n", stderr)
    exit(2)
}

func post(_ key: CGKeyCode, _ down: Bool, flags: CGEventFlags = []) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else {
        return
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func tap(_ key: CGKeyCode, flags: CGEventFlags) {
    post(key, true, flags: flags)
    usleep(40_000)
    post(key, false, flags: flags)
}

post(CGKeyCode(modifierKeyCode), true, flags: flags)
usleep(preHoldMicros)
for index in 0..<tapCount {
    tap(CGKeyCode(keyCode), flags: flags)
    if index < tapCount - 1 {
        usleep(betweenTapMicros)
    }
}
usleep(postHoldMicros)
post(CGKeyCode(modifierKeyCode), false)
"""
    current_source = source_path.read_text(encoding="utf-8") if source_path.exists() else None
    if current_source != source or not binary_path.exists():
        source_path.write_text(source, encoding="utf-8")
        run(["swiftc", str(source_path), "-o", str(binary_path)], check=True)
    return require_file(binary_path, "shortcut helper binary")


def compile_mouse_helper() -> Path:
    ensure_directories()
    source_path = BIN_DIR / "post_mouse_click.swift"
    binary_path = BIN_DIR / "post_mouse_click"
    source = """import Cocoa
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 5 else {
    fputs("usage: post_mouse_click <x> <y> <moveDurationMicros> <clickHoldMicros> <settleMicros>\\n", stderr)
    exit(2)
}

guard
    let x = Double(arguments[0]),
    let y = Double(arguments[1]),
    let moveDurationMicros = UInt32(arguments[2]),
    let clickHoldMicros = UInt32(arguments[3]),
    let settleMicros = UInt32(arguments[4])
else {
    fputs("invalid numeric arguments\\n", stderr)
    exit(2)
}

let target = CGPoint(x: x, y: y)

func postMove(_ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

func postMouse(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

let start = CGEvent(source: nil)?.location ?? target
let stepCount = max(1, Int(moveDurationMicros / 16_000))
for step in 1...stepCount {
    let progress = Double(step) / Double(stepCount)
    let point = CGPoint(
        x: start.x + (target.x - start.x) * progress,
        y: start.y + (target.y - start.y) * progress
    )
    postMove(point)
    usleep(step == stepCount ? 1_000 : max(1, moveDurationMicros / UInt32(stepCount)))
}

postMouse(.leftMouseDown, target)
usleep(clickHoldMicros)
postMouse(.leftMouseUp, target)
usleep(settleMicros)
"""
    current_source = source_path.read_text(encoding="utf-8") if source_path.exists() else None
    if current_source != source or not binary_path.exists():
        source_path.write_text(source, encoding="utf-8")
        run(["swiftc", str(source_path), "-o", str(binary_path)], check=True)
    return require_file(binary_path, "mouse helper binary")


def compile_key_helper() -> Path:
    ensure_directories()
    source_path = BIN_DIR / "post_key_code.swift"
    binary_path = BIN_DIR / "post_key_code"
    source = """import Cocoa
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3 else {
    fputs("usage: post_key_code <keyCode> <count> <intervalMicros>\\n", stderr)
    exit(2)
}

guard
    let keyCode = Int(arguments[0]),
    let count = Int(arguments[1]),
    let intervalMicros = UInt32(arguments[2])
else {
    fputs("invalid numeric arguments\\n", stderr)
    exit(2)
}

func post(_ down: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

for index in 0..<max(1, count) {
    post(true)
    usleep(40_000)
    post(false)
    if index < count - 1 {
        usleep(intervalMicros)
    }
}
"""
    current_source = source_path.read_text(encoding="utf-8") if source_path.exists() else None
    if current_source != source or not binary_path.exists():
        source_path.write_text(source, encoding="utf-8")
        run(["swiftc", str(source_path), "-o", str(binary_path)], check=True)
    return require_file(binary_path, "key helper binary")


def compile_scroll_helper() -> Path:
    ensure_directories()
    source_path = BIN_DIR / "post_mouse_scroll.swift"
    binary_path = BIN_DIR / "post_mouse_scroll"
    source = """import Cocoa
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 6 else {
    fputs("usage: post_mouse_scroll <x> <y> <moveDurationMicros> <deltaY> <count> <intervalMicros>\\n", stderr)
    exit(2)
}

guard
    let x = Double(arguments[0]),
    let y = Double(arguments[1]),
    let moveDurationMicros = UInt32(arguments[2]),
    let deltaY = Int32(arguments[3]),
    let count = Int(arguments[4]),
    let intervalMicros = UInt32(arguments[5])
else {
    fputs("invalid numeric arguments\\n", stderr)
    exit(2)
}

let target = CGPoint(x: x, y: y)

func postMove(_ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

let start = CGEvent(source: nil)?.location ?? target
let stepCount = max(1, Int(moveDurationMicros / 16_000))
for step in 1...stepCount {
    let progress = Double(step) / Double(stepCount)
    let point = CGPoint(
        x: start.x + (target.x - start.x) * progress,
        y: start.y + (target.y - start.y) * progress
    )
    postMove(point)
    usleep(step == stepCount ? 1_000 : max(1, moveDurationMicros / UInt32(stepCount)))
}

for index in 0..<max(1, count) {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0) else {
        continue
    }
    event.location = target
    event.post(tap: .cghidEventTap)
    if index < count - 1 {
        usleep(intervalMicros)
    }
}
"""
    current_source = source_path.read_text(encoding="utf-8") if source_path.exists() else None
    if current_source != source or not binary_path.exists():
        source_path.write_text(source, encoding="utf-8")
        run(["swiftc", str(source_path), "-o", str(binary_path)], check=True)
    return require_file(binary_path, "scroll helper binary")


def compile_window_frame_helper() -> Path:
    ensure_directories()
    source_path = BIN_DIR / "set_window_frame.swift"
    binary_path = BIN_DIR / "set_window_frame"
    source = """import Cocoa
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 5 else {
    fputs("usage: set_window_frame <bundleId> <x> <y> <width> <height>\\n", stderr)
    exit(2)
}

let bundleId = arguments[0]
guard
    let x = Double(arguments[1]),
    let y = Double(arguments[2]),
    let width = Double(arguments[3]),
    let height = Double(arguments[4])
else {
    fputs("invalid numeric arguments\\n", stderr)
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
    fputs("app not running\\n", stderr)
    exit(1)
}

_ = app.activate(options: [.activateAllWindows])
Thread.sleep(forTimeInterval: 0.2)

let axApp = AXUIElementCreateApplication(app.processIdentifier)
var position = CGPoint(x: x, y: y)
var size = CGSize(width: width, height: height)

func currentWindows() -> [AXUIElement] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
    guard result == .success, let array = value as? [AXUIElement] else { return [] }
    return array
}

for _ in 0..<40 {
    if let window = currentWindows().first,
       let positionValue = AXValueCreate(.cgPoint, &position),
       let sizeValue = AXValueCreate(.cgSize, &size) {
        let setPosition = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let setSize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        if setPosition == .success && setSize == .success {
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.15)
}

fputs("failed to set window frame\\n", stderr)
exit(1)
"""
    current_source = source_path.read_text(encoding="utf-8") if source_path.exists() else None
    if current_source != source or not binary_path.exists():
        source_path.write_text(source, encoding="utf-8")
        run(["swiftc", str(source_path), "-o", str(binary_path)], check=True)
    return require_file(binary_path, "window frame helper binary")


def parse_shortcut(shortcut: str) -> tuple[str, int, int]:
    parts = shortcut.split("+")
    if len(parts) != 2:
        raise PipelineError(f"Unsupported shortcut format for real capture: {shortcut}")

    modifier, key = parts
    if modifier not in MODIFIER_BITS or modifier not in MODIFIER_KEY_CODES:
        raise PipelineError(f"Unsupported shortcut modifier: {shortcut}")
    if key not in SHORTCUT_KEY_CODES:
        raise PipelineError(f"Unsupported shortcut key: {shortcut}")

    return modifier, MODIFIER_KEY_CODES[modifier], SHORTCUT_KEY_CODES[key]


def post_shortcut_sequence(shortcut: str, tap_count: int, pre_hold: float, between_taps: float, post_hold: float) -> None:
    modifier_name, modifier_key_code, key_code = parse_shortcut(shortcut)
    helper_path = compile_shortcut_helper()
    run(
        [
            str(helper_path),
            modifier_name,
            str(modifier_key_code),
            str(key_code),
            str(tap_count),
            str(int(pre_hold * 1_000_000)),
            str(int(between_taps * 1_000_000)),
            str(int(post_hold * 1_000_000)),
        ],
        capture_output=True,
        check=True,
    )


def post_mouse_click(x: int, y: int, move_duration: float, click_hold: float, settle: float) -> None:
    helper_path = compile_mouse_helper()
    run(
        [
            str(helper_path),
            str(x),
            str(y),
            str(int(move_duration * 1_000_000)),
            str(int(click_hold * 1_000_000)),
            str(int(settle * 1_000_000)),
        ],
        capture_output=True,
        check=True,
    )


def post_key_code(key_code: int, count: int, interval: float) -> None:
    helper_path = compile_key_helper()
    run(
        [
            str(helper_path),
            str(key_code),
            str(max(1, count)),
            str(int(interval * 1_000_000)),
        ],
        capture_output=True,
        check=True,
    )


def post_mouse_scroll(x: int, y: int, move_duration: float, delta_y: int, count: int, interval: float) -> None:
    helper_path = compile_scroll_helper()
    run(
        [
            str(helper_path),
            str(x),
            str(y),
            str(int(move_duration * 1_000_000)),
            str(delta_y),
            str(max(1, count)),
            str(int(interval * 1_000_000)),
        ],
        capture_output=True,
        check=True,
    )


def ensure_group(profile: dict[str, Any], group_name: str) -> dict[str, Any]:
    groups_payload = url_query(profile, "list-groups")
    groups = groups_payload.get("data", [])
    if not isinstance(groups, list):
        raise PipelineError("Unexpected list-groups payload")

    for group in groups:
        if str(group.get("name", "")).lower() == group_name.lower():
            return group

    url_command(profile, f"create-group?name={quote(group_name)}")
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        time.sleep(0.25)
        groups_payload = url_query(profile, "list-groups")
        groups = groups_payload.get("data", [])
        if not isinstance(groups, list):
            raise PipelineError("Unexpected list-groups payload after create-group")
        for group in groups:
            if str(group.get("name", "")).lower() == group_name.lower():
                return group
    raise PipelineError(f"Failed to create group via URL automation: {group_name}")


def sync_group_apps(profile: dict[str, Any], group_id: str, desired_apps: list[dict[str, Any]]) -> None:
    payload = url_query(profile, f"get-group?{group_selector(group_id)}")
    group_data = payload.get("data", {})
    current_apps = group_data.get("apps", [])
    if not isinstance(current_apps, list):
        raise PipelineError("Unexpected get-group payload")

    current_bundle_ids = {str(app["bundleId"]) for app in current_apps}
    desired_bundle_ids = {str(app["bundle_id"]) for app in desired_apps}

    for bundle_id in sorted(current_bundle_ids - desired_bundle_ids):
        url_command(profile, f"remove-app?{group_selector(group_id)}&bundleId={quote(bundle_id)}")
        time.sleep(0.15)

    for app in desired_apps:
        bundle_id = str(app["bundle_id"])
        if bundle_id in current_bundle_ids:
            continue
        url_command(profile, f"add-app?{group_selector(group_id)}&bundleId={quote(bundle_id)}")
        time.sleep(0.15)


def seed_fixture_via_url(profile: dict[str, Any], fixture_id: str) -> None:
    fixture = load_fixture(fixture_id)
    settings = fixture.get("settings", {})

    if "show_hud" in settings:
        url_command(profile, setting_url_command("showHUD", "true" if settings["show_hud"] else "false"))
        time.sleep(0.1)
    if "show_shortcut_in_hud" in settings:
        url_command(
            profile,
            setting_url_command(
                "showShortcutInHUD",
                "true" if settings["show_shortcut_in_hud"] else "false",
            ),
        )
        time.sleep(0.1)
    if "appearance" in settings:
        url_command(profile, setting_url_command("appTheme", str(settings["appearance"])))
        time.sleep(0.1)
    if "language" in settings:
        url_command(profile, setting_url_command("selectedLanguage", str(settings["language"])))
        time.sleep(0.1)

    for position, desired_group in enumerate(fixture["groups"], start=1):
        group = ensure_group(profile, str(desired_group["name"]))
        group_id = str(group["id"])
        if not bool(group.get("isEnabled", True)):
            url_command(profile, f"enable-group?{group_selector(group_id)}")
            time.sleep(0.15)
        sync_group_apps(profile, group_id, desired_group["apps"])
        url_command(profile, f"reorder-group?{group_selector(group_id)}&position={position}")
        time.sleep(0.15)

    if fixture["groups"]:
        first_group = ensure_group(profile, str(fixture["groups"][0]["name"]))
        url_command(profile, f"select-group?{group_selector(str(first_group['id']))}")
        time.sleep(0.15)


def publish_scene_capture(scene: dict[str, Any], capture_path: Path) -> None:
    for destination in scene.get("publish_capture_to", []):
        destination_path = REPO_ROOT / str(destination)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(capture_path, destination_path)


def click_highlight_asset() -> Path:
    ensure_directories()
    output_path = BIN_DIR / "click-highlight.png"
    if output_path.exists():
        return output_path

    size = 96
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((12, 12, size - 12, size - 12), outline=(255, 214, 120, 210), width=6)
    image.save(output_path)
    return output_path


def slugify(value: str) -> str:
    return "".join(character.lower() if character.isalnum() else "-" for character in value).strip("-")


def display_shortcut(shortcut: str) -> str:
    parts = [part.strip() for part in shortcut.split("+") if part.strip()]
    if not parts:
        return shortcut

    modifiers = parts[:-1]
    key = parts[-1].upper()
    if modifiers == ["option"]:
        return f"Opt {key}"
    if modifiers == ["command"]:
        return f"Cmd {key}"
    if modifiers == ["shift"]:
        return f"Shift {key}"
    if modifiers == ["control"]:
        return f"Ctrl {key}"

    return " + ".join(part.title() for part in modifiers + [key])


def shortcut_badge_asset(shortcut: str, group_name: str) -> Path:
    ensure_directories()
    output_path = BIN_DIR / f"shortcut-badge-{slugify(shortcut)}-{slugify(group_name)}.png"
    shortcut_label = display_shortcut(shortcut)
    font = font_for_ui(24, bold=True)
    shortcut_bounds = ImageDraw.Draw(Image.new("RGBA", (1, 1))).textbbox((0, 0), shortcut_label, font=font)
    group_bounds = ImageDraw.Draw(Image.new("RGBA", (1, 1))).textbbox((0, 0), group_name, font=font)
    content_width = (shortcut_bounds[2] - shortcut_bounds[0]) + 22 + (group_bounds[2] - group_bounds[0])
    width = max(228, content_width + 48)
    height = 58
    cache_key = f"{slugify(shortcut_label)}-{slugify(group_name)}-{width}"
    output_path = BIN_DIR / f"shortcut-badge-{cache_key}.png"
    if output_path.exists():
        return output_path

    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_shadow(image, (0, 0, width, height), radius=22, blur=14, fill=(8, 14, 24, 62))

    badge = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge)
    draw.rounded_rectangle((0, 0, width, height), radius=22, fill=(10, 16, 26, 154))
    draw.text((20, 16), shortcut_label, font=font, fill="#FFFFFF")
    draw.text((20 + (shortcut_bounds[2] - shortcut_bounds[0]) + 22, 16), group_name, font=font, fill="#D4DEE9")
    image.alpha_composite(badge)
    image.save(output_path)
    return output_path


def apply_click_highlights(scene: dict[str, Any], capture_path: Path) -> None:
    click_actions = [action for action in scene.get("actions", []) if action.get("type") == "mouse-click" and action.get("highlight", True)]
    if not click_actions:
        return

    highlight_path = click_highlight_asset()
    capture_duration = float(ffprobe_stream(capture_path)["format"]["duration"])
    temp_output = capture_path.with_name(f"{capture_path.stem}-clicks{capture_path.suffix}")
    command = ["ffmpeg", "-y", "-i", str(capture_path)]
    filter_parts: list[str] = []
    previous = "[0:v]"

    for index, action in enumerate(click_actions, start=1):
        command.extend(["-loop", "1", "-i", str(highlight_path)])
        x = int(action["x"]) - 60
        y = int(action["y"]) - 60
        start = float(action["at"])
        duration = float(action.get("highlight_duration", 0.45))
        output_label = f"[v{index}]"
        filter_parts.append(
            f"{previous}[{index}:v]overlay={x}:{y}:enable='between(t,{start:.3f},{start + duration:.3f})'{output_label}"
        )
        previous = output_label

    command.extend(
        [
            "-filter_complex",
            ";".join(filter_parts),
            "-map",
            previous,
            "-t",
            f"{capture_duration:.3f}",
            "-shortest",
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(temp_output),
        ]
    )
    run(command, check=True)
    temp_output.replace(capture_path)


def shortcut_group_names(scene: dict[str, Any]) -> dict[str, str]:
    fixture = load_fixture(str(scene["fixture"]))
    return {str(group["shortcut"]): str(group["name"]) for group in fixture.get("groups", [])}


def apply_shortcut_overlays(scene: dict[str, Any], capture_path: Path) -> None:
    shortcut_actions = [
        action
        for action in scene.get("actions", [])
        if action.get("type") == "shortcut-sequence" and action.get("show_shortcut_overlay", False)
    ]
    if not shortcut_actions:
        return

    group_names = shortcut_group_names(scene)
    capture_duration = float(ffprobe_stream(capture_path)["format"]["duration"])
    temp_output = capture_path.with_name(f"{capture_path.stem}-shortcuts{capture_path.suffix}")
    command = ["ffmpeg", "-y", "-i", str(capture_path)]
    filter_parts: list[str] = []
    previous = "[0:v]"

    for index, action in enumerate(shortcut_actions, start=1):
        shortcut = str(action["shortcut"])
        group_name = group_names.get(shortcut, str(action.get("overlay_group_name", "ShortcutCycle")))
        badge_path = shortcut_badge_asset(shortcut, group_name)
        command.extend(["-loop", "1", "-i", str(badge_path)])
        start = max(0.0, float(action["at"]) - 0.08)
        duration = float(action.get("overlay_duration", 0.90))
        output_label = f"[v{index}]"
        filter_parts.append(
            f"{previous}[{index}:v]overlay=84:76:enable='between(t,{start:.3f},{start + duration:.3f})'{output_label}"
        )
        previous = output_label

    command.extend(
        [
            "-filter_complex",
            ";".join(filter_parts),
            "-map",
            previous,
            "-t",
            f"{capture_duration:.3f}",
            "-shortest",
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(temp_output),
        ]
    )
    run(command, check=True)
    temp_output.replace(capture_path)


def shortcut_display(shortcut: str) -> str:
    symbols = {
        "command": "Cmd ",
        "shift": "Shift ",
        "option": "Opt ",
        "control": "Ctrl ",
    }
    parts = shortcut.split("+")
    return "".join(symbols.get(part, part.upper()) for part in parts)


def font_for_ui(size: int, *, bold: bool = False) -> ImageFont.ImageFont:
    path = DEFAULT_BOLD_FONT if bold else DEFAULT_REGULAR_FONT
    try:
        return ImageFont.truetype(path, size=size)
    except OSError:
        return ImageFont.load_default()


def resize_cover(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )
    left = max(0, (resized.width - width) // 2)
    top = max(0, (resized.height - height) // 2)
    return resized.crop((left, top, left + width, top + height))


def resize_contain(image: Image.Image, width: int, height: int) -> Image.Image:
    copy = image.copy()
    copy.thumbnail((width, height), Image.Resampling.LANCZOS)
    return copy


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def draw_shadow(
    canvas: Image.Image,
    box: tuple[int, int, int, int],
    *,
    radius: int,
    blur: int = 24,
    fill: tuple[int, int, int, int] = (14, 22, 38, 120),
) -> None:
    left, top, right, bottom = box
    shadow = Image.new("RGBA", (right - left + blur * 2, bottom - top + blur * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(
        (blur, blur, shadow.width - blur, shadow.height - blur),
        radius=radius,
        fill=fill,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, (left - blur, top - blur // 2))


def relative_crop_box(image: Image.Image, crop_rel: list[float]) -> tuple[int, int, int, int]:
    left = int(image.width * crop_rel[0])
    top = int(image.height * crop_rel[1])
    right = int(image.width * crop_rel[2])
    bottom = int(image.height * crop_rel[3])
    return left, top, right, bottom


def list_windows() -> list[dict[str, Any]]:
    script = """
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
var rows: [[String: Any]] = []

for item in info {
    guard
        let id = item[kCGWindowNumber as String] as? Int,
        let owner = item[kCGWindowOwnerName as String] as? String,
        let bounds = item[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? Double,
        let y = bounds["Y"] as? Double,
        let width = bounds["Width"] as? Double,
        let height = bounds["Height"] as? Double
    else {
        continue
    }

    let layer = item[kCGWindowLayer as String] as? Int ?? 0
    if layer != 0 || width < 220 || height < 180 {
        continue
    }

    rows.append([
        "id": id,
        "owner": owner,
        "name": item[kCGWindowName as String] as? String ?? "",
        "x": Int(x),
        "y": Int(y),
        "width": Int(width),
        "height": Int(height),
    ])
}

let data = try JSONSerialization.data(withJSONObject: rows)
print(String(decoding: data, as: UTF8.self))
"""
    result = run(["swift", "-e", script], check=True)
    payload = json.loads(result.stdout)
    if not isinstance(payload, list):
        raise PipelineError("Unexpected window listing payload")
    return payload


def wait_for_window(
    owner_name: str,
    *,
    title_contains: str | None = None,
    timeout: float = 18.0,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    best_match: dict[str, Any] | None = None
    title_query = title_contains.lower() if title_contains else None

    while time.monotonic() < deadline:
        matches: list[dict[str, Any]] = []
        for window in list_windows():
            if window["owner"] != owner_name:
                continue
            if title_query and title_query not in str(window.get("name", "")).lower():
                continue
            matches.append(window)

        if matches:
            best_match = max(matches, key=lambda item: int(item["width"]) * int(item["height"]))
            break
        time.sleep(0.5)

    if best_match is None:
        raise PipelineError(
            f"Timed out waiting for window owned by '{owner_name}'"
            + (f" containing '{title_contains}'" if title_contains else "")
        )
    return best_match


def capture_window(window_id: int, output_path: Path) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        ["screencapture", "-x", "-o", "-l", str(window_id), str(output_path)],
        check=True,
    )
    return require_file(output_path, "captured window image")


def find_app_bundle(bundle_identifier: str) -> Path:
    known = KNOWN_APP_BUNDLES.get(bundle_identifier)
    if known is not None and known.exists():
        return known

    result = run(["mdfind", f"kMDItemCFBundleIdentifier == '{bundle_identifier}'"], check=True)
    candidates = [Path(line.strip()) for line in result.stdout.splitlines() if line.strip().endswith(".app")]
    if not candidates:
        raise PipelineError(f"Unable to locate app bundle for {bundle_identifier}")

    candidates.sort(
        key=lambda path: (
            0 if str(path).startswith("/System/Applications/") else 1,
            0 if str(path).startswith("/Applications/") else 1,
            len(str(path)),
        )
    )
    return candidates[0]


def app_icon_path(bundle_identifier: str, icon_output_path: Path) -> Path:
    bundle = find_app_bundle(bundle_identifier)
    info_plist = bundle / "Contents" / "Info.plist"
    icon_name = ""
    result = run(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIconFile", str(info_plist)],
        check=False,
    )
    if result.returncode == 0:
        icon_name = result.stdout.strip()

    candidates: list[Path] = []
    if icon_name:
        icon_file = icon_name if icon_name.endswith(".icns") else f"{icon_name}.icns"
        candidates.append(bundle / "Contents" / "Resources" / icon_file)
    candidates.extend(sorted((bundle / "Contents" / "Resources").glob("*.icns")))

    source_icon = next((path for path in candidates if path.exists()), None)
    if source_icon is None:
        raise PipelineError(f"Unable to locate icon asset for {bundle_identifier}")

    icon_output_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "sips",
            "-s",
            "format",
            "png",
            str(source_icon),
            "--out",
            str(icon_output_path),
        ],
        check=True,
    )
    return require_file(icon_output_path, "converted app icon")


def create_overview_poster(output_path: Path) -> Path:
    require_file(OVERVIEW_BACKGROUND_PATH, "overview background image")
    image = resize_cover(Image.open(OVERVIEW_BACKGROUND_PATH).convert("RGBA"), 1600, 1000)
    overlay = Image.new("RGBA", image.size, (12, 24, 40, 58))
    image.alpha_composite(overlay)

    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((980, -60, 1620, 520), fill=(255, 255, 255, 52))
    glow = glow.filter(ImageFilter.GaussianBlur(54))
    image.alpha_composite(glow)

    panel = Image.new("RGBA", image.size, (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle((90, 120, 760, 720), radius=46, fill=(8, 14, 24, 138))
    image.alpha_composite(panel)

    draw = ImageDraw.Draw(image)
    title_font = font_for_ui(118, bold=True)
    subtitle_font = font_for_ui(42, bold=False)
    body_font = font_for_ui(32, bold=False)
    draw.text((146, 190), "ShortcutCycle", font=title_font, fill="#FFFFFF")
    draw.text((152, 338), "One shortcut per group", font=subtitle_font, fill="#D7E7F4")
    draw.text((152, 414), "Press again to cycle through your\nmost-used apps without breaking flow.", font=body_font, fill="#EEF5FB", spacing=10)

    chip_fill = (255, 255, 255, 228)
    chip_text = "#0B111B"
    chip_font = font_for_ui(28, bold=True)
    chips = ["⌥1 Tools", "⌥3 Projects"]
    x = 152
    for label in chips:
        bounds = draw.textbbox((0, 0), label, font=chip_font)
        chip_width = (bounds[2] - bounds[0]) + 54
        draw.rounded_rectangle((x, 560, x + chip_width, 612), radius=26, fill=chip_fill)
        draw.text((x + 27, 572), label, font=chip_font, fill=chip_text)
        x += chip_width + 16

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output_path)
    return output_path


def prepare_synthetic_overview_sources(run_id: str, work_dir: Path) -> dict[str, dict[str, Any]]:
    suffix = run_id.replace("/", "-")[-8:]
    poster_path = work_dir / f"daily-poster-{suffix}.png"
    notes_path = work_dir / f"project-notes-{suffix}.txt"
    create_overview_poster(poster_path)
    notes_path.write_text(
        "ShortcutCycle video pipeline\n"
        "Synthetic overview capture\n"
        "Tools: Clock, Tips, Calculator\n"
        "Projects: Font Book, TextEdit, Dictionary\n",
        encoding="utf-8",
    )

    sources = json.loads(json.dumps(SYNTHETIC_OVERVIEW_SOURCES))
    sources["com.apple.Preview"]["launch"] = ["open", "-a", "Preview", str(poster_path)]
    sources["com.apple.Preview"]["title_contains"] = poster_path.name
    sources["com.apple.TextEdit"]["launch"] = ["open", "-a", "TextEdit", str(notes_path)]
    sources["com.apple.TextEdit"]["title_contains"] = notes_path.name

    for bundle_identifier, config in sources.items():
        if "launch" not in config:
            config["launch"] = ["open", "-a", str(config["launch_app"])]
        config["capture_name"] = bundle_identifier.replace(".", "_")
    return sources


def render_overview_background(width: int, height: int) -> Image.Image:
    require_file(OVERVIEW_BACKGROUND_PATH, "overview background image")
    background = resize_cover(Image.open(OVERVIEW_BACKGROUND_PATH).convert("RGBA"), width, height)
    background.alpha_composite(Image.new("RGBA", background.size, (255, 255, 255, 28)))

    vignette = Image.new("RGBA", background.size, (0, 0, 0, 0))
    vignette_draw = ImageDraw.Draw(vignette)
    vignette_draw.ellipse((-220, -260, width + 180, height + 200), fill=(255, 255, 255, 34))
    vignette = vignette.filter(ImageFilter.GaussianBlur(160))
    background.alpha_composite(vignette)

    shade = Image.new("RGBA", background.size, (0, 0, 0, 0))
    shade_draw = ImageDraw.Draw(shade)
    shade_draw.rectangle((0, 0, width, height), fill=(7, 15, 28, 30))
    background.alpha_composite(shade)
    return background


def draw_shortcut_badge(
    canvas: Image.Image,
    *,
    shortcut: str,
    group_name: str,
) -> None:
    badge_box = (120, 112, 328, 248)
    draw_shadow(canvas, badge_box, radius=34, blur=18, fill=(10, 16, 26, 116))

    badge = Image.new("RGBA", (badge_box[2] - badge_box[0], badge_box[3] - badge_box[1]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge)
    draw.rounded_rectangle((0, 0, badge.width, badge.height), radius=34, fill=(8, 12, 20, 214))
    draw.text((34, 22), shortcut, font=font_for_ui(54, bold=True), fill="#FFFFFF")
    draw.text((36, 86), group_name, font=font_for_ui(24), fill="#B8C9D8")
    canvas.alpha_composite(badge, badge_box[:2])


def render_window_image(
    capture_path: Path,
    *,
    crop_rel: list[float] | None,
    width: int,
    height: int,
) -> Image.Image:
    image = Image.open(capture_path).convert("RGBA")
    if crop_rel is not None:
        image = image.crop(relative_crop_box(image, crop_rel))
    image = resize_contain(image, width, height)
    mask = rounded_mask(image.size, 34)
    image.putalpha(mask)
    return image


def draw_hud(
    canvas: Image.Image,
    *,
    apps: list[dict[str, Any]],
    active_bundle_id: str,
    icon_paths: dict[str, Path],
    active_name: str,
) -> None:
    count = len(apps)
    panel_width = 56 + count * 92
    panel_height = 118
    panel_left = (canvas.width - panel_width) // 2
    panel_top = canvas.height - 238
    panel_box = (panel_left, panel_top, panel_left + panel_width, panel_top + panel_height)
    draw_shadow(canvas, panel_box, radius=42, blur=22, fill=(12, 18, 34, 104))

    panel = Image.new("RGBA", (panel_width, panel_height), (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle((0, 0, panel_width, panel_height), radius=42, fill=(248, 249, 252, 214))

    cursor_x = 28
    for app in apps:
        is_active = app["bundle_id"] == active_bundle_id
        slot_box = (cursor_x, 20, cursor_x + 72, 92)
        if is_active:
            panel_draw.rounded_rectangle(slot_box, radius=22, fill=(214, 221, 231, 242))

        icon = Image.open(icon_paths[app["bundle_id"]]).convert("RGBA")
        icon = resize_contain(icon, 54, 54)
        panel.alpha_composite(icon, (cursor_x + (72 - icon.width) // 2, 20 + (72 - icon.height) // 2))
        cursor_x += 92

    canvas.alpha_composite(panel, panel_box[:2])

    label_text = active_name
    label_font = font_for_ui(28, bold=True)
    draw = ImageDraw.Draw(canvas)
    bounds = draw.textbbox((0, 0), label_text, font=label_font)
    label_width = (bounds[2] - bounds[0]) + 44
    label_height = 52
    label_left = (canvas.width - label_width) // 2
    label_top = panel_top + panel_height + 24
    label_box = (label_left, label_top, label_left + label_width, label_top + label_height)
    draw_shadow(canvas, label_box, radius=26, blur=18, fill=(12, 18, 34, 78))
    draw.rounded_rectangle(label_box, radius=26, fill=(246, 248, 251, 230))
    draw.text((label_left + 22, label_top + 11), label_text, font=label_font, fill="#10161F")


def window_surface(
    size: tuple[int, int],
    title: str,
    icon_path: Path,
    *,
    body_fill: str,
    title_fill: str | None = None,
    title_color: str = "#1C2530",
    border_color: tuple[int, int, int, int] = (255, 255, 255, 78),
) -> tuple[Image.Image, ImageDraw.ImageDraw, tuple[int, int, int, int]]:
    width, height = size
    title_fill = title_fill or body_fill
    surface = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(surface)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), radius=38, fill=body_fill, outline=border_color)
    draw.rounded_rectangle((0, 0, width - 1, 90), radius=38, fill=title_fill)
    draw.rectangle((0, 52, width - 1, 90), fill=title_fill)
    for index, color in enumerate(("#FF5F57", "#FEBB2E", "#28C840")):
        x = 30 + index * 28
        draw.ellipse((x, 26, x + 16, 42), fill=color)

    icon = Image.open(icon_path).convert("RGBA")
    icon = resize_contain(icon, 28, 28)
    surface.alpha_composite(icon, (118, 22))
    draw.text((154, 18), title, font=font_for_ui(28, bold=True), fill=title_color)
    return surface, draw, (30, 108, width - 30, height - 30)


def draw_analog_clock(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int) -> None:
    cx, cy = center
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill="#FFFFFF")
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline="#D4D9DE", width=3)
    for index in range(12):
        angle = (index / 12) * math.tau
        inner = radius - 12
        outer = radius - 4
        x1 = cx + int(inner * math.sin(angle))
        y1 = cy - int(inner * math.cos(angle))
        x2 = cx + int(outer * math.sin(angle))
        y2 = cy - int(outer * math.cos(angle))
        draw.line((x1, y1, x2, y2), fill="#1B2027", width=3)
    draw.line((cx, cy, cx + 18, cy - 6), fill="#FF8A24", width=5)
    draw.line((cx, cy, cx - 10, cy + 24), fill="#1B2027", width=5)
    draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill="#1B2027")


def render_clock_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((1420, 860), app_name, icon_path, body_fill="#1A1D22", title_fill="#1A1D22", title_color="#F5F7FB")
    left, top, right, bottom = content
    draw.rounded_rectangle((420, top - 16, 1000, top + 34), radius=24, outline="#3F454E", width=2)
    tabs = ["World Clock", "Alarms", "Stopwatch", "Timers"]
    x = 458
    for index, label in enumerate(tabs):
        fill = "#3A4048" if index == 0 else None
        if fill:
            draw.rounded_rectangle((x - 12, top - 6, x + 112, top + 24), radius=16, fill=fill)
        draw.text((x, top), label, font=font_for_ui(24, bold=index == 0), fill="#F7F9FC" if index == 0 else "#D3D8DD")
        x += 150

    map_box = (left + 18, top + 58, right - 18, top + 450)
    draw.rounded_rectangle(map_box, radius=28, fill="#111317")
    for x in range(map_box[0] + 80, map_box[2], 100):
        draw.line((x, map_box[1] + 20, x, map_box[3] - 20), fill="#262B33", width=2)
    draw.arc((map_box[0] + 180, map_box[1] - 120, map_box[0] + 860, map_box[3] + 120), start=18, end=156, fill="#6E7582", width=4)
    draw.arc((map_box[0] + 520, map_box[1] - 160, map_box[2] + 140, map_box[3] + 150), start=196, end=340, fill="#6E7582", width=4)
    for city, x, y, time_text in [("Cupertino", 220, 180, "4:00 PM"), ("New York", 470, 172, "7:00 PM")]:
        px = map_box[0] + x
        py = map_box[1] + y
        draw.ellipse((px - 6, py - 6, px + 6, py + 6), fill="#FF9A32")
        draw.text((px + 14, py - 14), city, font=font_for_ui(24, bold=True), fill="#FFFFFF")
        draw.text((px + 14, py + 16), time_text, font=font_for_ui(18), fill="#C4CBD3")

    card_y = map_box[3] + 26
    for index, (label, time_text) in enumerate((("Cupertino", "Today, -3 HRS"), ("New York", "Today, +0 HRS"))):
        card_left = left + 28 + index * 270
        draw.rounded_rectangle((card_left, card_y, card_left + 230, bottom - 18), radius=28, fill="#2B2E33")
        draw_analog_clock(draw, (card_left + 82, card_y + 84), 48)
        draw.text((card_left + 34, card_y + 154), label, font=font_for_ui(24, bold=True), fill="#F6F7F9")
        draw.text((card_left + 34, card_y + 188), time_text, font=font_for_ui(18), fill="#C6CBD2")
    return surface


def render_tips_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((1480, 900), app_name, icon_path, body_fill="#FBFBFC", title_fill="#FAFAFB")
    left, top, right, bottom = content
    draw.text((left + 220, top + 8), "Need help? Find answers here.", font=font_for_ui(56, bold=True), fill="#232A33")
    draw.rounded_rectangle((left + 160, top + 84, right - 170, top + 138), radius=27, outline="#D7DDE4", width=3)
    draw.text((left + 194, top + 96), "“How to take a screenshot” or “Make text bigger”", font=font_for_ui(24), fill="#7B8794")

    hero_box = (left + 12, top + 220, left + 470, top + 610)
    draw.rounded_rectangle(hero_box, radius=34, fill="#EEF6FF")
    draw.ellipse((hero_box[0] + 44, hero_box[1] + 40, hero_box[0] + 280, hero_box[1] + 276), fill="#CFE5FF")
    draw.text((hero_box[0] + 118, hero_box[1] + 112), "mac\nOS", font=font_for_ui(62, bold=True), fill="#4687D8", spacing=0, align="center")
    draw.text((hero_box[0] + 44, hero_box[1] + 298), "Mac User Guide", font=font_for_ui(48, bold=True), fill="#FFFFFF")
    draw.text((hero_box[0] + 44, hero_box[1] + 354), "See the full guide for your Mac.", font=font_for_ui(24), fill="#EAF5FF")

    rows = [
        ("Use subtitles and closed captions", "Show subtitles and captions, and customize how they look."),
        ("Zoom in on what’s around you", "Use the built-in camera or a connected camera to zoom in on things nearby."),
        ("Translate text in apps or in person", "Get translations of messages, calls, and face-to-face conversations."),
    ]
    row_top = top + 230
    for title, body in rows:
        draw.text((left + 580, row_top), title, font=font_for_ui(28, bold=True), fill="#202732")
        draw.text((left + 580, row_top + 42), body, font=font_for_ui(22), fill="#687481")
        draw.line((left + 560, row_top + 96, right - 40, row_top + 96), fill="#E0E5EA", width=2)
        row_top += 116

    draw.text((left + 12, bottom - 196), "Tips", font=font_for_ui(54, bold=True), fill="#232A33")
    chips = ["What’s New", "Apple Intelligence", "Welcome to Mac", "Essentials"]
    chip_left = left + 12
    for label in chips:
        draw.rounded_rectangle((chip_left, bottom - 120, chip_left + 260, bottom - 24), radius=28, fill="#F2F4F6", outline="#E0E5EA")
        draw.text((chip_left + 24, bottom - 90), label, font=font_for_ui(24, bold=True), fill="#25303B")
        chip_left += 282
    return surface


def render_calculator_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((860, 980), app_name, icon_path, body_fill="#242627", title_fill="#242627", title_color="#F5F7FA")
    left, top, right, bottom = content
    draw.rounded_rectangle((left, top, right, bottom), radius=34, fill="#2B2D2E")
    draw.text((right - 120, top + 68), "5", font=font_for_ui(82), fill="#F6F7F9")
    labels = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["±", "0", ".", "="],
    ]
    y = top + 178
    for row in labels:
        x = left + 24
        for label in row:
            fill = "#3A3D3F" if label not in {"÷", "−", "+", "="} else "#FF9F0A"
            draw.ellipse((x, y, x + 150, y + 150), fill=fill)
            draw.text((x + 58, y + 46), label, font=font_for_ui(54, bold=True), fill="#FFFFFF")
            x += 168
        y += 168
    return surface


def render_fontbook_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((1460, 900), app_name, icon_path, body_fill="#FCFCFD", title_fill="#FBFBFC")
    left, top, right, bottom = content
    draw.rounded_rectangle((left, top, left + 210, bottom), radius=28, fill="#F4F7FB")
    draw.rounded_rectangle((left + 18, top + 26, left + 192, top + 86), radius=20, fill="#1B6FFF")
    draw.text((left + 54, top + 42), "All Fonts", font=font_for_ui(28, bold=True), fill="#FFFFFF")
    sidebar_items = ["My Fonts", "English", "Simplified...", "Web", "Fixed Width"]
    y = top + 126
    for label in sidebar_items:
        draw.text((left + 30, y), label, font=font_for_ui(24, bold=label == "My Fonts"), fill="#1D2630" if label == "My Fonts" else "#56616E")
        y += 64

    cell_left = left + 262
    cell_top = top + 14
    glyphs = [("Aa", "Academy"), ("क", "Adelle Sans"), ("غ", "Akaya"), ("😃", "Apple Color Emoji"), ("漢", "Apple LiGothic"), ("⌘", "Apple Symbols")]
    index = 0
    for row in range(2):
        for column in range(3):
            x = cell_left + column * 330
            y = cell_top + row * 308
            draw.rounded_rectangle((x, y, x + 284, y + 260), radius=26, fill="#FFFFFF", outline="#E3E8EE")
            glyph, label = glyphs[index]
            draw.text((x + 98, y + 72), glyph, font=font_for_ui(74, bold=True), fill="#272E36")
            draw.text((x + 42, y + 194), label, font=font_for_ui(22, bold=True), fill="#27313A")
            draw.text((x + 42, y + 224), "1 style", font=font_for_ui(18), fill="#8A94A0")
            index += 1
    return surface


def render_textedit_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((1380, 860), app_name, icon_path, body_fill="#FFFFFF", title_fill="#F6F7F9")
    left, top, right, bottom = content
    draw.rounded_rectangle((left + 24, top + 20, right - 24, bottom - 24), radius=18, fill="#FFFFFF", outline="#E6E9ED")
    mono = font_for_ui(28)
    lines = [
        "ShortcutCycle video pipeline",
        "",
        "1. Seed a deterministic demo state",
        "2. Build a clean overview clip",
        "3. Add the intro card automatically",
        "",
        "Result: repeatable marketing footage",
    ]
    y = top + 72
    for line in lines:
        draw.text((left + 60, y), line, font=mono, fill="#151B22")
        y += 42
    draw.rectangle((left + 60, y - 6, left + 64, y + 26), fill="#4A90E2")
    return surface


def render_dictionary_capture(app_name: str, icon_path: Path) -> Image.Image:
    surface, draw, content = window_surface((1460, 860), app_name, icon_path, body_fill="#FFFFFF", title_fill="#FBFBFC")
    left, top, right, bottom = content
    draw.rounded_rectangle((left + 360, top - 6, right - 60, top + 46), radius=24, outline="#D6DBE2", width=2)
    draw.text((left + 390, top + 6), "shortcut", font=font_for_ui(24), fill="#717D8A")
    for index, label in enumerate(["All", "English", "Thesaurus"]):
        fill = "#E9EDF2" if index == 1 else None
        if fill:
            draw.rounded_rectangle((left + 10 + index * 120, top + 4, left + 104 + index * 120, top + 40), radius=18, fill=fill)
        draw.text((left + 34 + index * 120, top + 8), label, font=font_for_ui(22, bold=index == 1), fill="#2A3139")
    draw.text((left + 28, top + 92), "shortcut", font=font_for_ui(68, bold=True), fill="#202833")
    draw.text((left + 30, top + 176), "/ˈshôrtˌkət/", font=font_for_ui(28), fill="#7F8893")
    draw.text((left + 30, top + 248), "noun", font=font_for_ui(26, bold=True), fill="#3E4955")
    definition = (
        "a route that is shorter than the usual one,\n"
        "or an easier, faster way to do something."
    )
    draw.text((left + 30, top + 300), definition, font=font_for_ui(34), fill="#202833", spacing=14)
    draw.text((left + 30, top + 444), "“ShortcutCycle gives each app group a shortcut.”", font=font_for_ui(28), fill="#5D6875")
    return surface


def render_synthetic_window_capture(
    bundle_identifier: str,
    *,
    app_name: str,
    icon_path: Path,
    output_path: Path,
) -> Path:
    renderers = {
        "com.apple.calculator": render_calculator_capture,
        "com.apple.clock": render_clock_capture,
        "com.apple.Dictionary": render_dictionary_capture,
        "com.apple.FontBook": render_fontbook_capture,
        "com.apple.TextEdit": render_textedit_capture,
        "com.apple.helpviewer": render_tips_capture,
    }
    renderer = renderers.get(bundle_identifier)
    if renderer is None:
        raise PipelineError(f"No synthetic renderer configured for {bundle_identifier}")
    image = renderer(app_name, icon_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output_path)
    return output_path


def render_overview_state_image(
    *,
    width: int,
    height: int,
    state: dict[str, Any],
    capture_paths: dict[str, Path],
    icon_paths: dict[str, Path],
) -> Image.Image:
    source = SYNTHETIC_OVERVIEW_SOURCES[state["app"]["bundle_id"]]
    canvas = render_overview_background(width, height)

    window_image = render_window_image(
        capture_paths[state["app"]["bundle_id"]],
        crop_rel=source.get("crop_rel"),
        width=1520,
        height=820,
    )
    window_left = (width - window_image.width) // 2
    window_top = 64 + max(0, (820 - window_image.height) // 4)
    window_box = (window_left, window_top, window_left + window_image.width, window_top + window_image.height)
    draw_shadow(canvas, window_box, radius=38, blur=28)
    canvas.alpha_composite(window_image, (window_left, window_top))

    draw_shortcut_badge(
        canvas,
        shortcut=state["shortcut_label"],
        group_name=state["group"]["name"],
    )
    draw_hud(
        canvas,
        apps=state["group"]["apps"],
        active_bundle_id=state["app"]["bundle_id"],
        icon_paths=icon_paths,
        active_name=state["app"]["name"],
    )
    return canvas


def synthetic_overview_states(scene: dict[str, Any], fixture: dict[str, Any]) -> list[dict[str, Any]]:
    groups = {group["name"]: group for group in fixture["groups"]}
    actions = sorted(scene.get("actions", []), key=lambda item: float(item["at"]))
    if not actions:
        raise PipelineError("Synthetic overview capture requires at least one action")

    duration = float(scene["capture"]["duration"])
    initial_group_name = str(actions[0]["group"])
    current_group_name = initial_group_name
    current_index = 0
    states: list[dict[str, Any]] = []

    initial_group = groups[current_group_name]
    states.append(
        {
            "start": 0.0,
            "end": float(actions[0]["at"]),
            "group": initial_group,
            "app": initial_group["apps"][current_index],
            "shortcut_label": shortcut_display(str(initial_group["shortcut"])),
        }
    )

    for index, action in enumerate(actions):
        group_name = str(action["group"])
        if group_name not in groups:
            raise PipelineError(f"Unknown group in synthetic scene: {group_name}")
        if str(action["type"]) != "cycle":
            raise PipelineError(f"Unsupported synthetic overview action: {action['type']}")

        if group_name == current_group_name:
            current_index = (current_index + 1) % len(groups[group_name]["apps"])
        else:
            current_group_name = group_name
            current_index = 0

        group = groups[current_group_name]
        next_at = float(actions[index + 1]["at"]) if index + 1 < len(actions) else duration
        states.append(
            {
                "start": float(action["at"]),
                "end": next_at,
                "group": group,
                "app": group["apps"][current_index],
                "shortcut_label": shortcut_display(str(group["shortcut"])),
            }
        )
    return states


def capture_synthetic_overview(scene: dict[str, Any], run_id: str) -> Path:
    profile = load_profile(scene["profile"])
    fixture = load_fixture(scene["fixture"])
    width, height = output_size(profile)
    fps = frame_rate(profile)
    output_path = raw_scene_path(str(scene["id"]), run_id)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    work_dir = output_path.parent / f"{scene['id']}-synthetic-assets"
    captures_dir = work_dir / "captures"
    icons_dir = work_dir / "icons"
    states_dir = work_dir / "states"
    for directory in (work_dir, captures_dir, icons_dir, states_dir):
        directory.mkdir(parents=True, exist_ok=True)

    bundle_to_app = {app["bundle_id"]: app for group in fixture["groups"] for app in group["apps"]}
    source_bundle_ids = sorted(bundle_to_app.keys())
    capture_paths: dict[str, Path] = {}
    icon_paths: dict[str, Path] = {}
    for bundle_identifier in source_bundle_ids:
        icon_paths[bundle_identifier] = app_icon_path(
            bundle_identifier,
            icons_dir / f"{bundle_identifier.replace('.', '_')}.png",
        )
        capture_paths[bundle_identifier] = render_synthetic_window_capture(
            bundle_identifier,
            app_name=str(bundle_to_app[bundle_identifier]["name"]),
            icon_path=icon_paths[bundle_identifier],
            output_path=captures_dir / f"{bundle_identifier.replace('.', '_')}.png",
        )

    state_entries = synthetic_overview_states(scene, fixture)
    concat_lines: list[str] = []
    last_frame_path: Path | None = None
    for index, state in enumerate(state_entries):
        frame_path = states_dir / f"state-{index:02d}.png"
        render_overview_state_image(
            width=width,
            height=height,
            state=state,
            capture_paths=capture_paths,
            icon_paths=icon_paths,
        ).convert("RGB").save(frame_path)
        concat_lines.append(f"file '{frame_path.resolve()}'\n")
        concat_lines.append(f"duration {state['end'] - state['start']:.3f}\n")
        last_frame_path = frame_path

    if last_frame_path is None:
        raise PipelineError("Synthetic overview produced no frames")
    concat_lines.append(f"file '{last_frame_path.resolve()}'\n")

    concat_path = states_dir / "states.txt"
    concat_path.write_text("".join(concat_lines), encoding="utf-8")
    run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_path),
            "-vf",
            f"fps={fps},format=yuv420p",
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(output_path),
        ],
        check=True,
    )
    require_file(output_path, "synthetic overview output")
    publish_scene_capture(scene, output_path)
    return output_path


def execute_capture_action(profile: dict[str, Any], action: dict[str, Any]) -> None:
    action_type = action["type"]
    if action_type == "cycle":
        group = quote(str(action["group"]))
        open_url(profile, f"shortcutcycle://cycle?group={group}")
    elif action_type == "shortcut-sequence":
        post_shortcut_sequence(
            str(action["shortcut"]),
            int(action.get("tap_count", 1)),
            float(action.get("pre_hold", 0.12)),
            float(action.get("between_taps", 0.26)),
            float(action.get("post_hold", 0.42)),
        )
    elif action_type == "open-url":
        open_url(profile, str(action["url"]))
    elif action_type == "launch-app":
        launch_app(str(action["bundle_id"]))
    elif action_type == "activate-app":
        run(
            ["osascript", "-e", f'tell application id "{str(action["bundle_id"])}" to activate'],
            capture_output=True,
            check=True,
        )
    elif action_type == "mouse-click":
        post_mouse_click(
            int(action["x"]),
            int(action["y"]),
            float(action.get("move_duration", 0.30)),
            float(action.get("click_hold", 0.05)),
            float(action.get("settle", 0.14)),
        )
    elif action_type == "key-code":
        post_key_code(
            int(action["key_code"]),
            int(action.get("count", 1)),
            float(action.get("interval", 0.14)),
        )
    elif action_type == "scroll-wheel":
        post_mouse_scroll(
            int(action["x"]),
            int(action["y"]),
            float(action.get("move_duration", 0.20)),
            int(action.get("delta_y", -3)),
            int(action.get("count", 1)),
            float(action.get("interval", 0.18)),
        )
    else:
        raise PipelineError(f"Unsupported capture action: {action_type}")


def capture_scene(scene_id: str, run_id: str) -> Path:
    ensure_directories()
    scene = load_scene(scene_id)
    capture_settings = scene.get("capture", {})
    if capture_settings.get("mode") == "synthetic_overview":
        return capture_synthetic_overview(scene, run_id)

    profile = load_profile(scene["profile"])
    output_path = raw_scene_path(scene_id, run_id)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    quit_integration_app(profile)
    run_prepare_steps([step for step in scene.get("prepare_before_launch", []) if isinstance(step, dict)])

    did_seed_fixture = not bool(scene.get("skip_seed", False))
    if did_seed_fixture:
        seed_fixture(profile, scene["fixture"])

    launch_integration_app(profile)
    time.sleep(0.6)

    if did_seed_fixture:
        seed_fixture_via_url(profile, scene["fixture"])

    for command in scene.get("prepare_urls", []):
        url_command(profile, str(command))
        time.sleep(0.15)

    for bundle_identifier in scene.get("launch_apps", []):
        launch_app(str(bundle_identifier))
        time.sleep(float(profile.get("app_launch_stagger_seconds", 0.6)))

    run_prepare_steps([step for step in scene.get("prepare_after_launch", []) if isinstance(step, dict)])

    if scene.get("window_bounds") or scene.get("window_layouts"):
        stage_windows(scene)

    duration = float(capture_settings["duration"])
    ffmpeg_command = [
        "ffmpeg",
        "-y",
        "-f",
        "avfoundation",
        "-pixel_format",
        str(profile.get("capture_pixel_format", "bgr0")),
        "-framerate",
        str(frame_rate(profile)),
        "-i",
        str(profile["capture_device"]),
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        str(output_path),
    ]
    recorder = subprocess.Popen(ffmpeg_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    start = time.monotonic()
    try:
        for action in sorted(scene.get("actions", []), key=lambda item: float(item["at"])):
            while time.monotonic() - start < float(action["at"]):
                time.sleep(0.02)
            execute_capture_action(profile, action)

        target_duration = duration + float(profile.get("record_tail_seconds", 0.6))
        while time.monotonic() - start < target_duration:
            time.sleep(0.05)
    finally:
        recorder.send_signal(signal.SIGINT)
        recorder.wait(timeout=15)

    require_file(output_path, "captured scene output")
    apply_click_highlights(scene, output_path)
    apply_shortcut_overlays(scene, output_path)
    publish_scene_capture(scene, output_path)
    return output_path


def cover_filter(width: int, height: int, fps: int) -> str:
    return (
        f"fps={fps},"
        f"scale={width}:{height}:force_original_aspect_ratio=increase,"
        f"crop={width}:{height},"
        "format=yuv420p"
    )


def font_for(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    text: str,
    *,
    font: ImageFont.FreeTypeFont,
    fill: str,
) -> None:
    left, top, right, bottom = box
    bbox = draw.multiline_textbbox((0, 0), text, font=font, align="center", spacing=0)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x = left + (right - left - width) / 2
    y = top + (bottom - top - height) / 2
    draw.multiline_text((x, y), text, font=font, fill=fill, align="center")


def render_shortcut_intro_card(
    template: dict[str, Any],
    title: str,
    lines: list[str],
    output_path: Path,
) -> None:
    width, height = template.get("size", [1920, 1080])
    image = Image.new("RGB", (int(width), int(height)), ImageColor.getrgb(template.get("background_color", DEFAULT_TEMPLATE_BG)))
    draw = ImageDraw.Draw(image)

    panel = template["panel"]
    panel_width = int(panel["width"])
    panel_height = int(panel["height"])
    panel_left = (int(width) - panel_width) // 2
    panel_top = (int(height) - panel_height) // 2
    panel_box = (panel_left, panel_top, panel_left + panel_width, panel_top + panel_height)
    draw.rounded_rectangle(panel_box, radius=int(panel["radius"]), fill=panel["color"])

    title_style = template["title"]
    title_font = font_for(str(title_style["font"]), int(title_style["size"]))
    title_y = panel_top + int(panel_height * 0.14) + int(title_style.get("offset_y", 0))
    title_box = (
        panel_left + 80,
        title_y,
        panel_left + panel_width - 80,
        title_y + 96,
    )
    draw_centered_text(
        draw,
        title_box,
        title,
        font=title_font,
        fill=title_style["color"],
    )

    line_style = template["line"]
    line_font = font_for(str(line_style["font"]), int(line_style["size"]))
    start_y = panel_top + int(panel_height * 0.42)
    gap = int(line_style.get("gap", 56))
    for index, line in enumerate(lines):
        line_box = (
            panel_left + 80,
            start_y + index * gap,
            panel_left + panel_width - 80,
            start_y + index * gap + 72,
        )
        draw_centered_text(draw, line_box, line, font=line_font, fill=line_style["color"])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)


def render_card_image(template_id: str, item: dict[str, Any], output_path: Path) -> Path:
    template = load_template(template_id)
    if template["kind"] != "shortcut_intro":
        raise PipelineError(f"Unsupported card template kind: {template['kind']}")

    title = str(item.get("title", "")).strip()
    lines = [str(value) for value in item.get("lines", [])]
    render_shortcut_intro_card(template, title, lines, output_path)
    return output_path


def render_card_segment(
    template_id: str,
    item: dict[str, Any],
    output_path: Path,
    *,
    fps: int,
    width: int,
    height: int,
) -> Path:
    image_path = output_path.with_suffix(".png")
    render_card_image(template_id, item, image_path)
    run(
        [
            "ffmpeg",
            "-y",
            "-loop",
            "1",
            "-t",
            str(item["duration"]),
            "-i",
            str(image_path),
            "-vf",
            cover_filter(width, height, fps),
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(output_path),
        ],
        check=True,
    )
    return output_path


def resolve_scene_source(scene_id: str, run_id: str) -> Path:
    raw_path = raw_scene_path(scene_id, run_id)
    if raw_path.exists():
        return raw_path

    scene = load_scene(scene_id)
    fallback_source = scene.get("fallback_source_clip")
    if not fallback_source:
        raise PipelineError(
            f"No captured raw clip for scene '{scene_id}' in run '{run_id}', and no fallback_source_clip is configured."
        )
    return require_file(REPO_ROOT / fallback_source, f"fallback source clip for {scene_id}")


def render_scene_segment(
    scene_id: str,
    run_id: str,
    item: dict[str, Any],
    output_path: Path,
    *,
    fps: int,
    width: int,
    height: int,
) -> Path:
    source_path = resolve_scene_source(scene_id, run_id)
    run(
        [
            "ffmpeg",
            "-y",
            "-ss",
            str(item["trim_start"]),
            "-to",
            str(item["trim_end"]),
            "-i",
            str(source_path),
            "-vf",
            cover_filter(width, height, fps),
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(output_path),
        ],
        check=True,
    )
    return output_path


def render_video(video_id: str, run_id: str) -> Path:
    ensure_directories()
    video = load_video(video_id)
    profile = load_profile(video["profile"])
    width, height = output_size(profile)
    fps = frame_rate(profile)

    segment_dir = cards_video_dir(video_id, run_id)
    segment_dir.mkdir(parents=True, exist_ok=True)
    segments: list[Path] = []

    for index, item in enumerate(video["sequence"]):
        item_type = item["type"]
        segment_path = segment_dir / f"{index:02d}-{item_type}.mp4"
        if item_type == "card":
            render_card_segment(
                str(item["template"]),
                item,
                segment_path,
                fps=fps,
                width=width,
                height=height,
            )
        elif item_type == "scene":
            render_scene_segment(
                str(item["scene"]),
                run_id,
                item,
                segment_path,
                fps=fps,
                width=width,
                height=height,
            )
        else:
            raise PipelineError(f"Unsupported sequence item type: {item_type}")
        segments.append(segment_path)

    concat_list = segment_dir / "segments.txt"
    concat_list.write_text("".join(f"file '{segment.resolve()}'\n" for segment in segments), encoding="utf-8")

    output_path = render_output_path(video_id, run_id)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_list),
            "-an",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(output_path),
        ],
        check=True,
    )
    return output_path


def ffprobe_stream(path: Path) -> dict[str, Any]:
    result = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_streams",
            "-show_format",
            str(path),
        ],
        check=True,
    )
    return json.loads(result.stdout)


def validate_video(video_id: str, run_id: str) -> dict[str, Any]:
    video = load_video(video_id)
    validate = video.get("validate", {})
    output = render_output_path(video_id, run_id)
    payload = ffprobe_stream(output)
    video_stream = next((stream for stream in payload["streams"] if stream.get("codec_type") == "video"), None)
    if video_stream is None:
        raise PipelineError(f"No video stream found in {output}")

    report = {
        "path": str(output),
        "width": int(video_stream["width"]),
        "height": int(video_stream["height"]),
        "frame_rate": video_stream["r_frame_rate"],
        "duration": float(payload["format"]["duration"]),
        "has_audio": any(stream.get("codec_type") == "audio" for stream in payload["streams"]),
    }

    if "resolution" in validate:
        expected_width, expected_height = validate["resolution"]
        if (report["width"], report["height"]) != (int(expected_width), int(expected_height)):
            raise PipelineError(
                f"Validation failed for {video_id}: got {report['width']}x{report['height']}, "
                f"expected {expected_width}x{expected_height}"
            )

    if "max_duration" in validate and report["duration"] > float(validate["max_duration"]) + 0.05:
        raise PipelineError(
            f"Validation failed for {video_id}: duration {report['duration']:.2f}s exceeds {validate['max_duration']}s"
        )

    if validate.get("audio") is False and report["has_audio"]:
        raise PipelineError(f"Validation failed for {video_id}: expected silent output")

    report_path = report_output_path(video_id, run_id)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def publish_video(video_id: str, run_id: str) -> list[Path]:
    video = load_video(video_id)
    output = render_output_path(video_id, run_id)
    published: list[Path] = []
    for destination in video.get("publish_to", []):
        destination_path = REPO_ROOT / destination
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(output, destination_path)
        published.append(destination_path)
    return published


def print_status(label: str, ok: bool, detail: str = "") -> None:
    status = "OK" if ok else "FAIL"
    suffix = f" - {detail}" if detail else ""
    print(f"[{status}] {label}{suffix}")


def doctor() -> int:
    checks = [
        ("ffmpeg", ["ffmpeg", "-version"]),
        ("ffprobe", ["ffprobe", "-version"]),
        ("osascript", ["osascript", "-e", 'return "ok"']),
        ("python yaml", [sys.executable, "-c", "import yaml; print('ok')"]),
        ("python pillow", [sys.executable, "-c", "from PIL import Image; print('ok')"]),
    ]
    failures = 0
    for label, command in checks:
        result = run(command, check=False)
        ok = result.returncode == 0
        print_status(label, ok)
        if not ok:
            failures += 1

    default_profile = load_profile(DEFAULT_PROFILE_ID)
    bundle = REPO_ROOT / default_profile["app_bundle_path"]
    print_status("integration app bundle", bundle.exists(), str(bundle))
    if not bundle.exists():
        failures += 1

    fallback_clip = REPO_ROOT / load_scene("overview-main")["fallback_source_clip"]
    print_status("overview fallback clip", fallback_clip.exists(), str(fallback_clip))
    if not fallback_clip.exists():
        failures += 1

    background = OVERVIEW_BACKGROUND_PATH
    print_status("overview background", background.exists(), str(background))
    if not background.exists():
        failures += 1

    print_status(
        "accessibility scripting",
        True,
        "not required for the current synthetic overview capture path",
    )
    return 1 if failures else 0


def build_video(video_id: str, run_id: str, *, recapture: bool) -> dict[str, Any]:
    if recapture:
        video = load_video(video_id)
        seen_scenes: set[str] = set()
        for item in video["sequence"]:
            if item["type"] == "scene":
                scene_id = str(item["scene"])
                if scene_id not in seen_scenes:
                    capture_scene(scene_id, run_id)
                    seen_scenes.add(scene_id)

    render_path = render_video(video_id, run_id)
    report = validate_video(video_id, run_id)
    published = publish_video(video_id, run_id)
    return {
        "render": render_path,
        "report": report,
        "published": published,
    }


def build_set(set_id: str, run_id: str, *, recapture: bool) -> list[dict[str, Any]]:
    data = load_set(set_id)
    results = []
    for video_id in data.get("videos", []):
        results.append(build_video(str(video_id), run_id, recapture=recapture))
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build marketing videos from manifests.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("doctor")

    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("--scene", required=True)
    capture_parser.add_argument("--run-id")

    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--video", required=True)
    render_parser.add_argument("--run-id")

    publish_parser = subparsers.add_parser("publish")
    publish_parser.add_argument("--video", required=True)
    publish_parser.add_argument("--run-id")

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--video", required=True)
    validate_parser.add_argument("--run-id")

    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--video", required=True)
    build_parser.add_argument("--run-id")
    build_parser.add_argument("--recapture", action="store_true")

    build_set_parser = subparsers.add_parser("build-set")
    build_set_parser.add_argument("--set", required=True)
    build_set_parser.add_argument("--run-id")
    build_set_parser.add_argument("--recapture", action="store_true")

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    ensure_directories()

    if args.command == "doctor":
        return doctor()

    run_id = getattr(args, "run_id", None) or now_run_id()

    if args.command == "capture":
        path = capture_scene(args.scene, run_id)
        print(path)
        return 0

    if args.command == "render":
        path = render_video(args.video, run_id)
        print(path)
        return 0

    if args.command == "publish":
        for path in publish_video(args.video, run_id):
            print(path)
        return 0

    if args.command == "validate":
        report = validate_video(args.video, run_id)
        print(json.dumps(report, indent=2))
        return 0

    if args.command == "build":
        result = build_video(args.video, run_id, recapture=bool(args.recapture))
        print(result["render"])
        for path in result["published"]:
            print(path)
        return 0

    if args.command == "build-set":
        results = build_set(args.set, run_id, recapture=bool(args.recapture))
        for result in results:
            print(result["render"])
            for path in result["published"]:
                print(path)
        return 0

    raise PipelineError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PipelineError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
