# How it works, and what each change does

This is for anyone (or any agent) who wants to check the work before running it. Everything here sits on top of
[StonkGuy/steamac](https://github.com/StonkGuy/steamac) **v1.9-eac.1**, a fork of FX Steam Launcher that runs genuine
Easy Anti-Cheat games: a libkrun VM with SteamOS (ARM64), x86 emulation through a patched FEX
([StonkGuy/FEX](https://github.com/StonkGuy/FEX)), Proton, and DXMT (Direct3D 11 to Metal).

Out of the box Fellowship needs a newer FEX build than the launcher installs and the right launch options, and two
launcher problems make it hard to play. This repo covers those, and nothing else.

## 1. FEX: use StonkGuy's eac-2610.3 (no changes)

FX Steam Launcher 1.9-eac.1 installs StonkGuy's patched FEX at tag `eac-2610.2`. In my earlier testing that build
stopped Fellowship's anti-cheat start with EAC "Unexpected error (#2)"; the fix for it (StonkGuy/FEX PR #17, ptrace
and alignment-fault stops) landed after `eac-2610.2`. StonkGuy's newer tag **`eac-2610.3`** (`938eedf`) includes it
and more; tested unmodified: EAC result 301 ("successfully loaded in-game"), title screen, hero select, town, logout.

`vm/install-fex.sh` either downloads the prebuilt bundle from this repo's release (that tag, built inside the
SteamOS guest with the same Steam-mode release options as StonkGuy's `fex-eac/build-fex.sh`; FEX disables
`-mcpu=native` inside a VM, so it is generic armv8-a code) or builds the tag itself (`install-fex.sh build`). It swaps
the binaries into Valve's FEX compatibility tool (Steam app 3127680) the way StonkGuy's `install-fex-tool.sh` does,
after backing up Valve's files; `install-fex.sh restore` puts them back. No FEX source is changed by this repo.

(Earlier, on `eac-2610.2`-era builds, I needed a small local FEX patch to how invalid-instruction signals are
reported. With `eac-2610.3` the game starts without it, so it is not included.)

## 2. Launcher: right-drag mouse-look (`patches/launcher-right-drag-mouselook.patch`)

Fellowship turns the camera while you hold the right mouse button. It hides its cursor when the drag starts and,
when you let go, puts the cursor back where it hid it (Windows games do this; on a PC the OS pointer jumps back too).

In the launcher's default mouse mode the Mac pointer is the visible cursor and the launcher steers the game's
(invisible) cursor with relative motion from a model of where it is. During a right-drag the Mac pointer kept
moving while the game put its cursor back on release, so the two ended up apart by the length of the drag: hover
and clicks landed somewhere else until the launcher re-synced after 1.5 s without motion.

The patch (`host/launcher/Sources/steamac-vm/Window.swift`, ~45 lines):

- while a game has focus and the right button is held, the Mac pointer stays at the press point and raw motion goes
  to the game, the same way captured mode works (`CGAssociateMouseAndMouseCursorPosition(0)`, cursor hidden);
- on release the pointer reappears where it was pressed, which is where the game puts its cursor;
- the game hides its cursor only after a short drag and restores it *there*, so after a drag the next mouse motion
  (from 0.15 s after the release) re-syncs the game's cursor to the Mac pointer, using the launcher's existing
  re-anchor (corner and back, which can briefly hover the top-left UI);
- quick right-clicks without motion are unchanged; left button, Steam's UI and other games' captured mode too;
- off switch: `defaults write es.fxgam.steamac rightDragMouseLook -bool false`.

Side effect: right-drag turning now uses 1 count per Mac point (captured-mode rate), about twice the old rate at
render scale 0.5. Lower the in-game sensitivity if it feels fast.

Measured in the town with real CoreGraphics mouse events: after a 600-point right-drag the game's cursor was 0-1 px
from the Mac pointer (stock launcher: 729 px).

## 3. Launcher: the game freezes when you quit or log out (`mac/install-launcher-fixes.sh`, wmtr part)

On the DXMT graphics path, Metal objects live on the Mac side (`libwmtr_host.dylib`, "wmtr"). When the game releases
a buffer, the Mac side reports the freed memory back through a 4096-entry ring that the game side empties only when it
allocates (`wmtr/src/wmtr_host.m`, `push_free`). If the ring is full, `push_free` waits in a `usleep` loop, inside the
release call the game itself is waiting on. Quitting, logging out or a large unload frees thousands of buffers in a
row, fills the ring and deadlocks the game. Then Steam's UI and Xwayland stall too, and shutting SteamOS down needs the
launcher's 180 s forced power-off.

Seen in `sample` of the VM process during three freezes: a `wmtr-executor` thread in
`host_call → NSObject_release → IOGPUMetalBuffer dealloc → __host_new_buffer_block_invoke → usleep`.

The fix is one instruction in the shipped `libwmtr_host.dylib` (1.9-eac.1, SHA-256 `9a1ef6a0…6c61`): at `0x3950`
the wait loop's first instruction `add x0, x20, x21` becomes `b 0x399c`, the function's own unlock-and-return. When
the ring is full the release returns instead of waiting. The cost: that buffer's memory range is not reused by the
game until it exits (at least 16 KB each, and only when more than 4096 frees pile up without an allocation).

A proper source fix would keep an overflow list on the Mac side and hand it over as the ring drains. It needs the full
wmtr build (DXMT + LLVM 15) and is not done here. As of v1.9-eac.2 the bug is still in StonkGuy's tree (it drains the
ring more often, which should make the freeze rarer, not impossible).

## Launch options

```
env EAC_LAUNCHERDIR=$HOME/.local/share/Steam/steamapps/compatdata/2352620/pfx/drive_c/users/steamuser/AppData/Roaming/EasyAntiCheat PROTON_EAC_RUNTIME="$HOME/.local/share/Steam/steamapps/common/Proton EasyAntiCheat Runtime" WINEDEBUG=-all PROTON_USE_XALIA=0 FEX_NEEDSSECCOMP=1 FEX_SMCHOTPAGEFAULTS=1 WINE_CPU_TOPOLOGY=16:0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7 %command% -dx11
```

- `EAC_LAUNCHERDIR`, `PROTON_EAC_RUNTIME`: load Proton's EAC runtime (same as the fork's VRChat instructions).
- `FEX_NEEDSSECCOMP=1`: Wine installs a seccomp filter for this game; FEX must emulate it (fork patch 0010).
- `FEX_SMCHOTPAGEFAULTS=1`: code pages that keep faulting stay writable and are checked in the JIT instead (fork
  patch 0002). Without it EAC stopped with "Unexpected error (#2)" in our tests.
- `WINE_CPU_TOPOLOGY`: report 16 CPUs mapped onto the VM's vCPUs (the list must match your vCPU count;
  `vm/install-fex.sh launch-options` prints yours).
- `-dx11`: Fellowship defaults to Direct3D 12; the DXMT path is Direct3D 11.

## What was tested

M3 Max, macOS 27.0, FX Steam Launcher 1.9-eac.1, VM with 8 vCPUs / 16 GB, Graphics path DXMT, render scale 0.5 on a
5120x2160 display, Proton Experimental. Genuine EAC (launcher result 301), title screen, hero select and the town.
Not tested: other Macs, other macOS versions, dungeons for long sessions, v1.9-eac.2.
