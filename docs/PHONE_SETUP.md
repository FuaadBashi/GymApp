# Putting GymApp on the iPhone

Everything below needs the phone in hand and about 20 minutes. It uses a free Apple ID, so no
paid membership (decision #2). A free install lasts 7 days; the app warns two days ahead
(decision #3), and reinstalling keeps every workout.

> **Never delete the app to fix a problem.** Deleting it deletes the data on the phone
> (decision #2). Reinstall from Xcode instead, and keep the backup folder set (step 3).

## 1. Sign the app (Mac, once)

1. Xcode → Settings → Accounts → **+** → Apple ID. Sign in with your normal Apple ID.
2. Open `GymApp.xcodeproj`. In the project navigator click **GymApp** (the blue icon).
3. For the **GymApp** target: Signing & Capabilities → tick *Automatically manage signing* →
   Team: *Your Name (Personal Team)*.
4. Do the same for the **GymAppWidgets** target (the lock-screen countdown).
5. If Xcode says the bundle identifier is unavailable, change `com.fuaadshurie` to something
   unique in both targets (keep the `.GymAppWidgets` ending on the widget).

## 2. Prepare the phone (once)

1. Connect the iPhone with a cable and unlock it. Tap **Trust** on the phone.
2. Settings → Privacy & Security → **Developer Mode** → on. The phone restarts; confirm.
3. In Xcode, choose the iPhone as the run destination (top bar) and press **Run** (⌘R).
4. The first launch is refused: on the phone go to Settings → General → VPN & Device
   Management → your Apple ID → **Trust**. Run again from Xcode.
5. Allow notifications when asked: the rest alert and the expiry reminder need them.

## 3. Bring your data across (once)

1. AirDrop or save the JEFIT export (`jefit-export-….csv`) to Files on the phone.
2. GymApp → Settings → Data → **Import JEFIT export…** → pick the file. The report should
   say 468 workouts and 7,751 sets.
3. Settings → Data → **Backups & recovery** → **Choose backup folder…** → iCloud Drive →
   make a folder `GymApp Backups` → Open. From now on every change is copied there.

## 4. Checks on the device

Tick each in HANDOFF.md when done. Each is something a simulator cannot show.

- [ ] **Rest alert, phone locked, music playing.** Start a workout, log a set, lock the phone
      with music on. The "Rest over" alert sounds when the timer ends.
- [ ] **Lock-screen countdown.** During rest the lock screen shows the countdown. A free
      account may refuse Live Activities; if so, the alert above is enough (decision #5).
- [ ] **Backup reaches iCloud Drive.** After a workout, Files → iCloud Drive → GymApp Backups
      holds a new `recovery-….sqlite`, and on the Mac it appears in iCloud Drive too.
- [ ] **Restore from that backup.** Backups & recovery → Restore from file… → pick it →
      Schedule restore → reopen the app. Counts match what the preview said.
- [ ] **Expiry banner.** In Xcode: Product → Scheme → Edit Scheme → Run → Arguments → add
      `-signingExpiry 1`, run, and Train shows the orange banner. Remove the argument after.
- [ ] **Real expiry date.** Without that argument, nothing shows on the first five days; on
      day six the banner and a notification appear.
- [ ] **Reinstall keeps data.** On day six or seven, connect and press Run in Xcode again.
      History is unchanged.

## 5. Use it

Log the next sessions in GymApp alongside JEFIT. When a week of sessions has gone through
without needing JEFIT, stop using JEFIT. The CSV export (Settings → Data) and
the full backup are the way out if ever needed; [EXPORT_FORMAT.md](EXPORT_FORMAT.md) explains both.

## Every week

Free signing lasts 7 days. When the banner appears, connect the phone and press Run in Xcode.
That is the whole reinstall; nothing is lost. After the first cable install, Xcode can also
send it over Wi-Fi (Window → Devices and Simulators → *Connect via network*).
