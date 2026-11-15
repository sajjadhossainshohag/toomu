#!/usr/bin/env python3
"""Shrinks youtubedl-android's bundled archives in a merged native-libs dir.

youtubedl-android ships Python, FFmpeg and aria2c as zip archives disguised as
`lib/<abi>/lib<name>.zip.so`, unpacked on the phone at first start. They are
general-purpose builds: Python carries a static QuickJS library (compile-time
only), test modules, a terminal UI stack and crypto/sqlite modules yt-dlp
treats as optional; FFmpeg and aria2c carry libraries nothing loads.

This removes:
  1. Python files on an explicit list of things yt-dlp never imports (or
     imports inside `try/except ImportError`), and
  2. in every archive, native libraries no remaining program or library
     links to — found by reading each ELF file's DT_NEEDED entries, starting
     from the executables the app runs (libpython.so, libffmpeg.so,
     libffprobe.so, libaria2c.so) and everything kept in the archive.
Everything else is copied byte for byte with its original zip metadata
(Unix modes: the library recreates symlinks from them).

Usage: python3 -I trim_ytdlp_bundles.py [--abis=arm64-v8a,...] <merged native libs dir> [...]
Python 3.8+ (macOS's bundled python3 works); standard library only.
"""

import os
import posixpath
import struct
import sys
import zipfile

# Python: never imported by yt-dlp, or optional to it (checked against
# yt-dlp 2026.10 source: sqlite3 and Cryptodome are imported inside
# try/except ImportError; curses, readline, tkinter, lib2to3, idlelib,
# pydoc_data, ensurepip, venv and the test modules not at all).
PYTHON_DROP_DIRS = (
    'usr/include/', 'usr/share/', 'usr/lib/pkgconfig/', 'usr/lib/quickjs/',
    'usr/lib/python3.12/test/', 'usr/lib/python3.12/idlelib/', 'usr/lib/python3.12/tkinter/',
    'usr/lib/python3.12/turtledemo/', 'usr/lib/python3.12/lib2to3/', 'usr/lib/python3.12/pydoc_data/',
    'usr/lib/python3.12/ensurepip/', 'usr/lib/python3.12/venv/', 'usr/lib/python3.12/sqlite3/',
    'usr/lib/python3.12/curses/', 'usr/lib/python3.12/site-packages/Cryptodome/',
)
PYTHON_DROP_MODULE_PREFIXES = (  # lib-dynload extension modules
    '_test', '_xx', 'xxlimited', 'xxsubtype', '_ctypes_test', '_curses', 'readline', '_sqlite3', '_tkinter',
)
DYNLOAD = 'usr/lib/python3.12/lib-dynload/'

def elf_needed(data):
    """DT_NEEDED sonames of an ELF file (bytes); None if not ELF."""
    if data[:4] != b'\x7fELF':
        return None
    is64 = data[4] == 2
    end = '<' if data[5] == 1 else '>'
    if is64:
        shoff, = struct.unpack_from(end + 'Q', data, 0x28)
        shentsize, shnum = struct.unpack_from(end + 'HH', data, 0x3A)
    else:
        shoff, = struct.unpack_from(end + 'I', data, 0x20)
        shentsize, shnum = struct.unpack_from(end + 'HH', data, 0x2E)
    sections = []
    for i in range(shnum):
        base = shoff + i * shentsize
        if is64:
            _, stype, _, _, off, size, link, _, _, entsize = struct.unpack_from(end + 'IIQQQQIIQQ', data, base)
        else:
            _, stype, _, _, off, size, link, _, _, entsize = struct.unpack_from(end + 'IIIIIIIIII', data, base)
        sections.append((stype, off, size, link, entsize))
    names = []
    for stype, off, size, link, entsize in sections:
        if stype != 6:  # SHT_DYNAMIC
            continue
        stroff = sections[link][1]
        step = entsize or (16 if is64 else 8)
        for pos in range(off, off + size, step):
            tag, val = struct.unpack_from(end + ('qQ' if is64 else 'iI'), data, pos)
            if tag == 0:
                break
            if tag == 1:  # DT_NEEDED
                stop = data.index(b'\0', stroff + val)
                names.append(data[stroff + val:stop].decode())
    return names


def is_link(info):
    return (info.external_attr >> 16) & 0o170000 == 0o120000


# The programs the app runs (next to the archives in lib/<abi>), and the
# archives in the order of the LD_LIBRARY_PATH youtubedl-android sets for
# them: one search path for all three, so FFmpeg may use a library from
# the Python archive (it does: libc++_shared, libcrypto, libexpat).
PROGRAMS = ('libpython.so', 'libffmpeg.so', 'libffprobe.so', 'libaria2c.so', 'libqjs.so')
ARCHIVES = ('libpython.zip.so', 'libffmpeg.zip.so', 'libaria2c.zip.so')


def resolve(links, f):
    for _ in range(10):
        if f not in links:
            return f
        f = posixpath.normpath(posixpath.join(posixpath.dirname(f), links[f]))
    return f


def trim_dir(lib_dir):
    """Trims the archives in one lib/<abi> dir together. Returns lines."""
    present = [a for a in ARCHIVES if os.path.exists(os.path.join(lib_dir, a))]
    if not present:
        return []
    files = {}  # (archive, path) -> bytes
    infos = {}  # archive -> [ZipInfo]
    links = {}  # archive -> {path: target}
    for a in present:
        with zipfile.ZipFile(os.path.join(lib_dir, a)) as z:
            infos[a] = z.infolist()
            links[a] = {}
            for i in infos[a]:
                if i.is_dir():
                    continue
                files[(a, i.filename)] = z.read(i.filename)
                if is_link(i):
                    links[a][i.filename] = files[(a, i.filename)].decode()

    drop = set()
    if 'libpython.zip.so' in present:
        for (a, f) in files:
            module = posixpath.basename(f)
            if a == 'libpython.zip.so' and (f.startswith(PYTHON_DROP_DIRS) or f.endswith('.a') or (
                    f.startswith(DYNLOAD) and module.startswith(PYTHON_DROP_MODULE_PREFIXES))):
                drop.add((a, f))

    def on_search_path(f):  # directly in usr/lib: found by name via LD_LIBRARY_PATH
        return posixpath.dirname(f) == 'usr/lib'

    by_name = {}
    for (a, f) in files:
        if (a, f) not in drop and on_search_path(f):
            by_name.setdefault(posixpath.basename(f), []).append((a, f))

    def real(key):
        a, f = key
        return (a, resolve(links[a], f))

    # Roots: the programs, plus every kept ELF file that isn't a library on
    # the search path (Python modules, OpenSSL providers/engines and other
    # plugins loaded by path) — those are kept as they are.
    pending = [open(os.path.join(lib_dir, p), 'rb').read() for p in PROGRAMS if os.path.exists(os.path.join(lib_dir, p))]
    for key, d in files.items():
        a, f = key
        if key not in drop and f not in links[a] and not on_search_path(f):
            pending.append(d)
    keep = set()
    while pending:
        for so in elf_needed(pending.pop()) or ():
            for key in by_name.get(so, ()):
                for k in (key, real(key)):
                    if k not in keep:
                        keep.add(k)
                        if k in files and k[1] not in links[k[0]]:
                            pending.append(files[k])
    for key, d in files.items():
        a, f = key
        if key in drop or key in keep or f in links[a] or not on_search_path(f):
            continue
        if elf_needed(d) is not None:
            drop.add(key)  # a library nothing loads
    for a in present:
        for f in links[a]:
            if real((a, f)) in drop:
                drop.add((a, f))

    lines = []
    for a in present:
        gone = {f for (b, f) in drop if b == a}
        if not gone:
            continue
        # Folders left empty go too: Python imports an empty folder as a
        # "namespace package", so `import sqlite3` would succeed and yt-dlp
        # (which expects ImportError) would crash on the empty module.
        kept = [f for (b, f) in files if b == a and f not in gone]
        for info in infos[a]:
            if info.is_dir() and not any(k.startswith(info.filename) for k in kept):
                gone.add(info.filename)
        path = os.path.join(lib_dir, a)
        before = os.path.getsize(path)
        tmp = path + '.trim'
        with zipfile.ZipFile(path) as src, zipfile.ZipFile(tmp, 'w') as out:
            for info in src.infolist():
                if info.filename not in gone:
                    # Same ZipInfo (Unix mode, compression): same entry.
                    out.writestr(info, b'' if info.is_dir() else src.read(info.filename))
        os.replace(tmp, path)
        saved = before - os.path.getsize(path)
        lines.append((os.path.basename(lib_dir), a, len(gone), saved))
    return lines


def main(args):
    abis = None
    if args and args[0].startswith('--abis='):
        abis = set(args[0][len('--abis='):].split(','))
        args = args[1:]
    total = 0
    for root in args:
        for dirpath, _, names in os.walk(root):
            if not any(a in names for a in ARCHIVES):
                continue
            if abis is not None and os.path.basename(dirpath) not in abis:
                continue
            for abi, a, count, saved in trim_dir(dirpath):
                total += saved
                print(f'trim_ytdlp_bundles: {abi}/{a}: removed {count} files, {saved / 1048576:.1f} MB smaller')
    print(f'trim_ytdlp_bundles: {total / 1048576:.1f} MB saved in total')


if __name__ == '__main__':
    main(sys.argv[1:])
