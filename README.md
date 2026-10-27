# StopMissingMeetings

A free macOS menu bar app that makes it impossible to miss a meeting.

Two minutes before every meeting it takes over **every screen** with a full-screen red alert, plays a loud sound every few seconds, and says the meeting name out loud. It stays up until you click **Join meeting**, **Snooze 1 min** or **Dismiss**.

- Works with Google Calendar (and any calendar your Mac syncs)
- Finds Google Meet, Zoom, Teams and Webex links: **Join meeting** opens them, or press Return
- Skips all-day events, cancelled events and meetings you declined
- The menu bar shows minutes until your next meeting

## Install

Requires macOS 14+ and Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/GianmarcoSalerno/StopMissingMeetings.git
cd StopMissingMeetings
./build.sh --install
```

Then:

1. Click **Allow** when macOS asks for calendar access.
2. Add your Google account: **System Settings → Internet Accounts → Google** (Calendars on). The menu has a shortcut to this.
3. Turn on **Launch at login** in the menu, and use **Test alert** to check the sound.

## How it reads Google Calendar

macOS syncs your Google Calendar once you add your Google account in Internet Accounts. The app reads it through Apple's EventKit, so no Google API keys or sign-in inside the app are needed, and your data never leaves your Mac.
