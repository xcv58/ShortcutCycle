#!/usr/bin/env python3
"""Capture current website images with native controls and a composited HUD.

Use the disposable capture-1.11 app. Capture first, visually review every PNG,
then install the responsive WebP files. This does not deploy the website.
"""

import argparse
import hashlib
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

import video_pipeline as vp


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / ".artifacts/website-1.11"
SCENES = {
    "hud-light": ("hud-horizontal", "light"),
    "hud-dark": ("hud-horizontal", "dark"),
    "hud-grid-light": ("hud-grid", "light"),
    "hud-grid-dark": ("hud-grid", "dark"),
    "group-light": ("group", "light"),
    "group-dark": ("group", "dark"),
    "general-light": ("general", "light"),
    "general-dark": ("general", "dark"),
    "automatic-backups": ("backups", "light"),
    "automatic-backups-dark": ("backups", "dark"),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_preference(domain, key):
    result = subprocess.run(["defaults", "read", domain, key], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def activation_helper():
    source = OUTPUT / "activate.swift"
    executable = OUTPUT / "activate"
    source.write_text('''import AppKit
import ApplicationServices
guard let pid = Int32(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else { exit(1) }
let element = AXUIElementCreateApplication(pid)
var value: CFTypeRef?
if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
   let windows = value as? [AXUIElement], let window = windows.first {
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
}
app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
Thread.sleep(forTimeInterval: 0.5)
guard app.isActive else { exit(1) }
''')
    subprocess.run(["swiftc", str(source), "-o", str(executable)], check=True)
    return executable


def capture(region):
    profile = vp.load_profile("capture-1.11")
    if vp.bundle_id(profile) != "com.xcv58.ShortcutCycle.capture" or profile.get("sandboxed") is not False:
        raise RuntimeError("Website capture requires the disposable, non-sandboxed capture app")
    binary = vp.app_bundle_path(profile) / "Contents/MacOS/ShortcutCycle"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    activate = activation_helper()
    # An incomplete recapture must not leave an installable old manifest.
    (OUTPUT / "capture-report.json").unlink(missing_ok=True)
    was_running = bool(vp.integration_process_ids(profile))
    vp.quit_integration_app(profile)
    backup = vp.backup_integration_settings(
        profile, "website", datetime.now().strftime("%Y%m%d-%H%M%S"), was_running=was_running
    )
    backdrop = None
    report = {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "binary_sha256": digest(binary),
        "bundle_id": vp.bundle_id(profile),
        "macos": subprocess.check_output(["sw_vers"], text=True).strip(),
        "hud_capture_region_points": region,
        "glass_tint": read_preference("-g", "NSGlassTintAmount"),
        "reduce_transparency": read_preference("com.apple.universalaccess", "reduceTransparency"),
        "increase_contrast": read_preference("com.apple.universalaccess", "increaseContrast"),
        "images": {},
    }
    try:
        for name, (scene, theme) in SCENES.items():
            # Exiting the previous capture app can raise the user's previous app.
            # Re-create the backdrop for each scene so it is above those windows.
            vp.stop_process(backdrop)
            backdrop = vp.start_capture_backdrop(str(vp.OVERVIEW_BACKGROUND_PATH))
            info = OUTPUT / f"{name}.json"
            output = OUTPUT / f"{name}.png"
            info.unlink(missing_ok=True)
            output.unlink(missing_ok=True)
            with (OUTPUT / f"{name}.log").open("w") as log:
                app = subprocess.Popen([
                    str(binary), "--screenshot-scene", scene,
                    "--screenshot-theme", theme, "--screenshot-language", "en",
                    "--screenshot-output", str(output), "--screenshot-window-info", str(info),
                    "--screenshot-background", str(vp.OVERVIEW_BACKGROUND_PATH),
                ], stdout=log, stderr=log, cwd=OUTPUT)
                try:
                    deadline = time.monotonic() + 15
                    while not info.exists():
                        if app.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError(f"Capture window unavailable: {name}; see its log")
                        time.sleep(0.1)
                    window = json.loads(info.read_text())["windowNumber"]
                    time.sleep(1)
                    if not scene.startswith("hud-"):
                        subprocess.run([str(activate), str(app.pid)], check=True)
                    command = ["/usr/sbin/screencapture", "-x"]
                    if scene.startswith("hud-"):
                        # Capture the actual desktop composition, including the background
                        # that the system sampled for Liquid Glass. Never paste a HUD cutout.
                        command += [f"-R{region}"]
                    else:
                        command += ["-o", "-l", str(window)]
                    subprocess.run(command + [str(output)], check=True)
                    with Image.open(output) as image:
                        if image.size != (2880, 1800):
                            raise RuntimeError(f"Expected Retina 2880x1800 capture: {name}: {image.size}")
                    report["images"][name] = {"scene": scene, "theme": theme, "sha256": digest(output)}
                    print(f"Captured {name}", flush=True)
                finally:
                    vp.stop_process(app)
    finally:
        vp.stop_process(backdrop)
        vp.restore_integration_settings(profile, backup)
    report["capture_preferences_restored"] = True
    (OUTPUT / "capture-report.json").write_text(json.dumps(report, indent=2) + "\n")


def install():
    report = json.loads((OUTPUT / "capture-report.json").read_text())
    # Validate the complete set before replacing any website assets.
    for name in SCENES:
        if digest(OUTPUT / f"{name}.png") != report["images"][name]["sha256"]:
            raise RuntimeError(f"Capture changed since manifest was written: {name}")
    report["web_images"] = {}
    for name in SCENES:
        with Image.open(OUTPUT / f"{name}.png") as original:
            for suffix, width in [("", 1800), ("-small", 900)]:
                size = (width, int(original.height * width / original.width))
                image = original.resize(size, Image.Resampling.LANCZOS)
                destination = ROOT / f"docs/assets/images/{name}{suffix}.webp"
                image.save(destination, "WEBP", quality=80)
                report["web_images"][destination.name] = {
                    "size": size, "sha256": digest(destination), "bytes": destination.stat().st_size
                }
        print(f"Installed {name} and mobile variant")
    report_path = ROOT / "marketing/screenshots/1.11/capture-report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    recording = subcommands.add_parser("capture")
    recording.add_argument("--region", required=True, help="1440x900 screen region in points, e.g. 36,41,1440,900")
    subcommands.add_parser("install")
    args = parser.parse_args()
    if args.command == "capture":
        coordinates = [int(value) for value in args.region.split(",")]
        if len(coordinates) != 4 or coordinates[2:] != [1440, 900]:
            parser.error("Use a 1440x900 region on a Retina display")
        capture(args.region)
    else:
        install()
