#!/bin/zsh
# Build the patched launcher binary yourself instead of downloading it (needs Xcode or the Command Line Tools,
# and network access for Swift packages and zstd). Output: ./steamac-vm.patched, which install-launcher-fixes.sh
# then uses instead of the download.
#
# Source: StonkGuy/steamac tag v1.9-eac.1 + ../patches/launcher-right-drag-mouselook.patch. Links against the
# libkrun.1.dylib inside your installed FX Steam Launcher.app; libkrun headers are in ./libkrun-include.
set -euo pipefail
HERE=${0:A:h}
WORK=${WORK:-$HERE/build}
APP=${APP:-$HOME/Applications/FX Steam Launcher.app}
[[ -d "$APP" ]] || APP="/Applications/FX Steam Launcher.app"
[[ -d "$APP" ]] || { echo "FX Steam Launcher.app not found (set APP=)"; exit 1; }
xcrun --find swift >/dev/null 2>&1 || { echo "No Swift compiler: install Xcode or run xcode-select --install"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
git clone -q --depth 1 --branch v1.9-eac.1 https://github.com/StonkGuy/steamac.git "$WORK/steamac"
cd "$WORK/steamac"
git apply --verbose "$HERE/../patches/launcher-right-drag-mouselook.patch"
grep -q rightDragMouseLook host/launcher/Sources/steamac-vm/Window.swift

KP="$WORK/krun"; mkdir -p "$KP/include" "$KP/lib"
cp "$HERE"/libkrun-include/*.h "$KP/include/"
cp "$APP/Contents/Frameworks/libkrun.1.dylib" "$KP/lib/"
ln -sf libkrun.1.dylib "$KP/lib/libkrun.dylib"
L="$WORK/steamac/host/launcher"
"$L/fetch-zstd.sh"
mkdir -p "$L/.build"; cp "$APP/Contents/Info.plist" "$L/.build/Info.plist"
FLAGS=(-c release --package-path "$L" --scratch-path "$L/.build"
       -Xcc "-I$KP/include" -Xlinker "-L$KP/lib"
       -Xlinker -rpath -Xlinker @executable_path/../Frameworks
       -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$L/.build/Info.plist")
swift build "${FLAGS[@]}"
cp "$(swift build "${FLAGS[@]}" --show-bin-path)/steamac-vm" "$HERE/steamac-vm.patched"
echo "built: $HERE/steamac-vm.patched — now run ./install-launcher-fixes.sh (launcher quit)"
