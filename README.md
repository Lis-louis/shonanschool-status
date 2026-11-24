<p align="center">
  <img src="packaging/AppIcon-1024.png" width="128" alt="CampusHub icon">
</p>

<h1 align="center">CampusHub — Moodle, Campus Square and university mail in one place</h1>

<p align="center">
  <b>English</b> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  A Mac / Windows app for Shonan Institute of Technology that brings Moodle assignments and deadlines,<br>
  the Campus Square timetable and cancellations, and your university mail together on one screen.<br>
  It shares its colors and components with "Suzu" and uses Suzu's artwork.
</p>

---

## Features

- **Everything on one screen**: today's classes, your to-dos (unfinished Moodle assignments + mail that needs action), announcements, and university mail on the Home screen.
- **Calendar**: a month view showing your weekly timetable, Moodle events, deadlines, and due dates found in mail, day by day.
- **Automatic sign-in**: fills your saved ID and password into the official sign-in pages. It never builds or imitates a sign-in page of its own.
- **Automatic mail sorting**: reads Gmail (read-only) and sorts it into "action needed / deadlines", "cancellations / class changes", "exams / reports", "Moodle notifications", "events", and "announcements". It also detects reminder words and due dates, and shows why each mail was sorted where it is.
- **In-app browser**: download course materials and upload assignment files. Links outside the university's domain open in your default browser.
- **Built for each OS**: SwiftUI on Mac, Electron on Windows (`windows/`). Same screens, same way of reading pages.
- **Safety first**: passwords are stored only in the OS's secure storage (Keychain / DPAPI). Nothing read from the sites is written to disk.
- **Day / night theme**: Suzu's artwork and the colors follow your OS's light / dark appearance.

## Install

Download the installer for your OS from [Releases (latest)](https://github.com/Lis-louis/shonanschool-status/releases/latest).

| OS | File | Steps |
|---|---|---|
| Windows | `CampusHub-Setup-<version>.exe` from [Releases](https://github.com/Lis-louis/shonanschool-status/releases/latest) | Run it and follow the setup (install location → Install). Installs for the current user, no administrator rights needed. Creates desktop and Start menu shortcuts |
| macOS | `CampusHub-0.2.0.pkg` | **Coming soon** (run `./scripts/build-pkg.sh` on a Mac to build it). Installs キャンパスハブ.app into Applications |

To uninstall: on Windows, use **Settings → Apps → Installed apps → キャンパスハブ → Uninstall**. On macOS, move キャンパスハブ from Applications to the Trash.

> The installers are not code-signed yet, so the OS may warn you the first time.
> Windows: if SmartScreen appears, click **More info → Run anyway**.
> macOS: if it is blocked, right-click → **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Updates (Windows)

The Windows version (0.3.0 and later) updates itself.

1. At launch (and every 3 hours after that) it checks [Releases](https://github.com/Lis-louis/shonanschool-status/releases) for a newer version
2. If there is one, it downloads it in the background and shows "**New version x.y.z is ready [Restart to update]**" at the top of the window
3. Click **Restart to update** and the app relaunches on the new version within a few seconds. If you just quit instead, the update is applied as the app closes

To check right away, use **Settings → App → Check for updates** (or the menu **File → Check for app updates**).

> Versions 0.2.0 and earlier have no automatic updates, so install the latest installer from Releases once by hand (your settings and sign-in details carry over).
> Automatic updates for the Mac version are coming soon.

## Requirements

- Windows 10 / 11, 64-bit (x64)
- macOS 14 Sonoma or later
- To build: Node.js LTS (Windows version), Xcode 16 or later / Swift 6 toolchain (Mac version)

## First-time setup

1. Save your student ID and password in **Settings → Sign-in**, then press **Refresh**.
2. To see university mail too, set up the Google connection as described in [Connecting Gmail](#connecting-gmail).
3. To just look at the screens, use **Settings → Show sample data**.

## Screens

| Screen | What it shows |
|---|---|
| Home | Today's classes (click one to open its Moodle course, or search Moodle for it if no course matches) / **To-dos** = unfinished Moodle assignments + mail that needs action / announcements / mail from the university |
| Calendar | Month view of the weekly timetable, Moodle events, deadlines, and due dates found in mail |
| Moodle | **Summary**: assignments and deadlines, notifications (those about work you have already submitted are folded away), courses (with progress; hide courses you no longer take with "Hide" and bring them back from "Hidden courses"). **Browser**: the official site inside the app |
| Campus Square | **Summary**: timetable by weekday, cancellations / make-up classes, portal announcements. **Browser**: the official site |
| Mail | Reads Gmail (read-only) and sorts it by content |
| Settings | Sign-in, Gmail connection, automatic sign-in, URLs, what to show, notifications, sample data, app version and update check (Windows), **connection diagnostics** |

### Shortcuts

| Action | Result |
|---|---|
| Ctrl+R (Windows) / ⌘R (Mac) | Refresh |
| Ctrl+1–6 (Windows) | Switch to Home, Calendar, Moodle, Campus Square, Mail, Settings |
| `CampusHub.exe --section calendar` (Windows)<br>`open -a キャンパスハブ --args --section calendar` (Mac) | Open on a given screen (`home` / `calendar` / `moodle` / `campusSquare` / `mail` / `settings`) |

## How it works

1. **Automatic sign-in**: types your saved ID and password into the fields of the official sign-in pages (Moodle: `#username` / `#password`, Campus Square: `#userNameInput` / `#passwordInput`) and presses the button.
2. **Summaries**: opens the signed-in pages in a browser that is never shown, then
   - Moodle: calls the AJAX services that Moodle's own dashboard uses (`core_course_get_enrolled_courses_by_timeline_classification`, `core_calendar_get_action_events_by_timesort`, `message_popup_get_popup_notifications`) from the signed-in page.
   - Campus Square: reads the text in each portal panel, the weekday table (timetable), and the table on the cancellations page.
3. **In-app browser**: supports downloading materials (to your Downloads folder), uploading assignment files, and `_blank` links. Links outside the university's domain open in your default browser.

## Safety and privacy

- Your ID and password are stored only in the OS's secure storage, never in code, settings files, or logs.
  - Mac: Keychain (`WhenUnlockedThisDeviceOnly`: no iCloud sync or migration)
  - Windows: encrypted with DPAPI in `%APPDATA%\キャンパスハブ\secrets.json` (Electron safeStorage)
- Automatic sign-in only fills pages that are https and whose host exactly matches the configured sign-in host. Filling runs in an environment isolated from the page's own scripts.
- The sign-in button is pressed automatically at most once every 30 seconds, so repeated failures can't lock your account.
- What the app reads stays in memory and is never saved to disk. Cookies stay in the app's own storage (delete them with **Settings → Clear sign-in state**).
- Data is refreshed only by hand (at launch and with the Refresh button). The app never polls the university's servers in the background.
- The app update check (Windows) connects only to GitHub (github.com) and sends nothing beyond what an ordinary download does (never your ID, password, or anything the app has read).

> Check for yourself whether your university's terms of use and information policies allow automatic sign-in and reading pages this way.

## Connecting Gmail

Google doesn't allow signing in through a browser embedded in an app, so CampusHub uses Google's official OAuth (sign-in happens in your default browser) and the Gmail API (read-only). You need to set this up once:

1. Create a new project in the [Google Cloud Console](https://console.cloud.google.com/) (a personal Google account is fine).
2. Under **APIs & Services → Library**, enable the **Gmail API**.
3. Create an **OAuth consent screen** (type: External, publishing status: Testing). **Add your university email address as a test user.**
4. Under **Credentials → Create credentials → OAuth client ID**, create one of type **Desktop app**.
5. In CampusHub, enter the client ID and secret in **Settings → Mail (Gmail)** and save.
6. Click **Sign in with Google**, choose your university account in the browser, and allow read access.

- If your university's administrators restrict third-party apps, step 6 shows "Access blocked". Ask your university (e.g. its IT center) in that case.
- Only the subject, sender, date, and the first part of the body (snippet) are fetched, and they are not saved. The refresh token and secret go into the same secure storage as your password.
- Sorting uses fixed keywords and date formats (Mac: `Sources/CampusHub/Services/MailClassifier.swift`).

## Build and run

### Windows (`windows/`)

Requires the LTS version of [Node.js](https://nodejs.org/).

```bat
cd windows
npm install
npm test             & rem unit tests
npm start            & rem launch without installing
npm run dist:win     & rem build the installer
```

`npm run dist:win` creates `dist\windows\CampusHub-Setup-<version>.exe` (for trying it on your own PC; releases are published automatically, see [Publishing a new version](#publishing-a-new-version-windows) below).

### macOS

```sh
git clone https://github.com/Lis-louis/shonanschool-status.git
cd shonanschool-status

./scripts/build-app.sh --install   # installs /Applications/キャンパスハブ.app (use this to keep it in the Dock)
swift run                          # launch for development
swift test                         # unit tests
```

### Building the installers

| Installer | Command | Output |
|---|---|---|
| Windows `.exe` | `cd windows && npm run dist:win` (on Windows)<br>`./scripts/build-windows.sh` (on a Mac) | `dist/windows/CampusHub-Setup-<version>.exe` |
| macOS `.pkg` | `./scripts/build-pkg.sh` (on a Mac) | `CampusHub-<version>.pkg` (repository root; installs /Applications/キャンパスハブ.app) |

- The Mac `.pkg` can't be built on Windows. The Windows `.exe` can also be built on a Mac (`./scripts/build-windows.sh --run` to preview the screens, `--test` to run the tests only).

### Publishing a new version (Windows)

1. Make your changes
2. Bump `"version"` in `windows/package.json` (e.g. `0.3.0` → `0.3.1`)
3. Push to main

GitHub Actions (`.github/workflows/release-windows.yml`) then runs the tests, builds the installer, and publishes it to [Releases](https://github.com/Lis-louis/shonanschool-status/releases) (tag `v<version>`).
Once it is published, installed copies of the app show "Restart to update".

- Pushing without bumping `version` does nothing (a Release for that version already exists).
- Follow progress in the **Actions** tab on GitHub. To run it by hand: Actions → "Windows 版をリリース" → **Run workflow**.
- Each Release holds three files: `CampusHub-Setup-<version>.exe`, `.exe.blockmap`, and `latest.yml`. The app finds new versions through `latest.yml`, so don't delete it.

## Troubleshooting

**Settings → Connection diagnostics** and the diagnostics log show where loading stopped (host and path of the opened page, item counts, errors). Your ID, password, mail, and class contents are never written there.

- Mac: `~/Library/Logs/CampusHub/diagnostics.log`
- Windows: `%APPDATA%\キャンパスハブ\logs\diagnostics.log` (menu **File → Open diagnostics log folder**)

## Where things are configured

| Item | Location |
|---|---|
| Per-university defaults (URLs, sign-in form selectors) | Mac: `Sources/CampusHub/Config/DefaultConfig.swift`<br>Windows: `windows/src/main/config.js` (same values; change both together) |
| Changes for your own computer only | The app's Settings (Mac: UserDefaults, Windows: `%APPDATA%\キャンパスハブ\settings.json`) |
| ID and password | **Settings → Sign-in** in the app |
| Scripts that run inside pages | Mac: `Sources/CampusHub/Web/Scripts.swift`, Windows: `windows/src/main/scripts.js` (same content) |
| Colors | `Sources/CampusHub/Theme/Theme.swift` (same values as Suzu's `appearance.palette`) |
| Images | `Sources/CampusHub/Resources/Appearance/` (Suzu's `face_*.jpg` and `hero_*.jpg`; the Windows version uses the same files) |
| App icon | Replace `icon/campus-hub.svg`, then run `./scripts/make-icon.sh && ./scripts/build-app.sh --install` |

## Project structure

```
Sources/CampusHub/        Mac version (SwiftUI)
├─ App.swift              launch, sidebar, overall layout
├─ Config/                per-university defaults
├─ Models/                settings, data types, URL validation
├─ Services/              Keychain, notifications, Gmail, mail sorting, sample data
├─ Store/                 state and loading flow
├─ Theme/                 Suzu theme (colors, cards, faces, background)
├─ Web/                   automatic sign-in, hidden WebView, in-app browser, page scripts
├─ Views/                 screens
└─ Resources/Appearance/  Suzu's artwork
Tests/CampusHubTests/     tests for URL validation, Moodle response parsing, timetable, etc.
windows/                  Windows version (Electron)
├─ src/main/              sign-in, reading, Gmail, storage (main process)
├─ src/renderer/          screens
├─ src/preload.js         bridge between the screens and the main process
└─ test/                  unit tests (npm test)
icon/                     app icon source (SVG)
packaging/                Mac icons (.icns, PNG)
scripts/                  build scripts for the .app, .pkg, and Windows .exe
.github/workflows/        GitHub Actions that publish the Windows version to Releases
```

## Status

| Item | Status |
|---|---|
| Mac version (SwiftUI) | Done |
| Windows version (Electron) | Done (installer and automatic updates) |
| Moodle / Campus Square sign-in and reading | Done |
| Gmail connection and sorting | Done |
| Distributing the Mac installer (.pkg) | Coming soon |
| Automatic updates for the Mac version | Coming soon |

### Unconfirmed and estimated values

| Item | Value | Status |
|---|---|---|
| Moodle | `https://moodle2026.shonan-it.ac.jp` | Confirmed (sign-in form too) |
| Campus Square | `https://portal.shonan-it.ac.jp/campusweb/` | Confirmed (sign-in form too) |
| Timetable | `campussquare.do?_flowId=RSW0001000-flow` | Confirmed (portal menu "履修登録・登録状況照会") |
| Cancellations / make-up classes | `_flowId=KHW0001100-flow` | **Estimated** |
| Grades / syllabus | `SIW0001300-flow` / `SYW0001000-flow` | **Estimated** |
| Attendance | `https://syusseki.shonan-it.ac.jp/campusaa/` | From a link on the sign-in page |
| University mail | Google Workspace (Gmail) | Confirmed via DNS (MX records) |

If an estimated page is wrong: open the correct page in Campus Square's **Browser**, then use **…** at the top right → "このページを『時間割』に設定" (set this page as the timetable).

### Known limitations

- The URLs for cancellations, grades, and the syllabus are estimated, so they may not match the university's pages (fix them as described above).
- On Windows, deadline notifications appear in the notification center only while the app is running.
- If the university changes its sites, reading may stop working (check **Settings → Connection diagnostics**).
- The app is shown in Japanese only.

## License

Code and character are licensed separately.

| What | License |
|---|---|
| Code (`Sources/`, `Tests/`, `windows/`, `scripts/`, etc.) | [MIT License](LICENSE) |
| The character Suzu (name, design, images in `Sources/CampusHub/Resources/Appearance/`, icons containing her artwork) | [Character Usage Guidelines](CHARACTER_GUIDELINES.en.md) |

You may draw and share non-commercial fan art of Suzu, with credit.
The following are not allowed:

- Uses that go against public decency
- Reposting or redistributing the images
- Commercial use
- Using Suzu for AI training

If you distribute a modified version of the app, remove all of Suzu's images and icons (it is no longer the official version).

```
Character "Suzu" © Lis-louis
```
