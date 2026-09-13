#!/usr/bin/env python3
# Omafetti's consent edits. Runs only when the user applies a choice in
# Omafetti's settings — never on its own.
#
#   bind "SUPER + P"      write the hotkey as a marked block in
#                         ~/.config/hypr/bindings.lua
#   unbind                remove that block
#   bar on|off [section]  move Omafetti's own entry between the bar
#                         layout and the plugins list in
#                         ~/.config/omarchy/shell.json
#
# Both files belong to the user, so every edit here is bound to descriptors
# rather than to pathnames. A pathname is a question asked again at every use,
# and the answer can change between the asking: the previous version of this
# code verified the target and its parent by name and then read, staged and
# renamed by name, so swapping an ancestor in between sent the write somewhere
# the checks had never seen. The parent directory is opened once, every
# component with O_NOFOLLOW, and the read, the staging and the rename all run
# relative to that held descriptor, which is revalidated before the rename.

import errno
import json
import os
import re
import secrets
import stat
import sys

ID = "io.github.weedwhitesandwine.omafetti"
MARK_KEY_IN = ">>> omafetti hotkey"
MARK_KEY_OUT = "<<< omafetti hotkey"
MARK_IN = "-- " + MARK_KEY_IN + " (managed by Omafetti settings — change it there)"
MARK_OUT = "-- " + MARK_KEY_OUT
BIND_LINE = 'o.bind("%s", "Omafetti (throw confetti)", "omarchy-shell shell summon ' + ID + '")'

BIND_FILE = os.path.expanduser("~/.config/hypr/bindings.lua")
SHELL_FILE = os.path.expanduser("~/.config/omarchy/shell.json")

# bindings.lua is a handful of lines and shell.json a small object. Anything
# far larger is not that file, and it is about to be read into memory and
# copied — so the ceiling sits at the read, with the one extra byte that
# identifies an over-sized file.
MAX_BIND_FILE = 1024 * 1024
MAX_SHELL_JSON = 4 * 1024 * 1024

# The hotkey becomes Lua source inside bindings.lua, so its shape is checked
# here as well as in the settings view — the settings file can be edited
# without going near the UI. Literal spaces, not \s, which also accepts a
# newline and would close the Lua string early. Refused, never escaped.
KEY_SHAPE = re.compile(
    r"^(SUPER|CTRL|ALT|SHIFT)( \+ (SUPER|CTRL|ALT|SHIFT))* \+ "
    r"([A-Z0-9]|F([1-9]|1[0-2])|SPACE|RETURN|ENTER|TAB|ESCAPE|BACKSPACE|"
    r"DELETE|INSERT|HOME|END|PAGE_UP|PAGE_DOWN|UP|DOWN|LEFT|RIGHT|COMMA|"
    r"PERIOD|SLASH|MINUS|EQUAL|SEMICOLON|APOSTROPHE|GRAVE|BRACKETLEFT|"
    r"BRACKETRIGHT|BACKSLASH)$"
)


def fail(msg):
    sys.stderr.write("omafetti-ctl.sh: %s\n" % msg)
    raise SystemExit(1)


class Target:
    """A config file held open by descriptor rather than by name.

    The path is resolved once — a dotfiles manager legitimately symlinks these
    files, and refusing every symlink would lock those users out while renaming
    over the link would orphan their repo copy. From then on the resolved name
    is never used again: the parent is walked component by component with
    O_NOFOLLOW, and the file is opened, staged and renamed through that
    descriptor.
    """

    def __init__(self, path, dfd, dir_path):
        self.display = path
        self.dir_path = dir_path
        self.base = os.path.basename(os.path.realpath(path))
        self.dfd = dfd
        self.dir_st = os.fstat(self.dfd)
        if self.dir_st.st_uid != os.getuid() or (self.dir_st.st_mode & 0o022):
            self.close()
            fail(
                "refusing to edit %s — its directory is not yours alone, or is "
                "writable by others" % dir_path
            )

    @classmethod
    def open(cls, path):
        """Return a Target for `path`, or None if it is not there at all.

        The directory is walked one component at a time, each opened relative
        to the previous descriptor. O_DIRECTORY is what does the refusing:
        O_NOFOLLOW alone, combined with O_PATH, returns a descriptor to the
        symlink itself rather than an error, so the two must be used together.
        O_PATH rather than O_RDONLY because traversal needs search permission
        and nothing more — an ancestor that is searchable but not readable
        (a 0711 /home, as some encrypted-home layouts use) would otherwise
        fail with EACCES.

        Holding the result is what makes the later read and rename immune to
        an ancestor swap: they do not consult the path again.
        """
        resolved = os.path.realpath(path)
        base = os.path.basename(resolved)
        if not base or base in (os.curdir, os.pardir):
            fail("refusing to edit %s — it does not name a file" % path)
        directory = os.path.dirname(resolved)
        parts = [p for p in directory.split(os.sep) if p]
        dfd = os.open(os.sep, os.O_PATH | os.O_DIRECTORY)
        try:
            for comp in parts:
                nfd = os.open(
                    comp,
                    os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW,
                    dir_fd=dfd,
                )
                os.close(dfd)
                dfd = nfd
        except OSError as e:
            os.close(dfd)
            if e.errno == errno.ENOENT:
                return None  # nothing of ours can be in a directory that is not there
            if e.errno in (errno.ENOTDIR, errno.ELOOP):
                fail(
                    "refusing to edit %s — a directory above it is a symlink, "
                    "or stopped being a directory while it was being checked"
                    % resolved
                )
            fail("refusing to edit %s — %s" % (resolved, e))
        return cls(path, dfd, directory)

    def close(self):
        if getattr(self, "dfd", None) is not None:
            os.close(self.dfd)
            self.dfd = None

    def _assert_dir_unchanged(self):
        """Check that the path still leads to the directory being held.

        Comparing the held descriptor against itself would prove nothing — an
        open descriptor refers to one inode for its whole life, so that
        comparison can never fail. The question worth asking is whether the
        *name* still resolves to it: if it does not, the file the user asked to
        edit is no longer the file about to be written, and the honest answer
        is to stop rather than to write a correct edit into a directory they
        can no longer reach.
        """
        try:
            now = os.stat(self.dir_path)
        except OSError as e:
            fail("refusing to edit %s — its directory is no longer reachable: %s"
                 % (self.display, e))
        if (now.st_dev, now.st_ino) != (self.dir_st.st_dev, self.dir_st.st_ino):
            fail("refusing to edit %s — its directory was swapped while it was "
                 "being edited" % self.display)

    def read(self, ceiling, missing_ok=False):
        """Read the file through the held directory descriptor.

        O_NOFOLLOW refuses a symlink planted at the name, O_NONBLOCK means a
        planted FIFO returns rather than parking the process forever, and the
        regular-file check is made on the descriptor that was actually opened.
        """
        try:
            fd = os.open(
                self.base,
                os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                dir_fd=self.dfd,
            )
        except OSError as e:
            if missing_ok and e.errno == errno.ENOENT:
                return None, None
            if e.errno in (errno.ELOOP, errno.EMLINK):
                fail("refusing to read %s — it is a symlink" % self.display)
            fail("cannot read %s: %s" % (self.display, e))
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                fail("refusing to read %s — not a regular file" % self.display)
            if st.st_uid != os.getuid():
                fail("refusing to read %s — it is not yours" % self.display)
            data = b""
            while len(data) <= ceiling:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                data += chunk
        finally:
            os.close(fd)
        if len(data) > ceiling:
            fail("refusing to edit %s — larger than %d bytes"
                 % (self.display, ceiling))
        self.file_st = st
        return data, st

    def write(self, data):
        """Stage under an unguessable name and rename, all through the held
        descriptor, revalidating immediately before the rename."""
        self._assert_dir_unchanged()
        mode = getattr(self, "file_st", None)
        mode = (mode.st_mode & 0o777) if mode else 0o644
        tmp = ".%s.%s.tmp" % (self.base, secrets.token_hex(8))
        fd = os.open(
            tmp,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=self.dfd,
        )
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
                os.fchmod(f.fileno(), mode)
            self._assert_target_unchanged()
            self._assert_dir_unchanged()
            os.replace(tmp, self.base, src_dir_fd=self.dfd, dst_dir_fd=self.dfd)
        except BaseException:
            try:
                os.unlink(tmp, dir_fd=self.dfd)
            except OSError:
                pass
            raise

    def _assert_target_unchanged(self):
        """The file about to be replaced must be the file that was read."""
        want = getattr(self, "file_st", None)
        if want is None:
            return
        try:
            fd = os.open(self.base, os.O_RDONLY | os.O_NOFOLLOW,
                         dir_fd=self.dfd)
        except OSError:
            fail("refusing to replace %s — it is no longer the file that was "
                 "read" % self.display)
        try:
            now = os.fstat(fd)
        finally:
            os.close(fd)
        if (now.st_dev, now.st_ino) != (want.st_dev, want.st_ino):
            fail("refusing to replace %s — it was replaced while being edited"
                 % self.display)


# --------------------------------------------------------------------------
# bindings.lua
# --------------------------------------------------------------------------

def check_markers(lines):
    """A block is only safe to rewrite when its markers are a matched, ordered
    pair. An opener with no closer would otherwise swallow every line after it,
    which on a real bindings.lua means losing the user's other hotkeys."""
    opens = [i for i, l in enumerate(lines) if MARK_KEY_IN in l]
    closes = [i for i, l in enumerate(lines) if MARK_KEY_OUT in l]
    if not opens and not closes:
        return
    if len(opens) != 1 or len(closes) != 1:
        fail(
            "refusing to edit %s — expected one marked block, found %d opening "
            "and %d closing markers. Repair or remove the block by hand."
            % (BIND_FILE, len(opens), len(closes))
        )
    if opens[0] >= closes[0]:
        fail("refusing to edit %s — the closing marker is above the opening "
             "marker." % BIND_FILE)


def strip_block(lines):
    """Return the file without our marked block, and without the one blank
    line we wrote above it. That blank is ours, so it comes out with the block;
    blank lines the user has of their own are kept."""
    out = []
    pending = 0
    skip = False
    for line in lines:
        if MARK_KEY_IN in line:
            if pending:
                pending -= 1
            out.extend([""] * pending)
            pending = 0
            skip = True
            continue
        if MARK_KEY_OUT in line:
            skip = False
            continue
        if skip:
            continue
        if line == "":
            pending += 1
            continue
        out.extend([""] * pending)
        pending = 0
        out.append(line)
    out.extend([""] * pending)
    return out


def edit_bindings(key):
    # Clearing a hotkey that was never set, in a home with no hypr config at
    # all, is not an error — there is simply nothing of ours to take out.
    t = Target.open(BIND_FILE)
    if t is None:
        if key is None:
            return
        fail("cannot edit %s — its directory does not exist" % BIND_FILE)
    try:
        raw, _ = t.read(MAX_BIND_FILE, missing_ok=True)
        if raw is None:
            if key is None:
                return
            fail("cannot read %s: it does not exist" % BIND_FILE)
        # surrogateescape, not replace: bindings.lua is the user's file and
        # only our own marked block is ours to change. Decoding with "replace"
        # turns any byte that is not valid UTF-8 into U+FFFD and writes that
        # back, quietly corrupting a line the plugin never meant to touch and
        # breaking the promise that everything outside the markers is copied
        # through untouched. surrogateescape round-trips those bytes exactly.
        text = raw.decode("utf-8", "surrogateescape")
        trailing_nl = text.endswith("\n")
        lines = text.split("\n")
        if trailing_nl:
            lines.pop()
        check_markers(lines)
        out = strip_block(lines)
        if key is not None:
            out.append("")
            out.append(MARK_IN)
            out.append(BIND_LINE % key)
            out.append(MARK_OUT)
        body = "\n".join(out)
        if body or trailing_nl:
            body += "\n"
        t.write(body.encode("utf-8", "surrogateescape"))
    finally:
        t.close()


# --------------------------------------------------------------------------
# shell.json
# --------------------------------------------------------------------------

def edit_bar(state, section):
    t = Target.open(SHELL_FILE)
    if t is None:
        return  # no omarchy config directory: nothing to move the entry within
    try:
        raw, _ = t.read(MAX_SHELL_JSON, missing_ok=True)
        if raw is None:
            return  # no shell.json yet: nothing to move the entry within
        # Strict, not "replace": JSON is UTF-8 by definition, and substituting
        # U+FFFD for a bad byte can turn a broken file into a valid-looking one
        # that is then written back over the user's config.
        try:
            cfg = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as e:
            fail("refusing to edit %s — not valid JSON: %s" % (SHELL_FILE, e))
        if not isinstance(cfg, dict):
            fail("refusing to edit %s — top level is not an object" % SHELL_FILE)

        def is_ours(w):
            return (w.get("id") if isinstance(w, dict) else w) == ID

        # The existing entry is carried across rather than rebuilt, so any
        # settings the user put on it survive the move.
        entry = None
        bar = cfg.get("bar")
        layout = bar.get("layout") if isinstance(bar, dict) else None
        if isinstance(layout, dict):
            for name in ("left", "center", "right"):
                sect = layout.get(name)
                if not isinstance(sect, list):
                    continue
                for w in sect:
                    if is_ours(w):
                        entry = w if isinstance(w, dict) else {"id": ID}
                layout[name] = [w for w in sect if not is_ours(w)]
        if isinstance(cfg.get("plugins"), list):
            for w in cfg["plugins"]:
                if is_ours(w):
                    entry = w if isinstance(w, dict) else {"id": ID}
            cfg["plugins"] = [w for w in cfg["plugins"] if not is_ours(w)]
        if entry is None:
            entry = {"id": ID}

        # Nothing is created that this entry does not need.
        if state == "on":
            if not isinstance(cfg.get("bar"), dict):
                cfg["bar"] = {}
            if not isinstance(cfg["bar"].get("layout"), dict):
                cfg["bar"]["layout"] = {}
            if not isinstance(cfg["bar"]["layout"].get(section), list):
                cfg["bar"]["layout"][section] = []
            cfg["bar"]["layout"][section].append(entry)
        else:
            if not isinstance(cfg.get("plugins"), list):
                cfg["plugins"] = []
            cfg["plugins"].append(entry)

        t.write((json.dumps(cfg, indent=2) + "\n").encode("utf-8"))
    finally:
        t.close()


def main(argv):
    if not argv:
        fail("usage: bind <keys> | unbind | bar on|off [section]")
    cmd = argv[0]
    if cmd == "bind":
        if len(argv) < 2 or not argv[1]:
            fail("usage: bind <keys>")
        key = argv[1]
        if len(key) > 40 or not KEY_SHAPE.match(key):
            fail("refusing hotkey that is not modifiers plus one key: %s" % key)
        edit_bindings(key)
    elif cmd == "unbind":
        edit_bindings(None)
    elif cmd == "bar":
        if len(argv) < 2 or argv[1] not in ("on", "off"):
            fail("usage: bar on|off [section]")
        section = argv[2] if len(argv) > 2 else "right"
        if section not in ("left", "center", "right"):
            section = "right"
        edit_bar(argv[1], section)
    else:
        fail("usage: bind <keys> | unbind | bar on|off [section]")


if __name__ == "__main__":
    main(sys.argv[1:])
