# MeetingReminder

![MeetingReminder demo](media/demo.gif)

A macOS menu bar app that reads Google Calendar directly and flies a banner
across your screen before meetings.

The app uses Google's desktop OAuth flow with PKCE, stores Google account tokens
locally, refreshes Google Calendar on launch and every 10 minutes, and shows
the existing airplane banner before each meeting using your selected lead time.

## Credits

This app is based on the original
[conniexu444/meeting-reminder](https://github.com/conniexu444/meeting-reminder)
project. Credit and thanks to Connie Xu for the original repository and app
foundation.

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
6. Add the Google accounts you want to test as **Test users**
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

Connected accounts appear in the menu bar popover. You can connect more
accounts from the same menu and remove accounts individually.

All local builds store connected Google account tokens in:

```text
~/Library/Application Support/MeetingReminder/GoogleOAuthCredential.json
```

That avoids repeated Keychain prompts while the app is unsigned or ad-hoc signed
from Xcode. The file is created with user-only permissions.

Use **Delete all local data** in the menu bar popover to remove connected
account tokens and reset local preferences like reminder choices, lead time, and
plane speed.

Use **Launch at login** in the menu bar popover to register or unregister the
app as a macOS Login Item. The same section shows the current Login Items
status and includes an **Open Login Items** shortcut to System Settings, where
you can also disable or remove the autostart entry.

Use **Censor mode** when demoing or screen sharing. It replaces account emails
and meeting titles with generic labels in the menu, planner, and reminder
banner while leaving the underlying calendar data unchanged.

If the macOS menu bar gets crowded, use the Dock/app icon as a fallback:
right-click **MeetingReminder** in the Dock and choose **Show Quick Menu**.
Clicking the Dock icon also reopens the quick menu window.

## Day Planner

After connecting Google Calendar, open **Day planner** from the menu bar popover.
The planner shows one day at a time, with previous/next day controls and a week
strip for jumping around the current week.

Each timed event has a checkbox:

- Checked events can trigger the banner reminder.
- Unchecked events are skipped by the reminder poller.
- Choices are stored locally in `UserDefaults`.

The menu bar popover shows the next three enabled reminder alarms and includes
a manual refresh button. It also lets you choose the reminder lead time. Calendar
data refreshes on app launch, when you click refresh, and every 10 minutes while
the app is running.

The planner refreshes when it opens, when you change dates, when you click the
refresh button, and every 10 minutes while the planner window is open.

---

## Testing Reminders

Use **Test airplane** to verify the visual banner immediately.

To test real Google Calendar polling:

1. Create a Google Calendar event that starts about your selected lead time from now
2. Make sure it is on a selected, visible calendar
3. Keep MeetingReminder running
4. Wait for the next poll cycle

The app refreshes Google Calendar every 10 minutes and keeps a local cache of
upcoming events across connected accounts. The background reminder checker scans
that cached list every 30 seconds and fires when a checked meeting is close to
your selected lead time.

---

## How It Works

- **Menu bar app**: `MeetingReminderApp.swift` uses `MenuBarExtra`
- **OAuth config**: `GoogleOAuthConfig.swift` loads the bundled
  `GoogleOAuthCredentials.json` desktop credential
- **OAuth**: `GoogleOAuthService.swift` opens Google sign-in in the browser,
  uses a localhost callback, exchanges the authorization code for tokens, and
  refreshes access tokens when needed
- **Token storage**: `GoogleOAuthService.swift` stores Google credentials in a
  local multi-account app-support file with user-only permissions
- **Calendar API**: `GoogleCalendarService.swift` reads selected Google
  calendars and events for every connected account
- **Refresh**: `AppController.swift` refreshes calendar data on launch, manual
  refresh, and every 10 minutes
- **Polling**: `CalendarPoller.swift` checks cached events every 30 seconds using
  the selected lead time and prevents duplicate alerts during the current app
  session
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
├── CalendarPoller.swift
├── AirplaneView.swift
├── AirplaneOverlayWindow.swift
├── MeetingReminder.entitlements
└── Assets.xcassets/
```

---

## Current Limitations

- Per-meeting opt-in/opt-out is local to this Mac
- Notifications are custom overlay banners, not macOS Notification Center banners
- The local OAuth credential JSON is intentionally not committed

---

## License

MIT
