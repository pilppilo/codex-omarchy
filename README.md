# chatgpt (Arch Linux / Omarchy PKGBUILD)

Native Arch Linux package for the official **OpenAI ChatGPT / Codex Desktop** application.

This repository provides a standalone, auditable `PKGBUILD` that repackages OpenAI's official `.deb` release into a standard Arch Linux package (`.pkg.tar.zst`), adhering strictly to **Arch Linux Packaging Standards** and the **XDG Desktop Specification**.

---

## Features

- **Official OpenAI Naming:** Packaged as `chatgpt` (compliant with [ArchWiki Nonfree Applications Guidelines](https://wiki.archlinux.org/title/Nonfree_applications_package_guidelines)).
- **Zero Collisions:** Coexists cleanly with `openai-codex` (the official Arch package for the CLI tool).
- **Sub-Second Update Checking:** `./update.sh check` queries upstream metadata via HTTP byte-range requests in <1 second without downloading the full ~410MB payload.
- **Local Pacman Integration:** Direct installation via `makepkg -si` / `pacman -U` or via an optional local repository (`[chatgpt-local]`) in `/etc/pacman.conf`.
- **Systemd User Timer:** Optional background service to auto-detect updates and notify when a new build is ready.

---

## Package Structure

Following the Arch Linux standard filesystem hierarchy:

| Installed Path | Description |
|---|---|
| `/usr/bin/chatgpt` | Application executable entrypoint |
| `/usr/lib/chatgpt/` | Application bundle and Electron runtime |
| `/usr/share/applications/chatgpt.desktop` | Desktop launcher (XDG standard) |
| `/usr/share/pixmaps/chatgpt.png` | Desktop icon |
| `/usr/share/licenses/chatgpt/LICENSE` | License / copyright file (Arch packaging requirement) |

---

## Installation & Usage

### 1. Build and Install Manually

Ensure you have `base-devel` installed:

```bash
# Clone this repository (matches systemd unit expectations)
git clone https://github.com/flub/codex-pkgbuild.git
cd codex-pkgbuild

# Build and install using standard makepkg
makepkg -si
```

### 2. Using the Helper Script (`update.sh`)

| Command | Action |
|---|---|
| `./update.sh check` | Checks if OpenAI has released a newer version upstream (fast <1s check). |
| `./update.sh bump` | Updates `pkgver` and `sha256sums` in `PKGBUILD` to latest upstream. |
| `./update.sh build` | Bumps `PKGBUILD` and runs `makepkg -f` to generate `.pkg.tar.zst`. |
| `./update.sh install` | Bumps `PKGBUILD`, builds, and runs `makepkg -si` to install. |
| `./update.sh repo` | Adds the built package to a local pacman repository database. |

---

## Optional: Local Pacman Repository Integration

If you want `sudo pacman -Syu` to manage upgrades automatically from your local build folder:

1. Add the local repository to `/etc/pacman.conf`:
   ```ini
   [chatgpt-local]
   SigLevel = Optional TrustAll
   Server = file:///home/flub/codex-pkgbuild/repo
   ```

2. Build and populate the repository:
   ```bash
   ./update.sh repo
   ```

3. Update your system:
   ```bash
   sudo pacman -Syu chatgpt
   ```

---

## Optional: Automatic Background Update Checks

To have systemd check for upstream releases in the background and notify you via desktop notifications:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/chatgpt-updater.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now chatgpt-updater.timer
```

When an update is detected, the timer builds the package into your local repo and sends a desktop notification (`notify-send`).

---

## License

The packaging files in this repository are licensed under the MIT License.  
The packaged ChatGPT software is proprietary and subject to OpenAI's Terms of Use.
