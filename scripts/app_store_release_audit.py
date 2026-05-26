#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError:
    Image = None


REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_ROOT = REPO_ROOT / "ShortcutCycle"
ASSETS_ROOT = PACKAGE_ROOT / "App Store Connect Assets"
SCREENSHOTS_DIR = ASSETS_ROOT / "Screenshots"
PREVIEW_VIDEOS_DIR = ASSETS_ROOT / "Preview Videos"
DOCS_VIDEOS_DIR = REPO_ROOT / "docs" / "assets" / "videos"
METADATA_PATH = PACKAGE_ROOT / "AppStoreMetadata.md"
RELEASE_MANIFEST_PATH = PACKAGE_ROOT / "AppStoreRelease.json"
PROJECT_PATH = PACKAGE_ROOT / "ShortcutCycle.xcodeproj" / "project.pbxproj"
APP_ICON_PATH = PACKAGE_ROOT / "ShortcutCycle" / "Assets.xcassets" / "AppIcon.appiconset" / "1024.png"

EXPECTED_PREVIEW_COUNT = 3
EXPECTED_SCREENSHOT_SLOTS = 10
EXPECTED_SCREENSHOT_SIZE = (2880, 1800)
MAX_PREVIEW_DURATION_SECONDS = 30.0
MIN_PREVIEW_DURATION_SECONDS = 15.0
EXPECTED_PREVIEW_SIZE = (1920, 1080)
APP_PREVIEW_AUDIO_SAMPLE_RATES = {44100, 48000}
APP_PREVIEW_AUDIO_MIN_BITRATE = 192_000
APP_PREVIEW_VIDEO_MIN_BITRATE = 9_000_000


@dataclass
class Finding:
    severity: str
    code: str
    message: str
    detail: str | None = None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def strip_markdown(text: str) -> str:
    cleaned_lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line == "---":
            cleaned_lines.append("")
            continue
        line = re.sub(r"^#{1,6}\s+", "", line)
        line = re.sub(r"^[*-]\s+", "", line)
        line = re.sub(r"^\d+\.\s+", "", line)
        line = re.sub(r"`([^`]+)`", r"\1", line)
        line = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines).strip()


def normalize_text(text: str) -> str:
    replacements = str.maketrans(
        {
            "\u2018": "'",
            "\u2019": "'",
            "\u201c": '"',
            "\u201d": '"',
            "\u2013": "-",
            "\u2014": "-",
            "\u00a0": " ",
        }
    )
    text = strip_markdown(text).translate(replacements)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "So")
    return compact(text)


def short_hash(text: str) -> str:
    return hashlib.sha256(normalize_text(text).encode("utf-8")).hexdigest()[:12]


def unique_in_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def resolve_repo_path(path: str) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return REPO_ROOT / candidate


def load_release_manifest(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open(encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"Release manifest must be a JSON object: {path}")
    return payload


def release_text_source(local: dict[str, Any]) -> dict[str, str]:
    manifest = local.get("manifest")
    if isinstance(manifest, dict):
        text = manifest.get("text", {})
        if isinstance(text, dict) and text:
            return {
                "promotional_text": str(text.get("promotionalText", "")),
                "description": str(text.get("description", "")),
                "whats_new": str(text.get("whatsNew", "")),
                "keywords": str(text.get("keywords", "")),
                "support_url": str(text.get("supportUrl", "")),
                "marketing_url": str(text.get("marketingUrl", "")),
                "copyright": str(text.get("copyright", "")),
            }
    return local["metadata"]


def manifest_media_paths(manifest: dict[str, Any] | None, media_key: str, fallback_dir: Path, suffix: str) -> list[Path]:
    if isinstance(manifest, dict):
        media = manifest.get("media", {})
        values = media.get(media_key) if isinstance(media, dict) else None
        if isinstance(values, list):
            return [resolve_repo_path(str(value)) for value in values]
    return sorted(path for path in fallback_dir.glob(f"*{suffix}") if not path.name.startswith("."))


def markdown_section(markdown: str, title_prefix: str) -> str:
    lines = markdown.splitlines()
    start: int | None = None
    for index, line in enumerate(lines):
        if line.startswith("## ") and line[3:].strip().startswith(title_prefix):
            start = index + 1
            break
    if start is None:
        return ""

    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    return "\n".join(lines[start:end]).strip()


def parse_metadata() -> dict[str, str]:
    if not METADATA_PATH.exists():
        return {}

    markdown = METADATA_PATH.read_text(encoding="utf-8")
    whats_new_match = re.search(r"^## What's New \(([^)]+)\)", markdown, re.MULTILINE)
    return {
        "pricing": markdown_section(markdown, "Pricing"),
        "app_name": markdown_section(markdown, "App Name"),
        "subtitle": markdown_section(markdown, "Subtitle"),
        "promotional_text": markdown_section(markdown, "Promotional Text"),
        "whats_new_version": whats_new_match.group(1) if whats_new_match else "",
        "whats_new": markdown_section(markdown, "What's New"),
        "description": markdown_section(markdown, "Description"),
        "keywords": markdown_section(markdown, "Keywords"),
        "support_url": markdown_section(markdown, "Support URL"),
        "copyright": markdown_section(markdown, "Copyright"),
        "review_contact": markdown_section(markdown, "App Review Information"),
    }


def parse_project_versions() -> dict[str, str]:
    if not PROJECT_PATH.exists():
        return {}

    text = PROJECT_PATH.read_text(encoding="utf-8")
    marketing_versions = unique_in_order(re.findall(r"\bMARKETING_VERSION = ([^;]+);", text))
    build_numbers = unique_in_order(re.findall(r"\bCURRENT_PROJECT_VERSION = ([^;]+);", text))
    return {
        "marketing_version": marketing_versions[0] if marketing_versions else "",
        "build_number": build_numbers[0] if build_numbers else "",
    }


def image_info(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"path": str(path), "name": path.name, "error": "File does not exist"}
    if Image is None:
        return {"path": str(path), "name": path.name, "error": "Missing Pillow dependency"}
    with Image.open(path) as image:
        return {
            "path": str(path),
            "name": path.name,
            "width": image.width,
            "height": image.height,
            "sha256": sha256(path),
        }


def ffprobe_json(path: Path) -> dict[str, Any]:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        (
            "format=duration,bit_rate:"
            "stream=index,codec_type,codec_name,profile,width,height,avg_frame_rate,"
            "pix_fmt,sample_rate,channels,channel_layout,bit_rate"
        ),
        "-of",
        "json",
        str(path),
    ]
    result = subprocess.run(command, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def video_info(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"path": str(path), "name": path.name, "error": "File does not exist"}
    try:
        payload = ffprobe_json(path)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        return {"path": str(path), "name": path.name, "error": str(error)}

    streams = payload.get("streams", [])
    video_stream = next((stream for stream in streams if stream.get("codec_type") == "video"), {})
    audio_streams = [stream for stream in streams if stream.get("codec_type") == "audio"]
    return {
        "path": str(path),
        "name": path.name,
        "width": video_stream.get("width"),
        "height": video_stream.get("height"),
        "frame_rate": video_stream.get("avg_frame_rate"),
        "video_codec": video_stream.get("codec_name"),
        "video_profile": video_stream.get("profile"),
        "video_pixel_format": video_stream.get("pix_fmt"),
        "video_bit_rate": int(video_stream.get("bit_rate", 0) or 0),
        "duration": float(payload.get("format", {}).get("duration", 0)),
        "has_audio": bool(audio_streams),
        "audio_streams": audio_streams,
        "sha256": sha256(path),
    }


def collect_local_state(manifest_path: Path = RELEASE_MANIFEST_PATH) -> dict[str, Any]:
    manifest = load_release_manifest(manifest_path)
    screenshot_paths = manifest_media_paths(manifest, "screenshots", SCREENSHOTS_DIR, ".png")
    preview_paths = manifest_media_paths(manifest, "previewVideos", PREVIEW_VIDEOS_DIR, ".mp4")
    docs_video_paths = sorted(path for path in DOCS_VIDEOS_DIR.glob("*.mp4") if not path.name.startswith("."))
    all_screenshot_paths = sorted(path for path in SCREENSHOTS_DIR.glob("*.png") if not path.name.startswith("."))

    return {
        "metadata_path": str(METADATA_PATH),
        "metadata": parse_metadata(),
        "manifest_path": str(manifest_path),
        "manifest": manifest,
        "project": parse_project_versions(),
        "app_icon": {
            "path": str(APP_ICON_PATH),
            "exists": APP_ICON_PATH.exists(),
        },
        "screenshots": [image_info(path) for path in screenshot_paths],
        "all_screenshots": [image_info(path) for path in all_screenshot_paths],
        "preview_videos": [video_info(path) for path in preview_paths],
        "docs_videos": [video_info(path) for path in docs_video_paths],
    }


def extract_text_field(snapshot: str, label: str) -> str:
    pattern = rf"text field \(settable, string\) (?:Description: )?{re.escape(label)}, Value: ([^\n]+)"
    match = re.search(pattern, snapshot)
    return match.group(1).strip() if match else ""


def extract_entry_area(snapshot: str, label: str) -> str:
    pattern = (
        rf"text entry area \(settable, string\) {re.escape(label)}"
        rf"(?:, Value: (?P<value>.*?))?"
        rf"(?=\n\s+\d+\s+(?:button|checkbox|container|heading|radio button|text|text entry area|text field)|\Z)"
    )
    match = re.search(pattern, snapshot, flags=re.DOTALL)
    if not match:
        return ""
    value = match.group("value")
    return value.strip() if value else ""


def parse_radio_value(snapshot: str, label: str) -> int | None:
    pattern = rf"radio button \(settable, integer\) {re.escape(label)}, Value: ([01])"
    match = re.search(pattern, snapshot)
    return int(match.group(1)) if match else None


def parse_asc_snapshot(path: Path) -> dict[str, Any]:
    snapshot = path.read_text(encoding="utf-8")
    preview_count_match = re.search(r"(\d+) of 3 App Previews", snapshot)
    screenshot_count_match = re.search(r"(\d+) of 10 Screenshots", snapshot)
    version_heading = re.search(r"heading macOS App(?:\s|\u00a0)+Version ([^,\n]+)", snapshot)

    preview_names = unique_in_order(re.findall(r"App Preview ([^\n]+?\.mp4)", snapshot))
    screenshot_names = unique_in_order(re.findall(r"Screenshot ([^\n]+?\.png)", snapshot))

    release_manual = parse_radio_value(snapshot, "Manually release this version")
    release_auto = parse_radio_value(snapshot, "Automatically release this version")
    release_after_review = parse_radio_value(snapshot, "Automatically release this version after App Review, no earlier than")
    phased_release = parse_radio_value(snapshot, "Release update over 7-day period using phased release")

    return {
        "path": str(path),
        "url": extract_text_field(snapshot, "Address and search bar"),
        "page_version": compact(version_heading.group(1)) if version_heading else "",
        "field_version": extract_text_field(snapshot, "Version"),
        "preview_count": int(preview_count_match.group(1)) if preview_count_match else None,
        "screenshot_count": int(screenshot_count_match.group(1)) if screenshot_count_match else None,
        "preview_names": preview_names,
        "screenshot_names": screenshot_names,
        "promotional_text": extract_entry_area(snapshot, "Promotional Text"),
        "description": extract_entry_area(snapshot, "Description"),
        "whats_new": extract_entry_area(snapshot, "What's New in This Version"),
        "keywords": extract_text_field(snapshot, "Keywords"),
        "support_url": extract_text_field(snapshot, "Support URL"),
        "marketing_url": extract_text_field(snapshot, "Marketing URL"),
        "copyright": extract_text_field(snapshot, "Copyright"),
        "save_disabled": "button (disabled) Save" in snapshot,
        "add_for_review_visible": "button Add for Review" in snapshot,
        "add_build_visible": "button Add Build" in snapshot,
        "release_manual": release_manual,
        "release_auto": release_auto,
        "release_after_review": release_after_review,
        "phased_release": phased_release,
        "snapshot_hash": hashlib.sha256(snapshot.encode("utf-8")).hexdigest()[:12],
    }


def add_finding(findings: list[Finding], severity: str, code: str, message: str, detail: str | None = None) -> None:
    findings.append(Finding(severity=severity, code=code, message=message, detail=detail))


def compare_optional_field(
    findings: list[Finding],
    local: dict[str, str],
    asc: dict[str, Any],
    field: str,
    label: str,
    *,
    empty_is_blocker: bool = False,
) -> None:
    expected = normalize_text(local.get(field, ""))
    actual = normalize_text(str(asc.get(field, "")))
    if not expected:
        add_finding(findings, "warn", f"local_{field}_missing", f"Local {label} is missing.")
        return
    if not actual:
        severity = "block" if empty_is_blocker else "warn"
        add_finding(
            findings,
            severity,
            f"asc_{field}_missing",
            f"App Store Connect {label} is empty.",
            f"Local {label} hash is {short_hash(expected)}.",
        )
        return
    if expected != actual:
        add_finding(
            findings,
            "warn",
            f"{field}_differs",
            f"Local {label} differs from App Store Connect.",
            f"local={short_hash(expected)} asc={short_hash(actual)}",
        )
    else:
        add_finding(findings, "pass", f"{field}_matches", f"{label} matches App Store Connect.")


def audit_local(local: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    metadata = local["metadata"]
    manifest = local.get("manifest")
    release_text = release_text_source(local)

    if not METADATA_PATH.exists():
        add_finding(findings, "block", "metadata_missing", "AppStoreMetadata.md is missing.", str(METADATA_PATH))
    else:
        add_finding(findings, "pass", "metadata_present", "App Store metadata source exists.", str(METADATA_PATH))

    if isinstance(manifest, dict):
        add_finding(findings, "pass", "release_manifest_present", "Release manifest exists.", local["manifest_path"])
    else:
        add_finding(
            findings,
            "warn",
            "release_manifest_missing",
            "Release manifest is missing; falling back to AppStoreMetadata.md.",
            local["manifest_path"],
        )

    for field in ["promotional_text", "whats_new", "description", "keywords", "support_url", "copyright"]:
        if normalize_text(release_text.get(field, "")):
            add_finding(findings, "pass", f"release_{field}", f"Release manifest has {field.replace('_', ' ')}.")
        else:
            add_finding(findings, "block", f"release_{field}_missing", f"Release manifest is missing {field.replace('_', ' ')}.")

    keywords = release_text.get("keywords", "")
    if len(keywords) <= 100:
        add_finding(findings, "pass", "keywords_length", f"Keywords fit App Store limit: {len(keywords)}/100.")
    else:
        add_finding(findings, "block", "keywords_too_long", "Keywords exceed App Store's 100-character limit.", f"{len(keywords)}/100")

    review_contact = metadata.get("review_contact", "")
    if "[Your " in review_contact:
        add_finding(
            findings,
            "warn",
            "review_contact_placeholders",
            "AppStoreMetadata.md still contains placeholder review-contact fields.",
            "Keep real contact details out of source, but do not rely on this section as release truth until it is templated.",
        )

    project_version = local["project"].get("marketing_version", "")
    metadata_version = metadata.get("whats_new_version", "")
    manifest_version = str(manifest.get("version", "")) if isinstance(manifest, dict) else ""
    expected_version = manifest_version or metadata_version
    if project_version and expected_version and project_version == expected_version:
        add_finding(findings, "pass", "version_matches_release", f"Project version matches release version: {project_version}.")
    else:
        add_finding(
            findings,
            "block",
            "version_mismatch",
            "Project MARKETING_VERSION does not match the release version.",
            f"project={project_version or 'missing'} release={expected_version or 'missing'}",
        )

    if local["app_icon"]["exists"]:
        add_finding(findings, "pass", "app_icon_present", "1024px app icon exists.", local["app_icon"]["path"])
    else:
        add_finding(findings, "block", "app_icon_missing", "1024px app icon is missing.", local["app_icon"]["path"])

    screenshots = local["screenshots"]
    if len(screenshots) < EXPECTED_SCREENSHOT_SLOTS:
        add_finding(
            findings,
            "block",
            "too_few_screenshots",
            f"Only {len(screenshots)} local screenshots found; App Store product page needs {EXPECTED_SCREENSHOT_SLOTS}.",
        )
    elif len(screenshots) > EXPECTED_SCREENSHOT_SLOTS:
        add_finding(
            findings,
            "warn",
            "extra_screenshots",
            f"{len(screenshots)} local screenshots found for {EXPECTED_SCREENSHOT_SLOTS} App Store slots.",
            "Add or confirm an upload-order manifest so the release auditor knows which 10 are canonical.",
        )
    else:
        add_finding(findings, "pass", "screenshot_count", f"{EXPECTED_SCREENSHOT_SLOTS} release screenshots selected.")

    all_screenshots = local.get("all_screenshots", [])
    if len(all_screenshots) > len(screenshots) and isinstance(manifest, dict):
        add_finding(
            findings,
            "pass",
            "extra_screenshots_ignored",
            f"{len(all_screenshots) - len(screenshots)} extra local screenshots are intentionally ignored by the release manifest.",
        )

    for screenshot in screenshots:
        if screenshot.get("error"):
            add_finding(findings, "block", "screenshot_unreadable", f"Could not inspect {screenshot['name']}.", screenshot["error"])
            continue
        size = (screenshot.get("width"), screenshot.get("height"))
        if size == EXPECTED_SCREENSHOT_SIZE:
            add_finding(findings, "pass", "screenshot_size", f"{screenshot['name']} is 2880x1800.")
        else:
            add_finding(findings, "block", "screenshot_size_invalid", f"{screenshot['name']} is not 2880x1800.", f"size={size}")

    previews = local["preview_videos"]
    if len(previews) != EXPECTED_PREVIEW_COUNT:
        add_finding(findings, "block", "preview_count", f"Expected {EXPECTED_PREVIEW_COUNT} preview videos, found {len(previews)}.")
    else:
        add_finding(findings, "pass", "preview_count", f"{EXPECTED_PREVIEW_COUNT} preview videos found.")

    docs_by_name = {video["name"]: video for video in local["docs_videos"]}
    for preview in previews:
        if preview.get("error"):
            add_finding(findings, "block", "preview_unreadable", f"Could not inspect {preview['name']}.", preview["error"])
            continue
        if (preview.get("width"), preview.get("height")) == EXPECTED_PREVIEW_SIZE:
            add_finding(findings, "pass", "preview_size", f"{preview['name']} is 1920x1080.")
        else:
            add_finding(
                findings,
                "block",
                "preview_size_invalid",
                f"{preview['name']} is not 1920x1080.",
                f"{preview.get('width')}x{preview.get('height')}",
            )

        if preview.get("video_codec") == "h264":
            add_finding(findings, "pass", "preview_video_codec", f"{preview['name']} uses H.264 video.")
        else:
            add_finding(
                findings,
                "block",
                "preview_video_codec_invalid",
                f"{preview['name']} is not H.264 video.",
                str(preview.get("video_codec") or "missing"),
            )

        if preview.get("video_pixel_format") == "yuv420p":
            add_finding(findings, "pass", "preview_pixel_format", f"{preview['name']} uses yuv420p pixel format.")
        else:
            add_finding(
                findings,
                "block",
                "preview_pixel_format_invalid",
                f"{preview['name']} does not use yuv420p pixel format.",
                str(preview.get("video_pixel_format") or "missing"),
            )

        video_bit_rate = int(preview.get("video_bit_rate", 0) or 0)
        if video_bit_rate >= APP_PREVIEW_VIDEO_MIN_BITRATE:
            add_finding(findings, "pass", "preview_video_bitrate", f"{preview['name']} video bitrate is App Store-ready.", f"{video_bit_rate} bps")
        else:
            add_finding(
                findings,
                "warn",
                "preview_video_bitrate_low",
                f"{preview['name']} video bitrate is below Apple's 10-12 Mbps target.",
                f"{video_bit_rate} bps",
            )

        duration = float(preview.get("duration", 0))
        if duration > MAX_PREVIEW_DURATION_SECONDS:
            add_finding(findings, "block", "preview_too_long", f"{preview['name']} is longer than 30 seconds.", f"{duration:.2f}s")
        elif duration < MIN_PREVIEW_DURATION_SECONDS:
            add_finding(
                findings,
                "block",
                "preview_short",
                f"{preview['name']} is shorter than Apple's 15 second app preview minimum.",
                f"{duration:.2f}s",
            )
        else:
            add_finding(findings, "pass", "preview_duration", f"{preview['name']} duration is {duration:.2f}s.")

        audio_streams = preview.get("audio_streams", [])
        audio_stream = audio_streams[0] if audio_streams else {}
        if not audio_stream:
            add_finding(
                findings,
                "block",
                "preview_audio_missing",
                f"{preview['name']} has no audio stream.",
                "App Store Connect requires enabled stereo audio for H.264 app previews.",
            )
        else:
            audio_codec = str(audio_stream.get("codec_name", ""))
            sample_rate = int(audio_stream.get("sample_rate", 0) or 0)
            channels = int(audio_stream.get("channels", 0) or 0)
            channel_layout = str(audio_stream.get("channel_layout", ""))
            audio_bit_rate = int(audio_stream.get("bit_rate", 0) or 0)

            if audio_codec == "aac":
                add_finding(findings, "pass", "preview_audio_codec", f"{preview['name']} uses AAC audio.")
            else:
                add_finding(findings, "block", "preview_audio_codec_invalid", f"{preview['name']} audio is not AAC.", audio_codec or "missing")

            if channels == 2 and channel_layout == "stereo":
                add_finding(findings, "pass", "preview_audio_stereo", f"{preview['name']} audio is stereo.")
            else:
                add_finding(
                    findings,
                    "block",
                    "preview_audio_not_stereo",
                    f"{preview['name']} audio is not stereo.",
                    f"channels={channels} layout={channel_layout or 'missing'}",
                )

            if sample_rate in APP_PREVIEW_AUDIO_SAMPLE_RATES:
                add_finding(findings, "pass", "preview_audio_sample_rate", f"{preview['name']} audio sample rate is {sample_rate} Hz.")
            else:
                add_finding(
                    findings,
                    "block",
                    "preview_audio_sample_rate_invalid",
                    f"{preview['name']} audio sample rate is not 44.1kHz or 48kHz.",
                    f"{sample_rate} Hz",
                )

            if audio_bit_rate >= APP_PREVIEW_AUDIO_MIN_BITRATE:
                add_finding(findings, "pass", "preview_audio_bitrate", f"{preview['name']} audio bitrate is App Store-ready.", f"{audio_bit_rate} bps")
            else:
                add_finding(
                    findings,
                    "warn",
                    "preview_audio_bitrate_low",
                    f"{preview['name']} audio bitrate is below the 256 kbps target.",
                    f"{audio_bit_rate} bps",
                )

        docs_video = docs_by_name.get(preview["name"])
        if docs_video and docs_video.get("sha256") == preview.get("sha256"):
            add_finding(findings, "pass", "preview_docs_match", f"{preview['name']} matches docs/assets/videos.")
        elif docs_video:
            add_finding(findings, "block", "preview_docs_drift", f"{preview['name']} differs from docs/assets/videos.")

    return findings


def audit_against_asc(local: dict[str, Any], asc: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    release_text = release_text_source(local)
    project_version = local["project"].get("marketing_version", "")

    asc_version = asc.get("field_version") or asc.get("page_version")
    if asc_version and project_version and asc_version == project_version:
        add_finding(findings, "pass", "asc_version_matches", f"ASC version matches local project version: {asc_version}.")
    elif asc_version:
        add_finding(findings, "block", "asc_version_mismatch", "ASC version differs from local project version.", f"asc={asc_version} local={project_version}")
    else:
        add_finding(findings, "warn", "asc_version_unknown", "Could not read ASC app version from snapshot.")

    if asc.get("preview_count") == EXPECTED_PREVIEW_COUNT:
        add_finding(findings, "pass", "asc_preview_count", "ASC shows 3 of 3 app previews.")
    elif asc.get("preview_count") is None:
        add_finding(findings, "warn", "asc_preview_count_unknown", "Could not read ASC app preview count from snapshot.")
    else:
        add_finding(findings, "block", "asc_preview_count", f"ASC shows {asc['preview_count']} of 3 app previews.")

    if asc.get("screenshot_count") == EXPECTED_SCREENSHOT_SLOTS:
        add_finding(findings, "pass", "asc_screenshot_count", "ASC shows 10 of 10 screenshots.")
    elif asc.get("screenshot_count") is None:
        add_finding(findings, "warn", "asc_screenshot_count_unknown", "Could not read ASC screenshot count from snapshot.")
    else:
        add_finding(findings, "block", "asc_screenshot_count", f"ASC shows {asc['screenshot_count']} of 10 screenshots.")

    local_preview_names = [video["name"] for video in local["preview_videos"]]
    if asc.get("preview_names") and asc["preview_names"] == local_preview_names:
        add_finding(findings, "pass", "asc_preview_order", "ASC preview filenames match local order.")
    elif asc.get("preview_names"):
        add_finding(
            findings,
            "warn",
            "asc_preview_order_differs",
            "ASC preview filenames/order differ from local preview videos.",
            f"asc={asc['preview_names']} local={local_preview_names}",
        )

    local_screenshot_names = {screenshot["name"] for screenshot in local["screenshots"]}
    unknown_asc_screenshots = [name for name in asc.get("screenshot_names", []) if name not in local_screenshot_names]
    if asc.get("screenshot_names") and not unknown_asc_screenshots:
        add_finding(findings, "pass", "asc_screenshot_names", "ASC screenshot filenames all exist locally.")
    elif unknown_asc_screenshots:
        add_finding(
            findings,
            "warn",
            "asc_screenshot_names_drift",
            "Some ASC screenshot filenames are not present locally.",
            f"missing locally: {', '.join(unknown_asc_screenshots)}",
        )

    compare_optional_field(findings, release_text, asc, "promotional_text", "Promotional Text")
    compare_optional_field(findings, release_text, asc, "description", "Description")
    compare_optional_field(findings, release_text, asc, "whats_new", "What's New", empty_is_blocker=True)
    compare_optional_field(findings, release_text, asc, "keywords", "Keywords")
    compare_optional_field(findings, release_text, asc, "support_url", "Support URL", empty_is_blocker=True)
    compare_optional_field(findings, release_text, asc, "marketing_url", "Marketing URL")
    compare_optional_field(findings, release_text, asc, "copyright", "Copyright")

    if asc.get("add_build_visible"):
        add_finding(
            findings,
            "block",
            "asc_build_missing",
            "ASC still shows Add Build on the version page.",
            "Attach/select the release build before submitting for review.",
        )
    else:
        add_finding(findings, "pass", "asc_build_attached", "ASC does not show Add Build on the captured page.")

    if asc.get("save_disabled") is False:
        add_finding(findings, "confirm", "asc_unsaved_changes", "ASC Save button appears enabled.", "Saving changes is an external side effect.")
    elif asc.get("save_disabled") is True:
        add_finding(findings, "pass", "asc_no_unsaved_changes", "ASC Save button appears disabled.")

    if asc.get("release_auto") == 1:
        add_finding(
            findings,
            "confirm",
            "asc_auto_release_selected",
            "ASC is set to automatically release this version after App Review approval.",
            "Confirm this policy before final submission.",
        )
    elif asc.get("release_manual") == 1:
        add_finding(findings, "pass", "asc_manual_release_selected", "ASC is set to manual release.")

    if asc.get("phased_release") == 1:
        add_finding(findings, "confirm", "asc_phased_release_selected", "ASC phased release is selected.")

    if asc.get("add_for_review_visible"):
        add_finding(
            findings,
            "confirm",
            "asc_add_for_review_visible",
            "ASC shows Add for Review.",
            "Clicking it submits metadata/build state to Apple review and must be confirmed at action-time.",
        )

    return findings


def overall_status(findings: list[Finding]) -> str:
    severities = {finding.severity for finding in findings}
    if "block" in severities:
        return "blocked"
    if "confirm" in severities or "warn" in severities:
        return "needs_confirmation"
    return "ready"


def print_text_report(local: dict[str, Any], asc: dict[str, Any] | None, findings: list[Finding]) -> None:
    print(f"Status: {overall_status(findings)}")
    print(f"Local project version: {local['project'].get('marketing_version', 'unknown')}")
    print(f"Local project build setting: {local['project'].get('build_number', 'unknown')}")
    print(f"Release manifest: {local['manifest_path'] if local.get('manifest') else 'not provided'}")
    print(f"Local screenshots: {len(local['screenshots'])}")
    print(f"Local preview videos: {len(local['preview_videos'])}")
    if asc:
        print(f"ASC snapshot: {asc['path']} ({asc['snapshot_hash']})")
        print(f"ASC version: {asc.get('field_version') or asc.get('page_version') or 'unknown'}")
        print(f"ASC media: {asc.get('preview_count', 'unknown')} previews, {asc.get('screenshot_count', 'unknown')} screenshots")
    else:
        print("ASC snapshot: not provided")
    print()

    for severity in ["block", "confirm", "warn", "pass"]:
        matching = [finding for finding in findings if finding.severity == severity]
        if not matching:
            continue
        print(f"{severity.upper()}:")
        for finding in matching:
            print(f"- [{finding.code}] {finding.message}")
            if finding.detail:
                print(f"  {finding.detail}")
        print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read-only App Store release auditor for local assets plus optional App Store Connect Computer Use snapshots.",
    )
    parser.add_argument(
        "--asc-snapshot",
        type=Path,
        help="Path to a saved Computer Use accessibility-tree snapshot from the App Store Connect version page.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=RELEASE_MANIFEST_PATH,
        help=f"Release manifest JSON path. Defaults to {RELEASE_MANIFEST_PATH.relative_to(REPO_ROOT)}.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of a text report.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    local = collect_local_state(args.manifest)
    asc = parse_asc_snapshot(args.asc_snapshot) if args.asc_snapshot else None
    findings = audit_local(local)
    if asc:
        findings.extend(audit_against_asc(local, asc))
    else:
        add_finding(
            findings,
            "warn",
            "asc_snapshot_missing",
            "No App Store Connect snapshot was provided.",
            "Capture the Chrome App Store Connect version page with Computer Use and pass it with --asc-snapshot.",
        )

    result = {
        "status": overall_status(findings),
        "local": local,
        "asc": asc,
        "findings": [asdict(finding) for finding in findings],
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print_text_report(local, asc, findings)

    return 1 if result["status"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
