# Release Keychain

For a signed TestFlight/App Store upload from the Mini, unlock the local release keychain before opening Xcode's distribution flow:

```sh
security unlock-keychain -p "$(cat ~/.codesign/heart-rate-insights/release.keychain.pass)" \
  ~/.codesign/heart-rate-insights/release.keychain-db
```

From another machine with SSH access to `mini`, run:

```sh
ssh mini 'security unlock-keychain -p "$(cat ~/.codesign/heart-rate-insights/release.keychain.pass)" ~/.codesign/heart-rate-insights/release.keychain-db'
```

The password file is intentionally outside this repository and must never be copied, printed, committed, or included in logs. This command must be run again after the keychain is locked or a new login session starts.
