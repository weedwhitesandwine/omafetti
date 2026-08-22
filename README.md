# OmaFetti

**It had to happen sooner or later — a useless plugin that blows confetti on your screen.**

![Omafetti](preview.png?v=2)

Press the hotkey and two party poppers go off in the bottom corners of the
screen, firing paper up and inward until it spreads everywhere and flutters
back down. It takes no keyboard focus and catches no clicks, so you can keep
typing straight through the celebration.

## Colours

Two modes, chosen in the settings card.

**Classic confetti** — the colours a real paper cannon comes loaded with,
whatever your desktop happens to look like. That's the shot above.

**Theme colours** — the hues of the active Omarchy theme, read from the
theme's own colour file. Change theme and the confetti changes with it. Below
is the same burst on the same wallpaper, in the theme's own reds:

![Omafetti in theme colours](preview-theme.png?v=2)

It stays faithful: a monochrome theme throws monochrome paper.

## Settings

The bar icon opens the settings card, and that is all it does — throwing is the
hotkey's job. There you choose the hotkey (recorded by pressing it), the colour
mode, the style of throw (**from the corners**, **cannon** from the bottom
centre, or **rain** from above), how much paper, and whether the bar icon shows
at all. **Throw some now** previews the choice before you apply it.

Confetti falls on every connected monitor.

## Install

```
omarchy plugin add https://github.com/weedwhitesandwine/omafetti.git --enable
```

The first time it opens, it shows the settings card so you can give it a
hotkey. Until you do, you can open the settings from a terminal:

```
omarchy-shell shell summon io.github.weedwhitesandwine.omafetti '{"view":"settings"}'
```

## Update

```
omarchy plugin update io.github.weedwhitesandwine.omafetti --yes
omarchy-restart-shell
```

## Remove

Turn the hotkey and the bar icon off in the settings card first (that removes
Omafetti's marked block from `bindings.lua` and its entry from the bar), then:

```
omarchy plugin remove io.github.weedwhitesandwine.omafetti
```

The only thing left behind is `~/.local/state/omafetti/`, which you can delete.

## Throwing confetti from anything else

The hotkey is not special — it just summons the plugin. Anything can:

```
omarchy-shell shell summon io.github.weedwhitesandwine.omafetti
```

Put that at the end of a build script, a passing test run, or a long download,
and the desktop celebrates for you.

## What it writes, and when

Omafetti has no network access, no background process, no timers that outlive a
burst, and no privileges: it never uses `sudo` or `pkexec` and does nothing as
root.

**Files it reads**

| Path | When |
|---|---|
| `~/.local/state/omafetti/settings.json` | On load, and whenever it changes |
| `~/.local/state/omarchy/current/theme/colors.toml` | On load, and on theme change — for the theme colour mode |

**Files it writes** — only when you press **Apply** in the settings card, never
on its own:

| Path | What |
|---|---|
| `~/.local/state/omafetti/settings.json` | Your choices |
| `~/.config/hypr/bindings.lua` | Only Omafetti's own marked block, between `-- >>> omafetti hotkey` and `-- <<< omafetti hotkey`. Everything outside those two lines is copied through untouched |
| `~/.config/omarchy/shell.json` | Only Omafetti's own `{"id": "io.github.weedwhitesandwine.omafetti"}` entry, moved between the bar layout and the enabled-plugins list |

**Processes it runs** — all of them only on **Apply**:

| Command | Why |
|---|---|
| `bash -c 'mkdir -p … && printf … > …'` | Save `settings.json` |
| `bash omafetti-ctl.sh bind`/`unbind` | Rewrite Omafetti's marked hotkey block |
| `bash omafetti-ctl.sh bar on`/`off` | Show or hide the bar icon |
| `hyprctl reload` | Called by the helper so a new hotkey takes effect immediately |
| `python3` | Called by the helper to edit `shell.json` as JSON rather than with text substitution |

## Dependencies

`bash`, `python3` and `hyprctl`, all of which Omarchy already installs. Nothing
else.

## Licence

MIT — see [LICENSE](LICENSE).

## Credits

Built with [Claude Code](https://claude.com/claude-code).
