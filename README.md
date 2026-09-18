# Downloads

What just landed in your download folder, one click from the Omarchy bar —
and every row is a drag handle, so a file goes straight into the upload field,
chat window, or editor that needs it.

The bar button carries a badge counting the files that arrived in the last few
minutes, so a finished download is visible without opening anything.

| Tokyo Night | Catppuccin Latte |
|---|---|
| ![The downloads popout on a dark theme](screenshots/panel.png) | ![The same popout on a light theme](screenshots/light.png) |

## A panel you can drag out of

The list opens as a layer-shell panel anchored to its bar button. It stays
out of the tiling layout and closes with Esc or a click outside it. No
Hyprland window rules are needed.

During a file drag, the panel limits its input region to the visible card
and removes outside-click surfaces on other monitors. This lets the
application under the pointer receive the drop. After the drag finishes or
is cancelled, outside-click dismissal is restored.

## Installing

```bash
omarchy plugin add https://github.com/jankeesvw/omarchy-downloads
omarchy plugin enable jankeesvw.downloads
omarchy bar move jankeesvw.downloads --section right
```

If upgrading from the floating-window version, the old rules matching
`org.quickshell` with title `Downloads` can be removed from your Hyprland
configuration; this panel does not use them.

### A key for it

```lua
o.bind("SUPER + D", "Downloads", "omarchy-shell shell toggle jankeesvw.downloads")
```

## Using it

| | |
|---|---|
| Click the bar button | open and close the list |
| Right-click the bar button | open the folder in your file manager |
| Drag a row | hand the file to whatever is under the cursor |
| Double-click a row | open the file |
| `Last N min` / `All` | show only what just arrived, or the whole folder |
| `Esc` or click outside | close |

## Settings

Set these on the plugin's entry in `~/.config/omarchy/shell.json`:

| Setting | Default | What it does |
|---|---|---|
| `freshMinutes` | `5` | How recent a file counts as "just arrived" — drives the badge, the accent, and the first filter |
| `folder` | XDG download dir | Watch a different folder, as a plain path |

```json
{ "id": "jankeesvw.downloads", "freshMinutes": 10 }
```

## What it does not do

- **Partial downloads are hidden.** `.crdownload`, `.part`, `.tmp` and friends
  are still being written and the final name is not known yet.
- **The list caps at 200 rows, and a refresh reads at most 2000 files.** Both
  caps cut from the oldest end - the folder is read newest first - so a recent
  download is never the thing that falls outside them. The panel says what it
  left out rather than pretending the folder is smaller than it is.
- **Not every change gets its own refresh.** A folder filling up reports one
  change per file, and those are collapsed into a single rebuild. A folder too
  large to watch cheaply is polled instead of watched - one read per interval
  rather than one per file - and with the panel closed the refresh backs off.
  Below that size nothing changes: a download appears the moment it lands.
- **A file that grows after it appears keeps its first size.** The folder
  watcher reports new and removed files, not writes to existing ones. Browsers
  rename on completion, so finished downloads are accurate.

## Removing it

```bash
omarchy plugin remove jankeesvw.downloads
```

**Nothing is left behind.** This plugin writes no cache, no config, and no
state of its own: it reads the download folder through Qt's folder model and
keeps everything in memory. There is no directory to clean up and nothing about
your files is stored anywhere.

If you added Hyprland window rules for an older version, remove those
separately from your Hyprland configuration.

## Privacy

Filenames never leave your machine. There is no network access, no telemetry,
and no helper script — the plugin is QML that reads a directory listing.
Filenames are rendered as `Text.PlainText` throughout, so a file named to look
like markup cannot make the shell fetch a remote image.

## License

MIT — see [LICENSE](LICENSE).
