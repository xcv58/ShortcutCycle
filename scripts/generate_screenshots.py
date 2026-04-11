#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageColor, ImageDraw, ImageFilter


SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent
PACKAGE_ROOT = REPO_ROOT / "ShortcutCycle"
BUILD_DIR = PACKAGE_ROOT / ".build" / "debug"
APP_BINARY = BUILD_DIR / "ShortcutCycle"
RAW_SCREENSHOTS_DIR = PACKAGE_ROOT / "App Store Connect Assets" / "Screenshots"
OPTIMIZE_SCRIPT = REPO_ROOT / "scripts" / "optimize_images.py"
BACKGROUND_IMAGE_PATH = REPO_ROOT / "scripts" / "assets" / "background.jpeg"
OUTPUT_SIZE = (2880, 1800)


@dataclass(frozen=True)
class CaptureSpec:
    filename: str
    scene: str
    theme: str
    language: str = "en"
    group: str | None = None
    variant: str | None = None


DIRECT_CAPTURES = [
    CaptureSpec("General Light.png", "general", "light"),
    CaptureSpec("General Dark.png", "general", "dark"),
    CaptureSpec("Group Light.png", "group", "light"),
    CaptureSpec("Group Dark.png", "group", "dark"),
    CaptureSpec("Automatic Backups.png", "backups", "light"),
    CaptureSpec("Automatic Backups Dark.png", "backups", "dark"),
]


HUD_SOURCE_CAPTURES = [
    CaptureSpec("__hud_light_window.png", "hud-horizontal", "light"),
    CaptureSpec("__hud_dark_window.png", "hud-horizontal", "dark"),
    CaptureSpec("__hud_grid_light_window.png", "hud-grid", "light"),
    CaptureSpec("__hud_grid_dark_window.png", "hud-grid", "dark"),
]


COMPOSITE_SOURCE_CAPTURES = [
    CaptureSpec("__menu_light_default.png", "menu-popover", "light"),
    CaptureSpec("__menu_dark_default.png", "menu-popover", "dark"),
    CaptureSpec("__menu_light_selected.png", "menu-popover", "light", group="utilities", variant="selected"),
    CaptureSpec("__menu_dark_selected.png", "menu-popover", "dark", group="utilities", variant="selected"),
    CaptureSpec("__general_en.png", "general", "light", language="en"),
    CaptureSpec("__general_de.png", "general", "light", language="de"),
    CaptureSpec("__general_fr.png", "general", "light", language="fr"),
    CaptureSpec("__general_es.png", "general", "light", language="es"),
    CaptureSpec("__general_ja.png", "general", "light", language="ja"),
    CaptureSpec("__general_ko.png", "general", "light", language="ko"),
    CaptureSpec("__general_zh_hans.png", "general", "light", language="zh-Hans"),
    CaptureSpec("__general_zh_hant.png", "general", "light", language="zh-Hant"),
]


FINAL_SCREENSHOT_FILENAMES = [spec.filename for spec in DIRECT_CAPTURES] + [
    "HUD Light.png",
    "HUD Dark.png",
    "HUD-Grid Light.png",
    "HUD-Grid Dark.png",
    "Menu Bar.png",
    "Multiple Languages.png",
]


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        text=True,
        capture_output=True,
    )


def build_app() -> None:
    print("Building ShortcutCycle screenshot harness...")
    result = run(["swift", "build"], cwd=PACKAGE_ROOT)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())


def validate_png_dimensions(path: Path) -> None:
    with Image.open(path) as image:
        if image.size != OUTPUT_SIZE:
            raise RuntimeError(f"{path.name} has size {image.size}, expected {OUTPUT_SIZE}")


def screenshot_environment(home_dir: Path) -> dict[str, str]:
    env = dict(os.environ)
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")
    env["CFFIXED_USER_HOME"] = str(home_dir)
    return env


def terminate_process(process: subprocess.Popen[str]) -> tuple[str, str]:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    stdout, stderr = process.communicate()
    return stdout, stderr


def wait_for_window_info(process: subprocess.Popen[str], window_info_path: Path, timeout_seconds: float) -> dict[str, int]:
    deadline = time.monotonic() + timeout_seconds

    while time.monotonic() < deadline:
        if window_info_path.exists():
            try:
                return json.loads(window_info_path.read_text())
            except json.JSONDecodeError:
                pass

        if process.poll() is not None:
            stdout, stderr = terminate_process(process)
            raise RuntimeError(
                f"Screenshot app exited before window info was ready.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}"
            )

        time.sleep(0.05)

    stdout, stderr = terminate_process(process)
    raise RuntimeError(
        f"Timed out waiting for window info for {window_info_path.name}.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}"
    )


def run_internal_capture(
    spec: CaptureSpec,
    output_path: Path,
    scratch_home: Path,
    *,
    expected_size: tuple[int, int] | None = OUTPUT_SIZE,
) -> None:
    command = [
        str(APP_BINARY),
        "--screenshot-scene", spec.scene,
        "--screenshot-theme", spec.theme,
        "--screenshot-language", spec.language,
        "--screenshot-output", str(output_path),
    ]

    if spec.group:
        command.extend(["--screenshot-group", spec.group])
    if spec.variant:
        command.extend(["--screenshot-variant", spec.variant])
    if BACKGROUND_IMAGE_PATH.exists():
        command.extend(["--screenshot-background", str(BACKGROUND_IMAGE_PATH)])

    env = screenshot_environment(scratch_home)
    result = subprocess.run(
        command,
        cwd=PACKAGE_ROOT,
        env=env,
        check=True,
        text=True,
        capture_output=True,
        timeout=25,
    )

    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())

    if expected_size is not None:
        validate_png_dimensions(output_path)


def run_capture(
    spec: CaptureSpec,
    output_path: Path,
    scratch_home: Path,
    *,
    expected_size: tuple[int, int] | None = OUTPUT_SIZE,
    allow_internal_fallback: bool = True,
) -> None:
    output_path.unlink(missing_ok=True)
    window_info_path = scratch_home / "window-info.json"
    command = [
        str(APP_BINARY),
        "--screenshot-scene", spec.scene,
        "--screenshot-theme", spec.theme,
        "--screenshot-language", spec.language,
        "--screenshot-output", str(output_path),
        "--screenshot-window-info", str(window_info_path),
    ]

    if spec.group:
        command.extend(["--screenshot-group", spec.group])
    if spec.variant:
        command.extend(["--screenshot-variant", spec.variant])
    if BACKGROUND_IMAGE_PATH.exists():
        command.extend(["--screenshot-background", str(BACKGROUND_IMAGE_PATH)])

    env = screenshot_environment(scratch_home)

    for attempt in range(3):
        window_info_path.unlink(missing_ok=True)
        process = subprocess.Popen(
            command,
            cwd=PACKAGE_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        try:
            window_info = wait_for_window_info(process, window_info_path, timeout_seconds=20)
            window_number = int(window_info["windowNumber"])

            capture_result = subprocess.run(
                ["screencapture", "-x", "-o", "-l", str(window_number), str(output_path)],
                cwd=REPO_ROOT,
                check=True,
                text=True,
                capture_output=True,
                timeout=10,
            )

            if expected_size is not None:
                validate_png_dimensions(output_path)
            stdout, stderr = terminate_process(process)
            if capture_result.stdout.strip():
                print(capture_result.stdout.strip())
            if capture_result.stderr.strip():
                print(capture_result.stderr.strip())
            if stdout.strip():
                print(stdout.strip())
            if stderr.strip():
                print(stderr.strip())
            time.sleep(0.2)
            return
        except Exception as error:  # noqa: BLE001
            stdout, stderr = terminate_process(process)
            if attempt < 2:
                print(f"External capture retry for {spec.filename}: {error}")
                if stdout.strip():
                    print(stdout.strip())
                if stderr.strip():
                    print(stderr.strip())
                time.sleep(0.25)
                continue

            if not allow_internal_fallback:
                raise RuntimeError(
                    f"External capture failed for {spec.filename}: {error}\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}"
                ) from error

            print(f"Falling back to internal capture for {spec.filename}: {error}")
            if stdout.strip():
                print(stdout.strip())
            if stderr.strip():
                print(stderr.strip())
            run_internal_capture(spec, output_path, scratch_home, expected_size=expected_size)
            time.sleep(0.2)
            return

    raise RuntimeError(f"Failed to capture {spec.filename}")


def resize_panel(image: Image.Image, width: int) -> Image.Image:
    ratio = width / image.width
    return image.resize((width, round(image.height * ratio)), Image.Resampling.LANCZOS)


def crop_box(image: Image.Image, *, left: float, top: float, right: float, bottom: float) -> Image.Image:
    width, height = image.size
    return image.crop(
        (
            round(width * left),
            round(height * top),
            round(width * right),
            round(height * bottom),
        )
    )


def trim_uniform_background(image: Image.Image, *, threshold: int = 18, padding: int = 0) -> Image.Image:
    rgba = image.convert("RGBA")
    background_rgb = rgba.getpixel((0, 0))[:3]
    background = Image.new("RGB", rgba.size, background_rgb)
    diff = ImageChops.difference(rgba.convert("RGB"), background)
    r, g, b = diff.split()
    contrast = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mask = contrast.point(lambda value: 255 if value > threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        return rgba

    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(rgba.width, bbox[2] + padding)
    bottom = min(rgba.height, bbox[3] + padding)
    return rgba.crop((left, top, right, bottom))


def crop_to_alpha_bounds(image: Image.Image, *, padding: int = 0) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        return rgba

    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(rgba.width, bbox[2] + padding)
    bottom = min(rgba.height, bbox[3] + padding)
    return rgba.crop((left, top, right, bottom))


def validate_crop_content(
    image: Image.Image,
    *,
    label: str,
    difference_threshold: int = 12,
    minimum_non_uniform_ratio: float = 0.01,
) -> None:
    rgba = image.convert("RGBA")
    if rgba.width == 0 or rgba.height == 0:
        print(f"Warning: {label} crop is empty; verify crop bounds.")
        return

    reference_pixel = rgba.getpixel((0, 0))
    background = Image.new("RGBA", rgba.size, reference_pixel)
    diff = ImageChops.difference(rgba, background).convert("L")
    mask = diff.point(lambda value: 255 if value > difference_threshold else 0)
    histogram = mask.histogram()
    non_uniform_pixels = sum(histogram[1:])
    non_uniform_ratio = non_uniform_pixels / max(rgba.width * rgba.height, 1)

    if non_uniform_ratio < minimum_non_uniform_ratio:
        print(
            f"Warning: {label} crop appears mostly uniform "
            f"({non_uniform_ratio:.1%} non-uniform pixels); verify crop bounds."
        )


def apply_rounded_mask(image: Image.Image, *, radius: int) -> Image.Image:
    panel = image.convert("RGBA")
    mask = Image.new("L", panel.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, panel.width - 1, panel.height - 1), radius=radius, fill=255)
    panel.putalpha(mask)
    return panel


def add_outline(
    image: Image.Image,
    *,
    radius: int,
    color: tuple[int, int, int, int],
    width: int = 2,
) -> Image.Image:
    panel = image.convert("RGBA")
    overlay = Image.new("RGBA", panel.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    inset = max(width // 2, 1)
    draw.rounded_rectangle(
        (inset, inset, panel.width - inset - 1, panel.height - inset - 1),
        radius=max(radius - inset, 0),
        outline=color,
        width=width,
    )
    return Image.alpha_composite(panel, overlay)


def add_shadow(
    image: Image.Image,
    blur_radius: int = 28,
    offset: tuple[int, int] = (0, 18),
    opacity: int = 90,
    color: tuple[int, int, int] = (18, 26, 32),
) -> Image.Image:
    base = image.convert("RGBA")
    shadow_padding = blur_radius * 3
    canvas = Image.new(
        "RGBA",
        (
            base.width + shadow_padding * 2,
            base.height + shadow_padding * 2 + offset[1],
        ),
        (0, 0, 0, 0),
    )

    shadow = Image.new("RGBA", base.size, color + (opacity,))
    shadow.putalpha(base.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius))
    shadow_position = (shadow_padding + offset[0], shadow_padding + offset[1])
    canvas.alpha_composite(shadow, shadow_position)
    canvas.alpha_composite(base, (shadow_padding, shadow_padding))
    return canvas


def add_outer_shadow(
    image: Image.Image,
    blur_radius: int = 28,
    offset: tuple[int, int] = (0, 18),
    opacity: int = 90,
    color: tuple[int, int, int] = (18, 26, 32),
) -> Image.Image:
    base = image.convert("RGBA")
    shadow_padding = blur_radius * 3
    canvas = Image.new(
        "RGBA",
        (
            base.width + shadow_padding * 2,
            base.height + shadow_padding * 2 + abs(offset[1]) + abs(offset[0]),
        ),
        (0, 0, 0, 0),
    )

    base_alpha = base.getchannel("A")
    blurred_alpha = base_alpha.filter(ImageFilter.GaussianBlur(blur_radius))
    outer_alpha = ImageChops.subtract(blurred_alpha, base_alpha)
    if opacity != 255:
        outer_alpha = outer_alpha.point(lambda value: round(value * (opacity / 255)))

    shadow = Image.new("RGBA", base.size, color + (0,))
    shadow.putalpha(outer_alpha)
    shadow_position = (shadow_padding + max(offset[0], 0), shadow_padding + max(offset[1], 0))
    base_position = (shadow_padding - min(offset[0], 0), shadow_padding - min(offset[1], 0))

    canvas.alpha_composite(shadow, shadow_position)
    canvas.alpha_composite(base, base_position)
    return canvas


def make_vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    width, height = size
    top_rgb = ImageColor.getrgb(top)
    bottom_rgb = ImageColor.getrgb(bottom)
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        mix = y / max(height - 1, 1)
        color = tuple(round(top_rgb[index] * (1 - mix) + bottom_rgb[index] * mix) for index in range(3))
        draw.line((0, y, width, y), fill=color + (255,))
    return image


def make_photo_background(size: tuple[int, int], *, blur_radius: float = 0) -> Image.Image:
    if not BACKGROUND_IMAGE_PATH.exists():
        return make_vertical_gradient(size, "#d9e4ef", "#eef3f8")

    with Image.open(BACKGROUND_IMAGE_PATH) as source:
        source = source.convert("RGBA")
        ratio = max(size[0] / source.width, size[1] / source.height)
        resized = source.resize(
            (round(source.width * ratio), round(source.height * ratio)),
            Image.Resampling.LANCZOS,
        )
        left = (resized.width - size[0]) // 2
        top = (resized.height - size[1]) // 2
        background = resized.crop((left, top, left + size[0], top + size[1]))

    if blur_radius > 0:
        background = background.filter(ImageFilter.GaussianBlur(blur_radius))

    return background


def add_blur_orb(canvas: Image.Image, bbox: tuple[int, int, int, int], color: tuple[int, int, int, int], blur_radius: int) -> None:
    orb = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(orb).ellipse(bbox, fill=color)
    canvas.alpha_composite(orb.filter(ImageFilter.GaussianBlur(blur_radius)))


def rotated_panel(
    image: Image.Image,
    angle: float,
    shadow_blur: int = 26,
    shadow_opacity: int = 44,
    shadow_offset: tuple[int, int] = (0, 10),
) -> Image.Image:
    panel = image.convert("RGBA").rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
    panel = add_outer_shadow(panel, blur_radius=shadow_blur, offset=shadow_offset, opacity=shadow_opacity)
    return crop_to_alpha_bounds(panel, padding=2)


# Crop the General settings application panel used for the foreground cards in
# the multi-language composite.
def crop_general_application_panel(image: Image.Image) -> Image.Image:
    panel = crop_box(image.convert("RGBA"), left=0.195, top=0.555, right=0.845, bottom=0.79)
    validate_crop_content(panel, label="general application panel")
    return panel


# Crop the General settings language controls strip when validating the
# localized language row framing.
def crop_general_language_strip(image: Image.Image) -> Image.Image:
    panel = crop_box(image.convert("RGBA"), left=0.21, top=0.60, right=0.845, bottom=0.735)
    validate_crop_content(panel, label="general language strip")
    return panel


def crop_full_window_capture(image: Image.Image) -> Image.Image:
    return crop_box(image.convert("RGBA"), left=0.004, top=0.001, right=0.996, bottom=0.989)


def compress_panel_width(image: Image.Image, factor: float) -> Image.Image:
    panel = image.convert("RGBA")
    compressed_width = max(1, round(panel.width * factor))
    return panel.resize((compressed_width, panel.height), Image.Resampling.LANCZOS)


def compose_hud_capture(output_path: Path, capture_path: Path) -> None:
    canvas = make_photo_background(OUTPUT_SIZE)

    with Image.open(capture_path) as original:
        panel = crop_to_alpha_bounds(original)
        if panel.size == original.size:
            panel = trim_uniform_background(original, threshold=12, padding=0)

    position = ((OUTPUT_SIZE[0] - panel.width) // 2, (OUTPUT_SIZE[1] - panel.height) // 2)
    canvas.alpha_composite(panel, position)
    canvas.convert("RGB").save(output_path, "PNG")
    validate_png_dimensions(output_path)


def compose_menubar_languages(output_path: Path, temp_dir: Path) -> None:
    canvas = make_photo_background(OUTPUT_SIZE, blur_radius=1.0)

    with Image.open(temp_dir / "__menu_dark_selected.png") as original:
        hero_menu = resize_panel(original.convert("RGBA"), 1080)
        hero_menu = apply_rounded_mask(hero_menu, radius=34)
        hero_menu = add_outline(hero_menu, radius=34, color=(255, 255, 255, 16), width=2)
        hero_menu = add_outer_shadow(hero_menu, blur_radius=36, offset=(0, 0), opacity=14, color=(9, 15, 22))
        hero_menu = crop_to_alpha_bounds(hero_menu, padding=2)

    with Image.open(temp_dir / "__menu_light_default.png") as original:
        support_menu = resize_panel(original.convert("RGBA"), 660)
        support_menu = apply_rounded_mask(support_menu, radius=28)
        support_menu = add_outline(support_menu, radius=28, color=(12, 18, 26, 20), width=2)
        support_menu = add_outer_shadow(support_menu, blur_radius=30, offset=(0, 0), opacity=12, color=(9, 15, 22))
        support_menu = crop_to_alpha_bounds(support_menu, padding=2)

    with Image.open(temp_dir / "__menu_light_selected.png") as original:
        support_selected = resize_panel(original.convert("RGBA"), 680)
        support_selected = apply_rounded_mask(support_selected, radius=28)
        support_selected = add_outline(support_selected, radius=28, color=(12, 18, 26, 20), width=2)
        support_selected = add_outer_shadow(support_selected, blur_radius=30, offset=(0, 0), opacity=12, color=(9, 15, 22))
        support_selected = crop_to_alpha_bounds(support_selected, padding=2)

    canvas.alpha_composite(hero_menu, (30, 90))
    canvas.alpha_composite(support_menu, (2050, 110))
    canvas.alpha_composite(support_selected, (1860, 720))

    canvas.convert("RGB").save(output_path, "PNG")
    validate_png_dimensions(output_path)


def compose_multiple_languages(output_path: Path, temp_dir: Path) -> None:
    canvas = make_photo_background(OUTPUT_SIZE, blur_radius=1.0)
    back_card_width_factor = 0.86

    stacked_windows = [
        ("__general_fr.png", 1320, 15, 110, -5.5),
        ("__general_ko.png", 1320, 1545, 110, 5.5),
        ("__general_ja.png", 1880, 500, 215, 0),
    ]

    for filename, width, x, y, angle in stacked_windows:
        with Image.open(temp_dir / filename) as original:
            panel = crop_full_window_capture(original)
            panel = resize_panel(panel, round(width / back_card_width_factor))
            panel = compress_panel_width(panel, back_card_width_factor)
            panel = apply_rounded_mask(panel, radius=38)
            panel = add_outline(panel, radius=38, color=(12, 18, 26, 14), width=2)
            panel = rotated_panel(panel, angle, shadow_blur=30, shadow_opacity=10, shadow_offset=(0, 0))
            canvas.alpha_composite(panel, (x, y))

    foreground_panels = [
        ("__general_de.png", 1180, 10, 1285, -3.5),
        ("__general_zh_hans.png", 1296, 795, 1180, 0),
        ("__general_zh_hant.png", 1180, 1688, 1285, 3.5),
    ]

    for filename, width, x, y, angle in foreground_panels:
        with Image.open(temp_dir / filename) as original:
            panel = crop_general_application_panel(original)
            panel = resize_panel(panel, width)
            panel = apply_rounded_mask(panel, radius=28)
            panel = add_outline(panel, radius=28, color=(12, 18, 26, 18), width=2)
            if angle != 0:
                panel = rotated_panel(panel, angle, shadow_blur=28, shadow_opacity=11, shadow_offset=(0, 0))
            else:
                panel = add_outer_shadow(panel, blur_radius=28, offset=(0, 0), opacity=11, color=(9, 15, 22))
                panel = crop_to_alpha_bounds(panel, padding=2)
            canvas.alpha_composite(panel, (x, y))

    canvas.convert("RGB").save(output_path, "PNG")
    validate_png_dimensions(output_path)


def refresh_web_assets() -> None:
    print("Refreshing website images...")
    result = run([sys.executable, str(OPTIMIZE_SCRIPT)], cwd=REPO_ROOT)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())


def remove_temporary_screenshots(temp_dir: Path) -> None:
    for path in temp_dir.iterdir():
        if path.suffix.lower() == ".png":
            path.unlink()


def main() -> int:
    try:
        build_app()

        RAW_SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)

        with tempfile.TemporaryDirectory(prefix="shortcutcycle-screenshots-") as temp_root_raw:
            temp_root = Path(temp_root_raw)
            temp_capture_dir = temp_root / "captures"
            temp_capture_dir.mkdir(parents=True, exist_ok=True)

            print("Generating direct screenshots...")
            for spec in DIRECT_CAPTURES:
                output_path = RAW_SCREENSHOTS_DIR / spec.filename
                scratch_home = temp_root / f"home-{output_path.stem.replace(' ', '-').lower()}"
                (scratch_home / "tmp").mkdir(parents=True, exist_ok=True)
                run_capture(spec, output_path, scratch_home)
                print(f"  wrote {output_path.name}")

            print("Generating HUD source captures...")
            for spec in HUD_SOURCE_CAPTURES:
                output_path = temp_capture_dir / spec.filename
                scratch_home = temp_root / f"home-{output_path.stem.replace(' ', '-').lower()}"
                (scratch_home / "tmp").mkdir(parents=True, exist_ok=True)
                run_capture(
                    spec,
                    output_path,
                    scratch_home,
                    expected_size=None,
                    allow_internal_fallback=False,
                )
                print(f"  staged {output_path.name}")

            print("Generating composite source captures...")
            for spec in COMPOSITE_SOURCE_CAPTURES:
                output_path = temp_capture_dir / spec.filename
                scratch_home = temp_root / f"home-{output_path.stem.replace(' ', '-').lower()}"
                (scratch_home / "tmp").mkdir(parents=True, exist_ok=True)
                run_capture(
                    spec,
                    output_path,
                    scratch_home,
                    expected_size=None if spec.scene == "menu-popover" else OUTPUT_SIZE,
                    allow_internal_fallback=spec.scene != "menu-popover",
                )
                print(f"  staged {output_path.name}")

            print("Composing derived screenshots...")
            compose_hud_capture(RAW_SCREENSHOTS_DIR / "HUD Light.png", temp_capture_dir / "__hud_light_window.png")
            compose_hud_capture(RAW_SCREENSHOTS_DIR / "HUD Dark.png", temp_capture_dir / "__hud_dark_window.png")
            compose_hud_capture(RAW_SCREENSHOTS_DIR / "HUD-Grid Light.png", temp_capture_dir / "__hud_grid_light_window.png")
            compose_hud_capture(RAW_SCREENSHOTS_DIR / "HUD-Grid Dark.png", temp_capture_dir / "__hud_grid_dark_window.png")
            compose_menubar_languages(RAW_SCREENSHOTS_DIR / "Menu Bar.png", temp_capture_dir)
            compose_multiple_languages(RAW_SCREENSHOTS_DIR / "Multiple Languages.png", temp_capture_dir)

            print("Validating final screenshot dimensions...")
            for filename in FINAL_SCREENSHOT_FILENAMES:
                path = RAW_SCREENSHOTS_DIR / filename
                validate_png_dimensions(path)
                print(f"  validated {filename}")

            refresh_web_assets()
            remove_temporary_screenshots(temp_capture_dir)

        print("Screenshot generation complete.")
        return 0
    except subprocess.CalledProcessError as error:
        print(error.stdout)
        print(error.stderr, file=sys.stderr)
        print(f"Screenshot generation failed while running: {' '.join(error.cmd)}", file=sys.stderr)
        return error.returncode or 1
    except Exception as error:  # noqa: BLE001
        print(f"Screenshot generation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
