# Skye

**A desktop shell for Wayland, built with [Quickshell](https://quickshell.org/) (QML).**

Made to live well with the [Umbriel](https://github.com/noctalia-dev/umbriel) compositor,
but it works on any compositor with `wlr-layer-shell` — KWin, Hyprland, niri, Sway…

![Wayland](https://img.shields.io/badge/Wayland-000000?style=flat-square&logo=wayland&logoColor=white)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3.1-f4be9e?style=flat-square)
![CachyOS](https://img.shields.io/badge/CachyOS-ready-00c1a2?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-efeceb?style=flat-square)

---

## ✨ Features

### Dynamic island

- **Floating pill-shaped bar**, one per monitor, with clicks passing through
  outside the pill (`mask`/`Region`).
- **Idle shows only the clock**; on hover, the pill **expands with an
  animation** (width + slide + fade) and reveals the side elements.
- **Recording**: the island becomes the **REC** indicator — pulsing red dot,
  recording time and pause/resume and stop buttons.
- **Volume**: when the volume/mute changes (media keys, apps), the island shows
  an **OSD** with a bar and percentage (it hides by itself).
- **Music**: while music is playing, the island shows the **album art** +
  animated equalizer bars + title.
- **The island adapts to the panels**: when a panel opens, it grows to the
  panel width and merges into it (no gap or divider line); when it closes, it
  goes back to normal — all animated.
- **Left (hover)**: desktop/workspace dots — **KWin via D-Bus** or
  Umbriel (automatic fallback). The current desktop gets bigger and lit; click
  switches desktop. Next to them, the bell with a dot when there are
  notifications.
- **Right (hover)**: three circular buttons **with colors only**; the selected
  one gets a soft radial-gradient glow:
  - **Orange** — notifications (opens/closes the panel)
  - **Magenta** — Control Center (opens/closes)
  - **Cyan** — Recent (opens/closes the recent files panel — hub)

### Control Center

- Tabs: **Control Center | Dashboard | Clipboard & Notes | OpenCode** (fixed
  height, no "jumping" when switching tabs).
- **Control Center**: Quick Settings (Network, Do Not Disturb, Night Light,
  Caffeine, Bluetooth, **Recorder** — records the screen and lights up while
  recording, **Camera** — webcam preview) + Session (Lock, Log out, Restart,
  Shut down); **Levels** with Output/Microphone/Brightness sliders, mute on the
  icon and an **audio device picker** on the arrow; **app mixer** (the button
  swaps the Levels for the list of apps playing sound, with per-app slider and
  mute); media line (MPRIS).
- **Music**: hovering the island (with music playing) opens a panel with
  album art and **album-color glow**, controls (previous/play/next), seek,
  **audio output**, **per-app mixer** and **lyrics** (lrclib, with sync and the
  current line highlighted).
- **Dashboard**: greeting ("Good morning/afternoon/evening, Name"), **calendar**
  with the current week + mini-month, **weather** with hourly forecast
  (humidity, wind, rain) and a **rain alert** when rain is coming, plus
  **System** with CPU, RAM, GPU, temperature, disk and uptime — all with
  little bars.
- **Clipboard & Notes**: clipboard history (left click copies back, right click
  removes) and notes (multiple, with title, saved to
  `~/.local/share/skye/notes.json`).
- **Footer** with shortcuts: Terminal, Files, Browser, Clipboard, Settings and
  the **language toggle (pt-BR/EN)**.

### Notifications and services

- **Notification panel** with color-coded category tabs (they filter the
  list), "clear all", action buttons and the **system tray** in the footer.
- **Toasts** stacked in the top-right corner (up to 4, they hide by
  themselves).
- **Central theme** in `Theme.qml`: black background, warm white text
  (`#efeceb`), peach accent (`#f4be9e`).
- **Proton Calendar** (optional): days with events get a dot under the number on
  the Dashboard calendar; clicking a day lists the events (time, title,
  location, description). See Integrations.
- **Discord Rich Presence** (optional): while Deezer plays, your Discord status
  shows the track (artists, title, album art and progress). See Integrations.
- **Custom IPC** to control everything from the command line.

---

## 📦 Requirements

**Required**

| Package | For what |
|---|---|
| `quickshell` (≥ 0.3.1) | the shell itself |
| Nerd Font (`ttf-jetbrains-mono-nerd` or similar) | UI icons |
| `curl` | weather (Open-Meteo) |

**Optional** (each one enables a feature; without it the UI degrades on its own)

| Package | For what |
|---|---|
| `umbriel` | workspaces via the compositor IPC (otherwise uses KWin) |
| `pipewire` / `wireplumber` | volume and microphone sliders |
| `ddcutil` | external monitor brightness (DDC/CI) |
| `nvidia-smi` / `lm_sensors` | GPU and temperature on the Dashboard |
| `kitty` | terminal button in the footer |
| `wl-clipboard` | clipboard history (wl-paste/wl-copy) |
| `gammastep` | Night Light button |
| `network-manager-applet` | network icon in the tray (`nm-applet --indicator`, start it with the session) |
| `qt6-multimedia` | camera preview (Camera button) |
| `curl` | lyrics (lrclib) and album art |
| `gpu-screen-recorder` | all-screens recording (Recorder button; uses NVENC/GPU and system audio + microphone) |
| `khal`, `vdirsyncer` | Proton Calendar events on the Dashboard |
| `discord` (native, not Flatpak/Snap), `python3` | Discord Rich Presence for the Deezer track |
| `opencode` | OpenCode tab in the Control Center (prompts with streaming responses) |

---

## 🚀 Installation

```bash
git clone https://github.com/marcoantoniio/skye ~/.config/quickshell/skye
qs -c skye -n -d        # starts in the background
```

Stop / inspect:

```bash
qs -c skye kill         # quits
qs -c skye list         # shows running instances
qs -c skye log          # prints the logs
```

### Start with the session (optional)

Via user systemd:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/skye.service <<'EOF'
[Unit]
Description=Skye (Quickshell shell)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# NVIDIA + Wayland: Qt may fall back to the basic render loop (~60 fps);
# Vulkan uses the threaded render loop. Uncomment if animations feel capped.
# Environment=QSG_RHI_BACKEND=vulkan
# On setups with monitors of different refresh rates, the default animation
# driver steps at the primary screen's rate; this keeps animations in real
# time on the faster monitor. Uncomment if animations look ~60 fps.
# Environment=QSG_USE_SIMPLE_ANIMATION_DRIVER=1
ExecStart=/usr/bin/qs -c skye -n
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user enable --now skye.service
```

Or copy a `.desktop` file into `~/.config/autostart/` (and into
`~/.local/share/applications/` if you want to launch it from the menu):

```ini
[Desktop Entry]
Type=Application
Name=Skye Shell
Exec=qs -c skye -n -d
Icon=video-display
Terminal=false
Categories=Utility;
```

---

## 🎮 How to use

- **Idle**: only the clock. **Hover**: the island expands and reveals the
  controls.
- **Dots on the left**: click to switch desktop/workspace.
- **Buttons on the right**: notifications, Control Center and Recent.
- **In the panel**: use the tabs at the top; the footer has the app shortcuts.

---

## 🧩 Integrations (optional)

### Proton Calendar

Shows your Proton Calendar events on the Dashboard calendar. Proton has no
CalDAV, so this uses a read-only sharing link:

1. In the Proton Calendar web app, go to Settings → All settings → Calendars,
   pick the calendar and create a link under **Share with anyone**:
   **Full view** shows event details, **Limited view** shows busy times only.
2. Install `khal` and `vdirsyncer`.
3. Save the link in `~/.config/vdirsyncer/config` (create the file if needed):

```ini
[general]
status_path = "~/.local/share/vdirsyncer/status/"

[pair proton]
a = "proton_local"
b = "proton_remote"
collections = null

[storage proton_local]
type = "filesystem"
path = "~/.local/share/skye/proton/"
fileext = ".ics"

[storage proton_remote]
type = "http"
url = "YOUR_PROTON_SHARE_LINK"
```

The link is a secret — anyone with it can read that calendar — so keep the
file private (`chmod 600`).

4. Create `~/.config/khal/config`:

```ini
[calendars]

[[proton]]
path = ~/.local/share/skye/proton/
type = calendar

[locale]
timeformat = %H:%M
dateformat = %Y-%m-%d
longdateformat = %Y-%m-%d
datetimeformat = %Y-%m-%d %H:%M
longdatetimeformat = %Y-%m-%d %H:%M
```

5. First-time setup:

```bash
mkdir -p ~/.local/share/skye/proton
vdirsyncer discover proton
vdirsyncer sync proton    # first sync (Skye syncs every 30 minutes after this)
```

Skye runs `vdirsyncer sync` every 30 minutes by itself — no cron needed.
Proton can take up to 8 hours to reflect changes in the link, and the link
can stop working after a while (generate a new one in Proton if that
happens).

### Discord Rich Presence

Shows the track you are playing on Deezer in your Discord profile. Requires
the **native** Discord client (Flatpak/Snap sandbox the IPC socket) and
`python3`.

1. Create an application at <https://discord.com/developers/applications>.
   The name you give it is what Discord displays in "Listening to …".
2. Copy the **Application ID** (General Information) and save it in
   `~/.config/skye/discord_client_id.txt`:

   ```bash
   mkdir -p ~/.config/skye
   printf '%s\n' YOUR_APPLICATION_ID > ~/.config/skye/discord_client_id.txt
   ```

   Then restart Skye (`systemctl --user restart skye.service`) to pick it up.

That is all Skye needs — no Client Secret and no bot token. Never share
those; the Application ID itself is public.

While Deezer is playing you get the artists (all of them — the Deezer app
sends only the main artist over MPRIS, so the list is completed from Deezer's
public API), the title, the album art (with an animated equalizer badge), a
progress bar and a "Listen on Deezer" button (buttons are only visible to
other people). Pausing clears the presence.

### OpenCode tab

Prompts OpenCode from the bar, streaming the answer line by line. Requires
the `opencode` CLI.

The tab keeps a session of its own (persisted across restarts), an input
line with history (↑/↓), a **broom** button (wipes the visible chat) and a
**plus** button (fresh session). The commands:

- `cd <dir>` (or `/cd <dir>`) — where the agent works (default: your home
  directory). It starts a fresh session there, because OpenCode sessions
  belong to the directory where they were created. `cd ..`, `cd -` (back to
  the previous directory) and `~` work like in a terminal;
- `/model <name>` — pick a model (empty resets to OpenCode's default);
- `/new` — start a fresh session (same as the plus button).

It runs with `--auto`, so the agent may read and edit files and run
commands without asking for approval — keep that in mind when pointing it
at a directory with important files.

---

## ⌨️ IPC

```bash
qs -c skye ipc show                          # lists everything available

qs -c skye ipc call notifications toggle     # notifications panel
qs -c skye ipc call notifications toggleDnd  # do not disturb
qs -c skye ipc call controlcenter toggle     # control center
qs -c skye ipc call controlcenter setTab 1   # 0=CC, 1=Dashboard, 2=Clipboard, 3=OpenCode
qs -c skye ipc call controlcenter toggleMixer  # app mixer (instead of Levels)
qs -c skye ipc call workspaces switchToIndex 1
qs -c skye ipc call brightness set 40        # brightness (DDC/CI)
qs -c skye ipc call weather refresh
qs -c skye ipc call clipboard copy "text"
qs -c skye ipc call recorder start           # records all screens (~/Videos)
qs -c skye ipc call recorder pause           # pauses/resumes recording
qs -c skye ipc call recorder stop            # stops and saves the file
qs -c skye ipc call music status             # current music (MPRIS)
qs -c skye ipc call music toggle             # play/pause
qs -c skye ipc call discord status           # Discord Rich Presence state
qs -c skye ipc call opencode send "prompt"   # OpenCode tab: prompt (streams the answer)
qs -c skye ipc call opencode clear           # clears the OpenCode tab chat
qs -c skye ipc call opencode status          # OpenCode tab state
qs -c skye ipc call audio setVolume 0.5      # output volume (shows the OSD)
qs -c skye ipc call timer pomodoro           # pomodoro/stopwatch (no UI yet)
qs -c skye ipc call timer status             # pomodoro/stopwatch state
qs -c skye ipc call camera toggle            # camera preview
qs -c skye ipc call recent toggle            # recent files panel (hub)
qs -c skye ipc call language toggle          # language: pt-BR/EN
```

---

## 🎨 Customization

> [!WARNING]
> The globe button in the Control Center footer opens **`https://localhost`** —
> the repository author's **local SearXNG** instance. If your machine doesn't
> run SearXNG there (or it runs on another host/port), change the URL in
> `ControlCenterPanel.qml` (footer, globe icon) or point it to the search
> engine of your choice.

| I want to change… | File |
|---|---|
| Colors, fonts and metrics | `Theme.qml` |
| Weather city (coordinates) | `Weather.qml` → `location` |
| Friendly disk names | `ControlCenterPanel.qml` → `diskName()` |
| Terminal button command | `ControlCenterPanel.qml` (footer) |
| Browser button URL (local SearXNG) | `ControlCenterPanel.qml` (footer) |
| Panel size | `Theme.qml` → `controlCenterPanelWidth` |
| Camera panel screen | `Theme.qml` → `cameraScreenName` |
| Dynamic island monitor | `Theme.qml` → `barScreenName` |
| Discord Application ID (Rich Presence) | `~/.config/skye/discord_client_id.txt` |
| Proton Calendar sharing link | `~/.config/vdirsyncer/config` |

Colors use Qt's `#AARRGGBB` format (the `AA` is the transparency).

---

## 📁 Structure

| File | Role |
|---|---|
| `shell.qml` | entry point; creates one bar per monitor |
| `Theme.qml` | theme (colors, fonts, metrics) and panel widths |
| `I18n.qml` | translations (pt-BR/EN) and language IPC |
| `Bar.qml` | the dynamic island (collapses/expands on hover) |
| `Clock.qml`, `Bell.qml`, `WorkspacePills.qml`, `CategoryButtons.qml`, `CategoryCircle.qml` | island widgets |
| `ControlCenter.qml`, `ControlCenterPanel.qml`, `PanelTab.qml`, `QuickToggle.qml`, `LevelRow.qml`, `LevelSlider.qml`, `DeviceMenu.qml`, `FooterIcon.qml` | Control Center |
| `CalendarCard.qml`, `WeatherCard.qml`, `SystemCard.qml`, `Weather.qml`, `Greeting.qml` | Dashboard |
| `Clipboard.qml` | clipboard history |
| `Notes.qml` | notes (persisted in `~/.local/share/skye`) |
| `Brightness.qml` | DDC/CI brightness |
| `Workspaces.qml`, `Umbriel.qml` | desktops (KWin + Umbriel) |
| `Notifications.qml`, `NotificationCenter.qml`, `NotificationPopup.qml`, `NotificationPopups.qml`, `FilterTab.qml` | notifications |
| `Tray.qml` | system tray |
| `RecentFiles.qml`, `RecentFilesPanel.qml` | recent files panel (cyan button hub) |
| `ProtonCalendar.qml` | Proton Calendar events (vdirsyncer + khal). See Integrations |
| `DiscordPresence.qml`, `discord_rpc.py` | Discord Rich Presence for the Deezer track. See Integrations |
| `OpenCode.qml`, `OpenCodeTab.qml` | OpenCode tab in the Control Center (streaming). See Integrations |

---

## 📝 Notes and limitations

- The Control Center panel has a **fixed height** so it doesn't reposition when
  switching tabs.
- **Notifications**: the shell needs to own
  `org.freedesktop.Notifications`. Under KDE with plasmashell running, the
  native panel wins — under Umbriel (or without plasmashell) it works normally.
- **Workspaces**: uses KWin via D-Bus; under Umbriel it automatically falls back
  to the compositor IPC.
- **Clipboard**: the history uses `wl-clipboard` (`wl-paste --watch` +
  `wl-copy`); without it installed, the tab shows "unavailable".
- **Brightness**: depends on the monitor supporting DDC/CI.
- The audio device menu doesn't close when clicking outside (a limitation of
  nested popups on Wayland); close it by clicking the arrow or picking an item.

---

## 📚 Documentation

- Quickshell: <https://quickshell.org/docs/>
- Umbriel (compositor): <https://docs.noctalia.dev/umbriel/>

---

## 📄 License

MIT — see [`LICENSE`](LICENSE).
