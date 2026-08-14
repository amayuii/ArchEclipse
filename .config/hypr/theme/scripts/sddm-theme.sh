#!/bin/bash


set -euo pipefail

readonly STATE_DIR="${ARCHECLIPSE_SDDM_DIR:-/var/lib/archeclipse/sddm}"
readonly BLUR_SIGMA=24
readonly DIM=42

die() {
    echo "sddm-theme: $*" >&2
    exit 1
}

wallpaper="${1:-}"
[[ -n "${wallpaper}" ]] || die "usage: sddm-theme.sh <wallpaper>"

wallpaper="${wallpaper/\$HOME/${HOME}}"
[[ -f "${wallpaper}" ]] || die "wallpaper not found: ${wallpaper}"
command -v magick >/dev/null || die "imagemagick is required"
[[ -d "${STATE_DIR}" ]] || die "${STATE_DIR} missing -- run maintenance/components/sddm.py"
[[ -w "${STATE_DIR}" ]] || die "${STATE_DIR} not writable by $(id -un) -- re-run maintenance/components/sddm.py"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# greeter cant play video, grab a frame
source_image="${wallpaper}"
if [[ "${wallpaper,,}" =~ \.(mp4|gif|webm|mkv|avi|flv|mpeg)$ ]]; then
    command -v ffmpeg >/dev/null || die "ffmpeg is required for animated wallpapers"
    source_image="${tmp}/frame.jpg"
    ffmpeg -y -loglevel error -ss 1 -i "${wallpaper}" -frames:v 1 -q:v 2 "${source_image}" >/dev/null 2>&1 ||
        ffmpeg -y -loglevel error -i "${wallpaper}" -frames:v 1 -q:v 2 "${source_image}" >/dev/null 2>&1 ||
        die "could not extract a frame from ${wallpaper}"
fi

# palette from the unblurred source
read -r bg fg accent < <(
    magick "${source_image}" -resize 400x400 -colors 16 -unique-colors -depth 8 txt: |
        awk '
        match($0, /#[0-9A-Fa-f]{6}/) {
            hex = substr($0, RSTART, RLENGTH)
            r = strtonum("0x" substr(hex, 2, 2))
            g = strtonum("0x" substr(hex, 4, 2))
            b = strtonum("0x" substr(hex, 6, 2))
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            max = (r > g ? (r > b ? r : b) : (g > b ? g : b))
            min = (r < g ? (r < b ? r : b) : (g < b ? g : b))
            sat = (max == 0) ? 0 : (max - min) / max

            if (n == 0 || lum < darkest) { darkest = lum; dark = hex }
            if (n == 0 || lum > brightest) { brightest = lum; light = hex }
            # accent from midtones only
            if (lum > 60 && lum < 200 && sat > best) { best = sat; accent = hex }
            n++
        }
        END {
            if (n == 0) { print "#12161a #d4d8da #6d7f8a"; exit }
            print dark, light, (accent ? accent : light)
        }'
)
[[ -n "${bg}" && -n "${fg}" && -n "${accent}" ]] || die "could not extract a palette"

# blur + dim so text stays readable on light wallpapers
magick "${source_image}" -resize 2560x2560^ -blur "0x${BLUR_SIGMA}" \
    -fill black -colorize "${DIM}" -quality 88 -strip "${tmp}/background.jpg" ||
    die "could not render the background"

printf '{"background":"%s","foreground":"%s","accent":"%s"}\n' "${bg}" "${fg}" "${accent}" > "${tmp}/colors.json"

# move last
mv -f "${tmp}/background.jpg" "${tmp}/colors.json" "${STATE_DIR}/"
chmod 644 "${STATE_DIR}/background.jpg" "${STATE_DIR}/colors.json"

echo "sddm-theme: staged ${wallpaper} (bg=${bg} fg=${fg} accent=${accent})"
