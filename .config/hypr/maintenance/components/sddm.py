#!/usr/bin/env python3
"""SDDM configuration."""

from __future__ import annotations

import getpass
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.append(str(Path(__file__).resolve().parent.parent))
    from components.utils import run_cmd, run_shell
else:
    from .utils import run_cmd, run_shell

THEME_NAME = "archeclipse"
THEME_SOURCE = Path(__file__).resolve().parent.parent.parent / "theme" / "sddm"
THEME_DEST = Path("/usr/share/sddm/themes") / THEME_NAME

# owned by login user
STATE_DIR = Path("/var/lib/archeclipse/sddm")


def configure_sddm() -> None:
    run_shell("figlet 'SDDM' -f slant | lolcat", check=False)

    user = getpass.getuser()

    print("Disabling lightdm and GDM (ignore errors if not installed)...")
    run_cmd(["sudo", "systemctl", "disable", "lightdm.service"], check=False)
    run_cmd(["sudo", "systemctl", "disable", "gdm.service"], check=False)
    print("Done.")

    print("Enabling sddm...")
    run_cmd(["sudo", "systemctl", "enable", "sddm"])
    print("Done.")

    print(f"Installing the {THEME_NAME} theme...")
    if not THEME_SOURCE.is_dir():
        raise SystemExit(f"theme source not found: {THEME_SOURCE}")
    run_cmd(["sudo", "rm", "-rf", str(THEME_DEST)])
    run_cmd(["sudo", "mkdir", "-p", str(THEME_DEST)])
    run_shell(f"sudo cp -r '{THEME_SOURCE}/.' '{THEME_DEST}/'")
    run_cmd(["sudo", "chmod", "-R", "a+rX", str(THEME_DEST)])
    print("Done.")

    print(f"Creating {STATE_DIR}...")
    run_cmd(["sudo", "mkdir", "-p", str(STATE_DIR)])
    run_cmd(["sudo", "chown", "-R", f"{user}:{user}", str(STATE_DIR)])
    # greeter reads as user sddm
    run_cmd(["sudo", "chmod", "755", str(STATE_DIR)])
    print("Done.")

    print("Setting sddm theme...")
    run_cmd(["sudo", "mkdir", "-p", "/etc/sddm.conf.d"])
    run_cmd(
        ["sudo", "tee", "/etc/sddm.conf.d/theme.conf"],
        input_text=f"[Theme]\nCurrent={THEME_NAME}\n",
    )
    print("Done.")

    _seed_background()

    print("Sddm configuration complete.")


def _seed_background() -> None:
    script = Path(__file__).resolve().parent.parent.parent / "theme" / "scripts" / "sddm-theme.sh"
    if not script.is_file():
        print(f"Skipping background seed: {script} not found")
        return

    current = Path.home() / ".config" / "hypr" / "wallpaper-daemon" / "config" / "current.conf"
    wallpaper = ""
    if current.is_file():
        wallpaper = current.read_text().strip().replace("$HOME", str(Path.home()))

    if not wallpaper or not Path(wallpaper).is_file():
        defaults = Path.home() / ".config" / "wallpapers" / "defaults"
        candidates = sorted(p for p in defaults.rglob("*") if p.is_file())
        if not candidates:
            print("Skipping background seed: no wallpaper available")
            return
        wallpaper = str(candidates[0])

    print(f"Seeding the login background from {wallpaper}...")
    result = run_cmd(["bash", str(script), wallpaper], check=False)
    if result.returncode != 0:
        print("Background seed failed; the theme will use its fallback colours.")
    else:
        print("Done.")


def main() -> None:
    configure_sddm()


if __name__ == "__main__":
    main()
