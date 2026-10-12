# Phase 5: On the phone

**Specified 12 October 2026.** The app is finished on the simulator. This phase puts it on the
iPhone and checks what a simulator cannot. Card 5.1 is code; card 5.2 is a guide, because
signing, installing and the device checks need the phone in hand.

## Card 5.1: Signing expiry warning (decision #3)

A free Apple ID signs the app for 7 days; after that it will not launch until it is
reinstalled from Xcode. The data survives a reinstall, but a lapsed install in the gym is
the failure to prevent.

**Files:** create `GymApp/Services/SigningExpiry.swift`, `GymAppTests/SigningExpiryTests.swift`;
change `Features/Train/TrainView.swift` (banner) and `App/RootView.swift` (schedule at launch).

- `SigningExpiry.expirationDate(fromProfile data: Data) -> Date?`: the provisioning profile is
  CMS-signed; take the bytes from `<?xml` to `</plist>` and read `ExpirationDate` with
  `PropertyListSerialization`. nil when there is no plist or no date.
- `SigningExpiry.current() -> Date?` reads `embedded.mobileprovision` from the app bundle
  (absent on the simulator, so nil there). DEBUG: launch argument `-signingExpiry <days>`
  pretends the profile expires that many days from now, for simulator checks.
- `warningStart(for expiry:) = expiry − 2 days`.
- **Banner** on Train when `now ≥ warningStart`: "This install expires <weekday, time>.
  Reinstall from Xcode to keep training without interruption." (red once expired: "This
  install has expired…").
- **Notification** at `warningStart` (identifier `signing-expiry`), rescheduled at every launch
  so a reinstall moves it; skipped when the moment is past.

**Tests:** a fixture profile (CMS-style bytes around a plist) yields the date; garbage yields
nil; the warning starts exactly two days before; the banner state for before, during and
after.

## Card 5.2: Phone setup guide and checklist

**Files:** create `docs/PHONE_SETUP.md`; update README, ROADMAP and HANDOFF.

A step-by-step guide for Fuaad: add the Apple ID in Xcode, select the team for GymApp and
GymAppWidgets, enable Developer Mode, run on the device, trust the developer profile, import
the JEFIT export, choose the backup folder in iCloud Drive. Then the device checklist with a
box per check: rest alert with the phone locked and music playing; Live Activity (may be
refused on a free account; the alert is enough); a backup reaching iCloud Drive; restore of
that backup; the expiry banner (via `-signingExpiry 1` in the scheme); reinstall after 7
days keeps the data. And the first sessions alongside JEFIT, after which JEFIT is dropped.
