# App Store Distribution Guide

## 1. Requirements for Paid Apps
To launch as a paid app, or convert an existing free app to a paid app, complete the following steps in **App Store Connect**:

### A. Legal and Banking
1. **Paid Applications Agreement**
   * Go to **Business** (or **Agreements, Tax, and Banking**).
   * Review and accept the **Paid Applications Agreement** (Schedule 2).
   * This agreement is separate from the agreement for free apps.
2. **Banking Information**
   * Add a valid bank account for payouts.
   * Apple will send a small verification deposit.
3. **Tax Forms**
   * Complete the required U.S. tax forms, even if you are not based in the United States.
   * Complete any additional regional tax forms required for your business location.

### B. App Store Connect Metadata
1. **Pricing and Availability**
   * Select a price tier. The recommended launch price is listed below.
   * Configure territory availability.
2. **Tax Category**
   * Select the appropriate software tax category, typically **App Store Software**.

## 2. Pricing Strategy
**Price: $3.99 (Tier 4)**

Recommended launch pricing: one-time purchase at Tier 4.

## 3. Build Versioning

`CURRENT_PROJECT_VERSION` (build number) must be unique for each TestFlight/App Store upload.

Both local archives and Xcode Cloud builds use the same version-sync script:
`scripts/sync_project_version.sh`

### Workflow
- For every archive, the shared scheme runs `scripts/sync_project_version.sh` as an Archive pre-action.
- In Xcode Cloud, `ShortcutCycle/ci_scripts/ci_post_clone.sh` runs the same script before the build. The script lives alongside `ShortcutCycle.xcodeproj`.
- For local archives, the default build number is `CURRENT_PROJECT_VERSION + 1`.
- For Xcode Cloud, the default build number is `CI_BUILD_NUMBER + SC_CI_BUILD_OFFSET`. `SC_CI_BUILD_OFFSET` defaults to `1000`, and a monotonic guard prevents regressions.
- `MARKETING_VERSION` remains manual unless explicitly overridden.
- Local archives will update `ShortcutCycle.xcodeproj/project.pbxproj`, which is expected.
- After a version is approved, its pre-release train is closed. The next upload must use a higher `MARKETING_VERSION`; increasing only the build number is not sufficient.

### Optional overrides
```sh
SC_BUILD_NUMBER=123 /bin/sh scripts/sync_project_version.sh
SC_CI_BUILD_OFFSET=2000 /bin/sh scripts/sync_project_version.sh
SC_MARKETING_VERSION=1.11 /bin/sh scripts/sync_project_version.sh
```

For the next local archive after rejected build 134, the checked-in 134 baseline produces version `1.11` build `135`. To prepare those values explicitly without archiving:

```sh
SC_BUILD_NUMBER=135 SC_MARKETING_VERSION=1.11 /bin/sh scripts/sync_project_version.sh
```

## 4. Launch Checklist
- [ ] Agreements: the Paid Applications Agreement is active in Business.
- [ ] Banking and tax: banking and tax information is in Processing or Active status.
- [ ] Metadata: 2880x1800 screenshots are ready for all supported languages.
- [ ] Binary: the app has been validated and uploaded from Xcode.
- [ ] Review: the submission has been sent for App Review.

## 5. Read-Only Release Audit

Before changing App Store Connect, run the local release auditor:

```sh
python3 scripts/app_store_release_audit.py
```

The release source of truth is `ShortcutCycle/AppStoreRelease.json`. It declares the target version, preferred App Store Connect build, release policy, App Store text fields, three preview videos, and the canonical 10 screenshots to upload from the generated screenshot set.

For a browser-side comparison, capture the App Store Connect macOS version page with Computer Use, save the accessibility-tree text outside the repo, then pass it to the auditor:

```sh
python3 scripts/app_store_release_audit.py \
  --asc-snapshot .artifacts/app-store-connect/macos-version-1.9.txt
```

The auditor is intentionally read-only. It reports `ready`, `blocked`, or `needs_confirmation` and treats App Store Connect actions such as saving metadata, uploading assets, selecting a build, changing release policy, or clicking **Add for Review** as explicit-confirmation steps.
