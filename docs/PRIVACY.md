# Bashi Gym privacy policy

Last updated: 25 October 2026.

Bashi Gym is a training log. It is built and run by one person, not a company.

## What stays on your phone

- Your workouts, sets, programs, notes, body weight and form cues are stored on your phone.
- Video clips you attach to sets are stored on your phone only. They are never uploaded.
- Daily steps and body weight that you allow the app to read from Apple Health are stored on your
  phone. Nothing is written to Apple Health.

## Sync (optional, off until you turn it on)

When you turn on sync in Settings, the app sends your training data to the Bashi Gym sync
server, so that it can be restored or shared with another device of yours:

- **What is sent:**
  - exercises, programs, workouts and sets;
  - exercise notes and body weight entries;
  - the form cues that you wrote yourself.
- **What is never sent:** video clips, Apple Health steps, and usage counts.
- **Identity:** your account is identified by an identifier from Sign in with Apple. The app
  does not ask for your name or email address.
- **Where it is stored:** a Postgres database hosted by Neon, in the United States (AWS
  us-east-2), behind a server hosted by Render. All traffic is encrypted (HTTPS and TLS).

## What is never done

- There is no advertising and no tracking. No data is sold or shared with third parties for any
  purpose.
- There are no analytics services. The app counts screen opens on your phone only, and you can
  export or ignore those counts in Settings.

## Your rights

- **Download:** Settings → Sync → *Download server copy* gives you everything the server
  holds, as JSON.
- **Delete:** Settings → Sync → *Delete server copy* deletes your account and every row on the
  server at once. Server backups age out within 30 days.
- **Turn off:** you can turn off sync at any time. Your data on the phone is not affected.

## Contact

Open an issue on the project's GitHub page.
