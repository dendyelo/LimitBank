# LimitBank 🏦

**LimitBank** is a lightweight, sleek macOS menu bar utility designed for developers to monitor their API quotas and token limits for **Antigravity (Google Gemini)** and **Codex (OpenAI)** accounts in real time.

## Screenshots 📸

<p align="center">
  <img src="screenshots/popover.png" alt="LimitBank Popover Status" width="220" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="screenshots/settings.png" alt="LimitBank Settings" width="480" />
</p>

## Features 🚀

- **Real-Time Quota Monitoring**: Tracks hour, day, week, and monthly limits with beautiful progress bars directly from the macOS menu bar.
- **Multi-Account Support**: Manage multiple accounts simultaneously. Easily switch active sessions for both Codex and Antigravity.
- **Native macOS Experience**: Designed with a clean, responsive SwiftUI popover, monochrome checkmarks, and native-feeling settings sidebar.
- **Independent Sessions**: Google Antigravity tokens are kept separate from IDE instances, allowing you to use multiple accounts without conflicts.
- **Sleek Integration**: Automatically quits and restarts Codex or Antigravity applications when switching active sessions to apply credentials instantly.
- **OAuth Auto-Sync**: Built-in OAuth server automatically captures browser login codes and updates configuration forms in real time.

## Installation & Build 🛠️

To compile and package the app as a native macOS bundle:

1. Clone the repository to your local machine.
2. Build the `.app` bundle by running the helper script:
   ```bash
   ./build_app.sh
   ```
3. Open the newly created `LimitBank.app` in your workspace directory:
   ```bash
   open LimitBank.app
   ```

## Configuration ⚙️

- **Antigravity Accounts**: Simply click **Sign In via Google (Browser)** in settings to authenticate and monitor your Gemini quotas.
- **Codex Accounts**: Click **Launch Codex CLI Login** to switch between OpenAI accounts cleanly without revoking tokens on the server.

---
Created by [dendyelo](https://github.com/dendyelo). Built with SwiftUI.
