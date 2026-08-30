# OmaFetti

**It had to happen sooner or later — a useless plugin that blows confetti on your screen.**

![Omafetti](preview.png?v=3)

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
is the same burst on the same wallpaper, in the theme's own pinks:

![Omafetti in theme colours](preview-theme.png?v=3)

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

Omafetti runs as your own user. Everything it reads, writes and runs is listed
below, and that list is complete.

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

**Processes it runs**

| Command | When |
|---|---|
| `python3 -c` (a short reader, inline below) | On load, when the settings card is opened, and whenever the theme changes — to read those two files to a size ceiling |
| `bash -c 'mkdir -p … && mktemp … && printf … && mv …'` | On **Apply** — save `settings.json`, staged under an exclusively-created temporary name and renamed into place |
| `bash omafetti-ctl.sh bind`/`unbind` | On **Apply** — rewrite Omafetti's marked hotkey block |
| `bash omafetti-ctl.sh bar on`/`off` | On **Apply** — show or hide the bar icon |
| `hyprctl reload` | Run by the helper after a hotkey change, so the new hotkey takes effect immediately |
| `python3` | Run by the helper to edit `shell.json` as JSON rather than with text substitution |

Every one of them exits as soon as it has done its job.

## Handling untrusted input

The settings file is state that could have been restored from a backup, and the
theme palette is a file the plugin does not own, so both are treated as data and
never as code:

- The hotkey is validated against a fixed shape — modifiers, then one key — in
  both the settings card and the helper script, and refused outright if it does
  not match. It is written into `bindings.lua` as Lua source, so refusing is the
  only safe answer to anything unexpected; escaping would be answering the wrong
  question.
- Every text field on screen renders as plain text rather than rich text, so a
  stored value cannot cause the shell to load a resource.
- Both files stop at a size ceiling as they are read, not after. They are read
  through a short `python3` helper that opens with `O_NOFOLLOW` and
  `O_NONBLOCK`, confirms the descriptor is a regular file, and reads at most the
  ceiling plus the one byte that identifies an over-sized file. A symlink is
  refused, a FIFO cannot park the read, and anything past the ceiling is
  refused — leaving the last good values in place. This runs inside a shell
  process that lives for days.
- Nothing watches either file. Both are read on load, the settings file again
  when the settings card is opened, and the palette again whenever the shell's
  own live theme colours change. That reader above is therefore the only thing
  that ever opens either path, and it is the only place a ceiling is needed. An
  edit made behind Omafetti's back is picked up the next time the settings card
  is opened rather than the instant it lands.
- `bindings.lua` and `shell.json` belong to you, not to Omafetti. Each is
  resolved through any symlink first, because dotfile managers such as stow and
  chezmoi legitimately link these into a repository, and is edited only once the
  resolved file and its directory are confirmed to be yours and writable by
  nobody else. The replacement is staged in that same directory under an
  unpredictable name created exclusively (`mktemp`/`mkstemp`, which never follow
  a symlink) and renamed over the target in one atomic step — so a managed
  symlink keeps pointing where it pointed, the repository copy is the one that
  changes, and a symlink planted at a staging name cannot redirect the write.
- The hotkey block is rewritten only when its two markers form exactly one
  properly ordered pair. If the block has been half-removed — by hand, or by a
  merge in a dotfiles repository — the file is left exactly as it stands and the
  reason is printed, rather than being rewritten from an opening marker that has
  no end.

## Dependencies

`bash`, `python3` and `hyprctl`, all of which Omarchy already installs. Nothing
else.

## Licence

MIT — see [LICENSE](LICENSE).

## Credits

Built with [Claude Code](https://claude.com/claude-code).
