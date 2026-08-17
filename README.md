# KittyTaskbar

A tiny macOS menu bar app that acts as a taskbar for the [kitty](https://sw.kovidgoyal.net/kitty/) terminal: it lists every kitty OS window and tab, lets you jump to any of them with a single click, and lets you move tabs between windows with drag & drop.

macOS has no per-window taskbar and the Dock groups all kitty windows under one icon — KittyTaskbar fills that gap from the menu bar (🐱 icon).

## Features

- Lists all kitty OS windows and their tabs, grouped per window, refreshed every time the panel opens
- Click a tab to focus it and bring kitty to the front (the active tab shows a checkmark)
- Drag a tab by its grip handle (≡) onto another window group to move it there
- Drop a tab onto the dashed area at the bottom to detach it into a new OS window
- Splits (multiple kitty windows inside a tab) are listed as indented rows and are clickable too
- Supports multiple running kitty instances; right-click the menu bar icon to quit

## Requirements

- macOS 13 (Ventura) or newer
- kitty with remote control enabled in `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}
```

Restart kitty after changing the config.

## Install

### Homebrew

```sh
brew tap muarifer/tap
brew trust muarifer/tap   # required on Homebrew 6+
brew install --cask kitty-taskbar
```

Releases are signed with a Developer ID certificate and notarized by Apple, so Gatekeeper allows them without any extra steps.

### Build from source

```sh
git clone https://github.com/muarifer/kitty-taskbar.git
cd kitty-taskbar
./build.sh            # produces KittyTaskbar.app
open KittyTaskbar.app
```

To start it automatically at login, add `KittyTaskbar.app` to System Settings → General → Login Items.

## How it works

- Discovers kitty control sockets at `/tmp/kitty-<pid>` (stale sockets from dead processes are filtered out)
- Fetches the window/tab list with `kitten @ ls` each time the panel opens
- Focuses tabs with `kitten @ focus-tab --match id:N` (splits use `focus-window`) and activates the kitty app
- Moves tabs with `kitten @ detach-tab --match id:N --target-tab id:M`; dropping on the dashed zone omits `--target-tab`, detaching into a new OS window
- Tab moves only work within the same kitty instance — kitty's `detach-tab` cannot move tabs across processes

## License

[MIT](LICENSE)
