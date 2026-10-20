#!/bin/zsh
# Fellowship fixes for FX Steam Launcher 1.9-eac.1 (StonkGuy/steamac). Run on the Mac with the launcher quit.
#
#   ./install-launcher-fixes.sh           install both fixes (backs up the two original files first)
#   ./install-launcher-fixes.sh restore   put the original files back
#   ./install-launcher-fixes.sh status    show what is installed
#
# 1. Right-drag mouse-look: the launcher binary (Contents/MacOS/steamac-vm) built from the v1.9-eac.1 tag with
#    ../patches/launcher-right-drag-mouselook.patch. Downloaded from this repo's release and checked against its
#    SHA-256, or built locally with ./build-launcher.sh (needs Xcode).
# 2. Quit/logout freeze on the DXMT path: a one-instruction change in Contents/Frameworks/libwmtr_host.dylib
#    (see ../docs/HOW-IT-WORKS.md).
# The app is re-signed ad hoc afterwards with the launcher's own entitlements.
set -euo pipefail
HERE=${0:A:h}
APP=${APP:-}
if [[ -z "$APP" ]]; then
  for a in "$HOME/Applications/FX Steam Launcher.app" "/Applications/FX Steam Launcher.app"; do
    [[ -d "$a" ]] && { APP="$a"; break; }
  done
fi
[[ -n "$APP" && -d "$APP" ]] || { echo "FX Steam Launcher.app not found (set APP=/path/to/FX Steam Launcher.app)"; exit 1; }
EXE="$APP/Contents/MacOS/steamac-vm"
LIB="$APP/Contents/Frameworks/libwmtr_host.dylib"
BACKUP="$HOME/Library/Application Support/fellowship-on-mac/backup"
ENT="$HERE/steamac-vm.entitlements"

# Original 1.9-eac.1 files (from FX-Steam-Launcher-1.9-eac.1-adhoc.dmg, SHA-256 8363bdd6…e579)
ORIG_EXE_SHA=6a0d1401f7fde2eb0819bc0731de913ee07bc04ca32a53f4903d525a916ffd9f
ORIG_LIB_SHA=9a1ef6a015302660b8a7cf81502cd557bab6422ec5ed08d9b3702869455c6a61
# Patched launcher binary as published in the release (unsigned beyond the linker's ad-hoc signature)
PATCHED_EXE_SHA=490fac3296f314e7cc25876545bad77b08a5d88b650907f873a6672db40063d7
PATCHED_EXE_URL=${PATCHED_EXE_URL:-https://github.com/wkbevill-svg/fellowship-on-mac/releases/download/v1.0/steamac-vm-1.9-eac.1-fellowship}
LIB_OFF=$((0x3950))   # add x0,x20,x21 (80 02 15 8b) -> b 0x399c (13 00 00 14)

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
running() { pgrep -f "$EXE" >/dev/null; }
resign() {
  xattr -cr "$APP"   # Finder/iCloud attributes make codesign refuse the bundle
  codesign --force --sign - --timestamp=none --entitlements "$ENT" "$EXE"
  codesign --force --sign - --timestamp=none "$LIB"
  codesign --force --sign - --timestamp=none --entitlements "$ENT" "$APP"
  codesign --verify --deep --strict "$APP" && echo "signature OK"
}

case "${1:-install}" in
status)
  echo "app: $APP"
  [[ -f "$BACKUP/steamac-vm" ]] && echo "launcher fixes: installed (originals in $BACKUP)" || echo "launcher fixes: not installed"
  [[ $(xxd -s $LIB_OFF -l 4 -p "$LIB") == 13000014 ]] && echo "wmtr fix: present" || echo "wmtr fix: absent"
  exit 0 ;;
restore)
  running && { echo "Quit FX Steam Launcher first."; exit 1; }
  [[ -f "$BACKUP/steamac-vm" && -f "$BACKUP/libwmtr_host.dylib" ]] || { echo "no backup in $BACKUP"; exit 1; }
  cp "$BACKUP/steamac-vm" "$EXE"; cp "$BACKUP/libwmtr_host.dylib" "$LIB"
  resign
  echo "original launcher code restored (re-signed). For a byte-identical app, reinstall it from the 1.9-eac.1 DMG."
  rm -rf "$BACKUP"; exit 0 ;;
install) ;;
*) echo "usage: $0 [install|restore|status]"; exit 2 ;;
esac

running && { echo "Quit FX Steam Launcher first (shut down SteamOS), then run this again."; exit 1; }

# Back up the originals once, and only if they really are the 1.9-eac.1 files.
mkdir -p "$BACKUP"
if [[ ! -f "$BACKUP/steamac-vm" ]]; then
  [[ $(sha "$EXE") == $ORIG_EXE_SHA ]] || { echo "This is not the original 1.9-eac.1 launcher (steamac-vm $(sha "$EXE")). Reinstall it from the DMG first."; exit 1; }
  [[ $(sha "$LIB") == $ORIG_LIB_SHA ]] || { echo "libwmtr_host.dylib is not the 1.9-eac.1 original ($(sha "$LIB")). Reinstall from the DMG first."; exit 1; }
  cp -p "$EXE" "$BACKUP/steamac-vm"; cp -p "$LIB" "$BACKUP/libwmtr_host.dylib"
  echo "backed up the originals to $BACKUP"
fi

# 1. Patched launcher binary: a local build (./build-launcher.sh) wins over the download.
NEW="$HERE/steamac-vm.patched"
if [[ ! -f "$NEW" ]]; then
  echo "downloading the patched launcher binary"
  curl -fL --progress-bar -o "$NEW.part" "$PATCHED_EXE_URL"
  [[ $(sha "$NEW.part") == $PATCHED_EXE_SHA ]] || { rm -f "$NEW.part"; echo "download does not match the published SHA-256"; exit 1; }
  mv "$NEW.part" "$NEW"
fi
grep -aq rightDragMouseLook "$NEW" || { echo "$NEW does not contain the right-drag fix"; exit 1; }
cp "$NEW" "$EXE.new" && mv -f "$EXE.new" "$EXE"
echo "installed the right-drag mouse-look launcher"

# 2. wmtr fix, applied to the backed-up original.
cur=$(xxd -s $LIB_OFF -l 4 -p "$BACKUP/libwmtr_host.dylib")
[[ $cur == 8002158b ]] || { echo "unexpected bytes at 0x3950 in libwmtr_host.dylib: $cur"; exit 1; }
cp "$BACKUP/libwmtr_host.dylib" "$LIB.new"
printf '\x13\x00\x00\x14' | dd of="$LIB.new" bs=1 seek=$LIB_OFF conv=notrunc 2>/dev/null
mv -f "$LIB.new" "$LIB"
echo "applied the wmtr quit-freeze fix"

resign
echo "done. Start FX Steam Launcher as usual. If macOS asks whether it may access a folder, allow it."
