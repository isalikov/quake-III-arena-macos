# Quake III Arena for macOS

Install the full Quake III Arena game on modern macOS, including **M3 Pro** and
other Apple Silicon Macs. The installer builds ioquake3 as a universal
**arm64 + x86_64** application: it runs natively on Apple Silicon, without Rosetta.

## Installation

Requires macOS 11 or later, Xcode Command Line Tools, CMake, an internet connection,
and about 2 GB of free disk space. Homebrew is only needed if you use it to install
CMake. These tools must already be installed before running the installer.

Run this single command in Terminal as your normal user, without `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/isalikov/quake-III-arena-macos/master/install.sh | bash
```

The game is installed in `~/Applications/ioquake3`. Launch it with:

```bash
open "$HOME/Applications/ioquake3/ioquake3.app"
```

## Game files

The installer automatically obtains **all nine `baseq3/pak0.pk3`–`pak8.pk3` files**:
maps, textures, models, sounds, music, bots, and game QVMs.

- `pak0.pk3` comes from the [nrempel/q3-server mirror](https://github.com/nrempel/q3-server/tree/master/baseq3)
  over HTTPS. The installer checks an existing game installation and the standard
  Steam folder first.
- `pak1.pk3`–`pak8.pk3` come from the [official ioquake3 patches](https://ioquake3.org/extras/patch-data/).
  The same archive supplies `missionpack/pak1.pk3`–`pak3.pk3`.
  Playing Team Arena also requires its own `missionpack/pak0.pk3`.

The game data belongs to the commercial Quake III Arena release; you must own a
copy of the game. Patch terms are published on the ioquake3 download page.
The mirror is not an official id Software server.

Downloads are verified using SHA-256, and each baseq3 PK3 is checked as a ZIP
archive. HTTP errors and corrupt files stop installation before the existing game
is updated. Verified downloads are cached; rerunning the installer preserves
configuration files and additional mods. User settings are stored in
`~/Library/Application Support/Quake3`.

## Options

Set environment variables on `bash` to customize the one-command installation:

```bash
# Use a different installation directory (must be writable):
curl -fsSL https://raw.githubusercontent.com/isalikov/quake-III-arena-macos/master/install.sh | Q3_INSTALL_DIR="$HOME/Games/Quake3" bash

# Use your own pak0.pk3 instead of downloading it:
curl -fsSL https://raw.githubusercontent.com/isalikov/quake-III-arena-macos/master/install.sh | Q3_PAK0="/path/to/baseq3/pak0.pk3" bash

# Use another HTTPS mirror of the same retail pak0.pk3:
curl -fsSL https://raw.githubusercontent.com/isalikov/quake-III-arena-macos/master/install.sh | Q3_PAK0_URL="https://your-mirror.example/baseq3/pak0.pk3" bash
```

Other available variables are `Q3_CACHE_DIR`, `Q3_PATCH_URL` (a mirror of the
original `quake3-latest-pk3s.zip`), and `Q3_JOBS` (the number of parallel build
jobs). Checksum verification remains mandatory when using a different mirror.

The engine is pinned to commit
[`83a7762`](https://github.com/ioquake/ioq3/commit/83a776283bdb958f82db25554b5ed0966aaf6e49)
for reproducible builds. SDL2 and both OpenGL renderers are bundled with the app.
The installer verifies native architecture support and applies a local ad hoc
signature with the QVM JIT entitlement.

If macOS blocks launch, choose “Open” from the app's context menu or allow it in
“System Settings → Privacy & Security”. If a network error occurs, rerun the
installation command: verified cached downloads will be reused. For help, run:

```bash
curl -fsSL https://raw.githubusercontent.com/isalikov/quake-III-arena-macos/master/install.sh | bash -s -- --help
```

## Installer verification

From a local checkout of this repository, run:

```bash
bash -n install.sh
python3 tests/test_installer.py
```

Integration tests run without network access or a compiler in isolated temporary
directories. They check the complete PK3 set, reinstallation from cache,
configuration preservation, HTTP and SHA-256 errors, incorrect architecture,
app rollback after a copy failure, and use of a local pak0.

Verified on an Apple M3 Pro running macOS 27.0.1: a complete run of the updated
installer, loading the `q3dm1` map through OpenGL 4.1 (`GL_RENDERER: Apple M3 Pro`),
reading 4,073 files from nine PK3 archives, and a clean game exit with code 0.
