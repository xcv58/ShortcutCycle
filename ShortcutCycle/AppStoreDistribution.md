# App Store Distribution Guide

## 1. Requirements for Paid Apps
To switch your app from Free to Paid (or launch as Paid), you must complete the following in **App Store Connect**:

### A. Legal & Banking (Critical)
1.  **Paid Applications Agreement**: 
    *   Go to **Business** (or "Agreements, Tax, and Banking").
    *   Review and accept the **Paid Applications Agreement** (Schedule 2).
    *   *Note: This is separate from the free app agreement.*
2.  **Banking Information**:
    *   Add a valid bank account to receive payments.
    *   Apple will make a small deposit to verify.
3.  **Tax Forms**:
    *   Complete U.S. Tax Forms (even if you are not in the U.S., you need to declare your status).
    *   Complete tax forms for other regions if applicable to your business location.

### B. App Store Connect Metadata
1.  **Pricing and Availability**:
    *   Select a Price Tier (see details below).
    *   Set availability (all countries or specific ones).
2.  **Tax Category**:
    *   Select the appropriate tax category for software (usually "App Store Software").

## 2. Pricing Strategy
**Price: $3.99 (Tier 4)**

Selected price point for launch. One-time purchase.

## 3. Build Versioning

`CURRENT_PROJECT_VERSION` (build number) must be unique for each TestFlight/App Store upload.

### Xcode Cloud
Build numbers are set automatically by `<repo-root>/ci_scripts/ci_post_clone.sh` using `$CI_BUILD_NUMBER + 100` offset. No manual action needed.

### Local Builds
Before archiving locally, bump the build number from the terminal:

```sh
cd ShortcutCycle  # directory containing .xcodeproj
agvtool next-version -all
```

Then archive in Xcode (Product > Archive) and upload to TestFlight.

## 4. Launch Checklist
- [ ] Requirements: "Paid Applications Agreement" Active (Green light in Business).
- [ ] Requirements: Bank & Tax Info "Processing" or "Active".
- [ ] Metadata: Screenshots ready (2880x1800) for all supported languages.
- [ ] Binary: Validated and Uploaded via Xcode.
- [ ] Review: Submit for Review.
