#!/bin/zsh
# Run the VM-side installer from the Mac over SSH (FX Steam Launcher running, SteamOS booted).
# Needs FX Steam Launcher > Settings > Advanced > "Enable SSH" (restart the VM after turning it on).
#
#   ./vm.sh fex            install the prebuilt FEX bundle in SteamOS and print Fellowship's launch options
#   ./vm.sh fex build      build FEX inside SteamOS instead (15-25 minutes)
#   ./vm.sh fex restore    put Valve's FEX back
#   ./vm.sh shell          open a shell in SteamOS
#
# The SSH password is the one the launcher generated for your disk (steamac-vm --ssh-password); it is never shown.
set -euo pipefail
HERE=${0:A:h}
APP=${APP:-$HOME/Applications/FX Steam Launcher.app}
[[ -d "$APP" ]] || APP="/Applications/FX Steam Launcher.app"
EXE="$APP/Contents/MacOS/steamac-vm"
[[ -x "$EXE" ]] || { echo "FX Steam Launcher.app not found (set APP=)"; exit 1; }
DISK=$(defaults read es.fxgam.steamac diskImage 2>/dev/null || true)
[[ -n "$DISK" ]] || DISK="$HOME/Library/Application Support/es.fxgam.steamac/steamos.img"
PORT=$(defaults read es.fxgam.steamac sshPort 2>/dev/null || echo 2222)
nc -z -w2 127.0.0.1 "$PORT" 2>/dev/null || { echo "No SSH on port $PORT: start the launcher, enable SSH (Settings > Advanced), restart the VM."; exit 1; }

# askpass helper: prints the disk's generated password to ssh only
ASK=$(mktemp -t fellowship-askpass); trap 'rm -f "$ASK"' EXIT
cat > "$ASK" <<EOF
#!/bin/sh
"$EXE" --ssh-password "$DISK" --no-crash-reports | sed -n 's/^password //p'
EOF
chmod 700 "$ASK"
export SSH_ASKPASS="$ASK" SSH_ASKPASS_REQUIRE=force DISPLAY=:0
KH="$HOME/Library/Application Support/fellowship-on-mac/known_hosts"; mkdir -p "${KH:h}"
SSH=(ssh -p "$PORT" -o UserKnownHostsFile="$KH" -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no steamos@127.0.0.1)

case "${1:-}" in
fex)
  "${SSH[@]}" 'mkdir -p ~/fellowship-on-mac/vm && cat > ~/fellowship-on-mac/vm/install-fex.sh' < "$HERE/../vm/install-fex.sh"
  "${SSH[@]}" -t "sh ~/fellowship-on-mac/vm/install-fex.sh ${2:-install}" ;;
shell) "${SSH[@]}" ;;
*) echo "usage: $0 fex [build|restore|status|launch-options] | shell"; exit 2 ;;
esac
