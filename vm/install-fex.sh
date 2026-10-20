#!/bin/sh
# Runs inside SteamOS (the FX Steam Launcher VM). Installs StonkGuy's patched FEX, tag eac-2610.3 (newer than the
# eac-2610.2 that FX Steam Launcher 1.9-eac.1 installs; Fellowship needs it), into Valve's FEX compatibility tool,
# and prints Fellowship's Steam launch options.
#
#   sh install-fex.sh                  download the prebuilt FEX bundle from this repo's release and install it
#   sh install-fex.sh build            build it here instead (StonkGuy/FEX tag eac-2610.3, unmodified; about 15-25
#                                      minutes, uses the guest's own clang/cmake/ninja)
#   sh install-fex.sh restore          put Valve's original FEX files back
#   sh install-fex.sh status           show which FEX is installed
#   sh install-fex.sh launch-options   print the launch options for this VM
#
# Close Fellowship (and any other Steam game) first: FEX must not be running while its files are swapped.
# Steam can update the FEX tool and overwrite this build; if Fellowship stops starting, run this again.
# The install/backup logic follows StonkGuy/steamac fex-eac/install-fex-tool.sh (Apache-2.0).
set -eu

TAG=eac-2610.3
TAG_SHA=938eedfcd79eb00e86561fbdf4933770766f0ba9
BUNDLE_URL=${BUNDLE_URL:-https://github.com/wkbevill-svg/fellowship-on-mac/releases/download/v1.0/fex-eac-2610.3-arm64.tar.gz}
BUNDLE_SHA=${BUNDLE_SHA:-17e685284be2db7d57d9fce0d0c66550875e0bb687dec90e49e15d8aa1981aee}

V=$HOME/.local/share/Steam/steamapps/common/FEX-Emu
WORK=$HOME/fellowship-on-mac
STAGE=$WORK/stage
B=$WORK/valve-backup
BINS="FEX FEXBash FEXGetConfig FEXOfflineCompiler FEXServer FEXServerManager FEXpidof"
FILES="FEXCompatTool VERSIONS.txt ConfigTemplate.json"

die() { echo "error: $*" >&2; exit 1; }
cur() { sed -n "s/^FEX describe\t//p" "$V/VERSIONS.txt" 2>/dev/null; }

launch_options() {
  n=$(nproc); ids=$(seq -s, 0 $((n - 1)))
  cpus=$ids; i=$n; while [ "$i" -lt 16 ]; do cpus="$cpus,$ids"; i=$((i + n)); done
  cpus=$(echo "$cpus" | cut -d, -f1-16)
  cat <<EOF

Fellowship > Properties > Launch Options (one line):

env EAC_LAUNCHERDIR=\$HOME/.local/share/Steam/steamapps/compatdata/2352620/pfx/drive_c/users/steamuser/AppData/Roaming/EasyAntiCheat PROTON_EAC_RUNTIME="\$HOME/.local/share/Steam/steamapps/common/Proton EasyAntiCheat Runtime" WINEDEBUG=-all PROTON_USE_XALIA=0 FEX_NEEDSSECCOMP=1 FEX_SMCHOTPAGEFAULTS=1 WINE_CPU_TOPOLOGY=16:$cpus %command% -dx11

EOF
}

stage_prebuilt() {
  mkdir -p "$WORK"; rm -rf "$STAGE" "$WORK/bundle.tar.gz"
  echo "downloading the prebuilt FEX bundle"
  curl -fL --progress-bar -o "$WORK/bundle.tar.gz" "$BUNDLE_URL"
  echo "$BUNDLE_SHA  $WORK/bundle.tar.gz" | sha256sum -c - >/dev/null || die "download does not match the published SHA-256"
  mkdir -p "$STAGE"; tar -xzf "$WORK/bundle.tar.gz" -C "$STAGE"
}

stage_build() {
  for t in clang clang++ cmake ninja git python3; do command -v $t >/dev/null || die "$t not found"; done
  SRC=$WORK/FEX
  if [ ! -d "$SRC/.git" ]; then
    git clone --recurse-submodules --shallow-submodules --depth 1 --branch "$TAG" https://github.com/StonkGuy/FEX.git "$SRC"
  fi
  cd "$SRC"
  [ "$(git rev-parse HEAD)" = "$TAG_SHA" ] || die "$SRC is not at $TAG ($TAG_SHA); remove it and run again"
  git diff --quiet HEAD || die "$SRC has local changes; remove it and run again"
  cmake -S . -B build-steam -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_STEAM_SUPPORT=ON -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DBUILD_FEXCONFIG=OFF \
    -DENABLE_LTO=OFF -DENABLE_ASSERTIONS=OFF -DTUNE_CPU=native -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr -DOVERRIDE_VERSION=FEX-$TAG
  cmake --build build-steam -j"$(nproc)"
  # The Runtime component is what Valve's tool ships: the binaries, FEXCompatTool, ConfigTemplate.json, VERSIONS.txt.
  rm -rf "$STAGE"; DESTDIR=$STAGE cmake --install build-steam --component Runtime
  cd - >/dev/null
}

install_stage() {
  [ -d "$V/usr/bin" ] || die "Valve's FEX tool is not installed at $V (install Fellowship with Proton first, see the guide)"
  for b in $BINS; do [ -s "$STAGE/usr/bin/$b" ] || die "stage incomplete: usr/bin/$b"; done
  for f in $FILES; do [ -s "$STAGE/$f" ] || die "stage incomplete: $f"; done
  if [ ! -d "$B/valve" ]; then
    mkdir -p "$B/valve/usr/bin"
    for b in $BINS; do cp "$V/usr/bin/$b" "$B/valve/usr/bin/$b"; done
    for f in $FILES; do cp "$V/$f" "$B/valve/$f"; done
    echo "backed up Valve's FEX ($(cur)) to $B/valve"
  fi
  pgrep -x FEXServer >/dev/null && die "FEX is running: close Fellowship / other Steam games and try again"
  for b in $BINS; do cp "$STAGE/usr/bin/$b" "$V/usr/bin/.$b.new" && mv -f "$V/usr/bin/.$b.new" "$V/usr/bin/$b"; done
  for f in $FILES; do cp "$STAGE/$f" "$V/.$f.new" && mv -f "$V/.$f.new" "$V/$f"; done
  echo "installed: $(cur)"
}

case "${1:-install}" in
status) echo "installed FEX: $(cur)"; [ -d "$B/valve" ] && echo "Valve backup: $B/valve" ;;
restore)
  [ -d "$B/valve" ] || die "no backup in $B/valve"
  pgrep -x FEXServer >/dev/null && die "FEX is running: close Steam games first"
  for b in $BINS; do cp "$B/valve/usr/bin/$b" "$V/usr/bin/.$b.new" && mv -f "$V/usr/bin/.$b.new" "$V/usr/bin/$b"; done
  for f in $FILES; do cp "$B/valve/$f" "$V/.$f.new" && mv -f "$V/.$f.new" "$V/$f"; done
  echo "restored: $(cur)" ;;
launch-options) launch_options ;;
build) stage_build; install_stage; launch_options ;;
install) stage_prebuilt; install_stage; launch_options ;;
*) echo "usage: sh install-fex.sh [install|build|restore|status|launch-options]"; exit 2 ;;
esac
