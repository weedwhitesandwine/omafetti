#!/bin/bash
# Omafetti settings helper. Runs ONLY when the user applies a choice in
# Omafetti's settings card — never on its own.
#
#   omafetti-ctl.sh bind "SUPER + SHIFT + C"   manage Omafetti's hotkey as a
#                                              marked block in
#                                              ~/.config/hypr/bindings.lua
#                                              (replaces only its own block,
#                                              never other lines)
#   omafetti-ctl.sh unbind                     remove that block
#   omafetti-ctl.sh bar on|off [section]       add/remove the Omafetti icon in
#                                              the bar layout
#                                              (~/.config/omarchy/shell.json)
set -e

ID="io.github.weedwhitesandwine.omafetti"
BIND_FILE="$HOME/.config/hypr/bindings.lua"
MARK_IN="-- >>> omafetti hotkey (managed by Omafetti settings — change it there)"
MARK_OUT="-- <<< omafetti hotkey"
MARK_IN_KEY=">>> omafetti hotkey"
MARK_OUT_KEY="<<< omafetti hotkey"

# bindings.lua is a handful of lines. A file far larger than this is not one,
# and it is about to be read into a pipeline and copied — so the size is
# checked before anything is read.
MAX_BIND_FILE=$((1024 * 1024))

# A user config may legitimately be a symlink into a dotfiles repo — stow and
# chezmoi both work that way. Refusing every symlink locks those users out;
# renaming over the link replaces their managed link with a plain file and
# orphans the repo copy, so their edits silently stop reaching Hyprland.
# Resolve it instead, and write to the target once the target and its
# directory are confirmed to be ours and writable by nobody else.
resolve_config() {
  local p="$1" real dir
  real=$(realpath -e -- "$p" 2>/dev/null) || return 1
  [[ -f $real ]] || return 1
  [[ -O $real ]] || return 1
  dir=$(dirname -- "$real")
  [[ -d $dir && -O $dir ]] || return 1
  [[ -z $(find "$dir" -maxdepth 0 -perm /022 2>/dev/null) ]] || return 1
  printf '%s' "$real"
}

# awk's skip state clears on the closing marker, so an opening marker with no
# closer runs to end of file and takes every line after it. A block that is
# not exactly one properly ordered pair means the file has been edited by
# something else, and the only safe answer is to leave it alone and say so.
assert_balanced() {
  local f="$1" opens closes o c
  opens=$(grep -c -F -- "$MARK_IN_KEY" "$f" 2>/dev/null || true)
  closes=$(grep -c -F -- "$MARK_OUT_KEY" "$f" 2>/dev/null || true)
  opens=${opens:-0}
  closes=${closes:-0}
  [[ $opens -eq 0 && $closes -eq 0 ]] && return 0
  if [[ $opens -ne 1 || $closes -ne 1 ]]; then
    echo "omafetti-ctl: refusing to edit $f — expected one marked block, found $opens opening and $closes closing markers. Repair or remove the block by hand." >&2
    return 1
  fi
  o=$(grep -n -F -- "$MARK_IN_KEY" "$f" | head -1 | cut -d: -f1)
  c=$(grep -n -F -- "$MARK_OUT_KEY" "$f" | head -1 | cut -d: -f1)
  if [[ $o -ge $c ]]; then
    echo "omafetti-ctl: refusing to edit $f — the closing marker is above the opening marker." >&2
    return 1
  fi
  return 0
}

check_size() {
  local f="$1" sz
  sz=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
  if [[ $sz -gt $MAX_BIND_FILE ]]; then
    echo "omafetti-ctl: refusing to edit $f — $sz bytes is not a bindings file." >&2
    return 1
  fi
  return 0
}

strip_block() {
  # print bindings.lua without Omafetti's marked block, and without the blank
  # line written above it. That blank is ours, so it comes out with the block:
  # stripping only the marked lines left one behind on every re-bind, and
  # three hotkey changes meant three orphan blank lines in a file this plugin
  # promises to leave otherwise untouched. Blank lines the user has of their
  # own are held and re-emitted; exactly one, immediately above the opening
  # marker, is dropped.
  awk '
    function flush(  i) { for (i = 0; i < pending; i++) print ""; pending = 0 }
    index($0, ">>> omafetti hotkey") { if (pending > 0) pending--; flush(); skip = 1; next }
    index($0, "<<< omafetti hotkey") { skip = 0; next }
    skip { next }
    $0 == "" { pending++; next }
    { flush(); print }
    END { flush() }
  ' "$1"
}

# Stage beside the resolved target and rename over it, so the swap is a single
# atomic step and a managed symlink keeps pointing where it pointed. mktemp
# creates the stage file exclusively under a random name, so nothing can have
# been planted at it, and staging in the target's own directory keeps the
# rename on one filesystem — mktemp in /tmp plus mv degrades to a copy, which
# can leave a half-written config if interrupted.
replace_config() {
  local real="$1" tmp
  tmp=$(mktemp "$real.XXXXXXXX")
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp"
  chmod --reference="$real" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  mv -f "$tmp" "$real"
  trap - EXIT
}

# This value ends up inside a Lua string in bindings.lua, so it is checked here
# as well as in the settings card. A hotkey is modifiers plus one key and
# nothing else; anything that does not match that shape is refused rather than
# escaped, because there is no reason for it to exist. The separator is a
# literal space, exactly as in the settings card — [[:space:]] would also
# accept a newline, which would close the Lua string early.
HOTKEY_RE='^(SUPER|CTRL|ALT|SHIFT)( \+ (SUPER|CTRL|ALT|SHIFT))* \+ ([A-Z0-9]|F([1-9]|1[0-2])|SPACE|RETURN|ENTER|TAB|ESCAPE|BACKSPACE|DELETE|INSERT|HOME|END|PAGE_UP|PAGE_DOWN|UP|DOWN|LEFT|RIGHT|COMMA|PERIOD|SLASH|MINUS|EQUAL|SEMICOLON|APOSTROPHE|GRAVE|BRACKETLEFT|BRACKETRIGHT|BACKSLASH)$'

case "$1" in
  bind)
    key="$2"
    [[ -n $key ]] || exit 1
    if [[ ${#key} -gt 40 ]] || ! [[ $key =~ $HOTKEY_RE ]]; then
      echo "omafetti-ctl: refusing hotkey that is not modifiers plus one key: $key" >&2
      exit 1
    fi
    real=$(resolve_config "$BIND_FILE") || {
      echo "omafetti-ctl: refusing to edit $BIND_FILE — not a regular file we own in a directory only we can write." >&2
      exit 1
    }
    check_size "$real"
    assert_balanced "$real"
    {
      strip_block "$real"
      echo ""
      echo "$MARK_IN"
      printf 'o.bind("%s", "Omafetti (throw confetti)", "omarchy-shell shell summon %s")\n' "$key" "$ID"
      echo "$MARK_OUT"
    } | replace_config "$real"
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  unbind)
    real=$(resolve_config "$BIND_FILE") || exit 0
    check_size "$real"
    assert_balanced "$real"
    strip_block "$real" | replace_config "$real"
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  bar)
    # bar on [left|center|right] | bar off
    # The icon is visible when Omafetti's entry lives in the bar layout of
    # shell.json; hidden (but the plugin still enabled) when the entry lives
    # in the plugins list instead. The shell hot-reloads the file.
    python3 - "$2" "${3:-right}" <<'PY'
import json, os, stat, sys, tempfile
state = sys.argv[1]
sec = sys.argv[2] if sys.argv[2] in ("left", "center", "right") else "right"
ID = "io.github.weedwhitesandwine.omafetti"
p = os.path.expanduser("~/.config/omarchy/shell.json")

# shell.json belongs to the user, not to this plugin, and it is read back
# before it is rewritten — so it gets a ceiling at the read, plus the one byte
# that identifies an over-sized file. Refusing leaves the file exactly as it
# stands, which is the right answer for one this script cannot make sense of.
MAX_SHELL_JSON = 4 * 1024 * 1024


def fail(msg):
    sys.stderr.write("omafetti-ctl: %s\n" % msg)
    sys.exit(1)


# The same reasoning as bindings.lua: a dotfiles-managed symlink must keep
# working and must survive the write, so the link is resolved and the target
# verified rather than refused outright or replaced.
try:
    real = os.path.realpath(p)
    d = os.path.dirname(real)
    st = os.stat(d)
    if st.st_uid != os.getuid() or (st.st_mode & 0o022):
        fail("refusing to edit %s — its directory is not owned by us alone" % real)
    tst = os.stat(real)
    if not stat.S_ISREG(tst.st_mode) or tst.st_uid != os.getuid():
        fail("refusing to edit %s — not a regular file we own" % real)
except OSError:
    sys.exit(0)  # no shell.json yet: nothing to move the entry within

# The open still refuses a link and a non-regular file, so nothing swapped in
# between the check above and the read below can redirect it or block it.
try:
    fd = os.open(real, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except OSError as e:
    fail("cannot read %s: %s" % (real, e))
try:
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        fail("refusing to read %s — not a regular file" % real)
    with os.fdopen(fd, "rb") as f:
        fd = None
        raw = f.read(MAX_SHELL_JSON + 1)
finally:
    if fd is not None:
        os.close(fd)

if len(raw) > MAX_SHELL_JSON:
    fail("refusing to edit %s — larger than %d bytes" % (real, MAX_SHELL_JSON))
try:
    cfg = json.loads(raw.decode("utf-8", "replace"))
except ValueError as e:
    fail("refusing to edit %s — not valid JSON: %s" % (real, e))

# Valid JSON of the wrong shape is not a config file, and setdefault will
# happily hand back a string to be subscripted. Each level is checked, and a
# section of the wrong type is replaced with an empty list rather than skipped
# — skipping it leaves the append below to run against whatever was there.
if not isinstance(cfg, dict):
    fail("refusing to edit %s — top level is not an object" % real)

# Nothing is created that this entry does not need: turning the icon on adds
# the one section it goes into, turning it off adds the plugins list it goes
# into, and no other key is invented on the way past. A section of the wrong
# type is left exactly as it is and the append below makes its own room, so
# nothing is ever appended to whatever happened to be sitting there.
bar = cfg.get("bar")
layout = bar.get("layout") if isinstance(bar, dict) else None
plugins = cfg.get("plugins") if isinstance(cfg.get("plugins"), list) else None


def drop(seq):
    return [e for e in seq if not (isinstance(e, dict) and e.get("id") == ID)]


entry = None
if isinstance(layout, dict):
    for key in ("left", "center", "right"):
        section = layout.get(key)
        if not isinstance(section, list):
            continue
        for e in section:
            if isinstance(e, dict) and e.get("id") == ID:
                entry = e
        layout[key] = drop(section)
if plugins is not None:
    for e in plugins:
        if isinstance(e, dict) and e.get("id") == ID:
            entry = e
    cfg["plugins"] = drop(plugins)

if entry is None:
    entry = {"id": ID}

if state == "on":
    if not isinstance(cfg.get("bar"), dict):
        cfg["bar"] = {}
    if not isinstance(cfg["bar"].get("layout"), dict):
        cfg["bar"]["layout"] = {}
    if not isinstance(cfg["bar"]["layout"].get(sec), list):
        cfg["bar"]["layout"][sec] = []
    cfg["bar"]["layout"][sec].append(entry)
else:
    if not isinstance(cfg.get("plugins"), list):
        cfg["plugins"] = []
    cfg["plugins"].append(entry)

# Staged under an unpredictable name created exclusively by mkstemp — which
# never follows a symlink — in the resolved file's own directory, then renamed
# over the destination in one step. A predictable name here would let a
# pre-planted symlink turn this write into the truncation of whatever the link
# pointed at.
fd, tmp = tempfile.mkstemp(prefix=".shell.json.", suffix=".tmp", dir=d)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    try:
        os.chmod(tmp, tst.st_mode & 0o777)
    except OSError:
        pass
    os.replace(tmp, real)
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
    ;;
  *)
    echo "usage: omafetti-ctl.sh bind <keys> | unbind | bar on|off [section]" >&2
    exit 2
    ;;
esac
