# MeetingReminder

![MeetingReminder demo](media/demo.gif)

A macOS menu bar app that reads Google Calendar directly and flies a banner
across your screen before meetings.

The app uses Google's desktop OAuth flow with PKCE, stores the refresh token in
Keychain, polls Google Calendar every 60 seconds, and shows the existing
airplane banner around five minutes before each meeting.

---

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 or later
- A Google Cloud project with the Google Calendar API enabled

No paid Apple Developer account is required. The project uses ad-hoc signing
(`Sign to Run Locally`).

---

## Google OAuth Setup

1. Open [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select a project
3. Enable **Google Calendar API**
4. Open **APIs & Services -> OAuth consent screen**
5. Set the app to **Testing**
6. Add your Google account as a **Test user**
7. Open **APIs & Services -> Credentials**
8. Create **OAuth client ID**
9. Choose **Desktop app**
10. Download the OAuth client JSON

Place the downloaded JSON at:

```text
MeetingReminder/GoogleOAuthCredentials.json
```

That file is git-ignored because it includes the desktop OAuth client secret.
For this local app, the bundled credential lets users click **Connect Google**
without pasting anything.

---

## Run Locally

```bash
open MeetingReminder.xcodeproj
```

In Xcode, press **Cmd+R**.

Then:

1. Click the MeetingReminder menu bar icon
2. Click **Connect Google**
3. Complete the browser sign-in
4. Return to MeetingReminder after the success page appears

The connected email appears in the menu bar popover. Tokens are stored in
macOS Keychain.

## Day Planner

After connecting Google Calendar, open **Day planner** from the menu bar popover.
The planner shows one day at a time, with previous/next day controls and a week
strip for jumping around the current week.

Each timed event has a checkbox:

- Checked events can trigger the banner reminder.
- Unchecked events are skipped by the reminder poller.
- Choices are stored locally in `UserDefaults`.

The planner refreshes when it opens, when you change dates, when you click the
refresh button, and every 60 seconds while the planner window is open.

---

## Testing Reminders

Use **Test airplane** to verify the visual banner immediately.

To test real Google Calendar polling:

1. Create a Google Calendar event that starts about 5 minutes from now
2. Make sure it is on a selected, visible calendar
3. Keep MeetingReminder running
4. Wait for the next poll cycle

The background reminder poller checks Google Calendar every 60 seconds, looks
one hour ahead, and fires when a checked meeting is roughly 4-6 minutes away.

---

## How It Works

- **Menu bar app**: `MeetingReminderApp.swift` uses `MenuBarExtra`
- **OAuth config**: `GoogleOAuthConfig.swift` loads the bundled
  `GoogleOAuthCredentials.json` desktop credential
- **OAuth**: `GoogleOAuthService.swift` opens Google sign-in in the browser,
  uses a localhost callback, exchanges the authorization code for tokens, and
  refreshes access tokens when needed
- **Token storage**: `KeychainStore.swift` stores the Google credential locally
- **Calendar API**: `GoogleCalendarService.swift` reads selected Google
  calendars and events for the next hour or selected planner day
- **Polling**: `CalendarPoller.swift` checks every 60 seconds and prevents
  duplicate alerts during the current app session
- **Planner**: `MenuBarView.swift` lets you inspect a day/week and enable or
  disable reminders per event
- **Banner**: `AirplaneOverlayWindow.swift` and `AirplaneView.swift` draw the
  floating airplane banner above other windows

---

## Project Structure

```text
MeetingReminder/
├── MeetingReminderApp.swift
├── AppController.swift
├── MenuBarView.swift
├── CalendarSource.swift
├── GoogleOAuthService.swift
├── GoogleOAuthConfig.swift
├── GoogleCalendarService.swift
├── LocalOAuthRedirectServer.swift
├── KeychainStore.swift
├── CalendarPoller.swift
├── AirplaneView.swift
├── AirplaneOverlayWindow.swift
├── MeetingReminder.entitlements
└── Assets.xcassets/
```

---

## Current Limitations

- The first pass stores one connected Google account
- It reads selected visible calendars from that account
- Per-meeting opt-in/opt-out is local to this Mac
- Notifications are custom overlay banners, not macOS Notification Center banners
- The local OAuth credential JSON is intentionally not committed

---

## License

MIT
