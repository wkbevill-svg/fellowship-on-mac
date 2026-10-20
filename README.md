# Fellowship on a Mac (Apple Silicon)

How I got [Fellowship](https://store.steampowered.com/app/2352620/Fellowship/) running on my M3 Max, anti-cheat
and all, using StonkGuy's fork of FX Steam Launcher. That fork does the heavy lifting: it runs SteamOS in a VM on
your Mac, emulates x86 with a patched FEX, and runs Windows games through Proton with genuine Easy Anti-Cheat.
On top of that, Fellowship needed three things, which this repo sets up:

1. StonkGuy's newer FEX build (eac-2610.3, unmodified) so the anti-cheat loads; the launcher installs an older one
2. a launcher fix so the cursor lines up again after you right-drag to turn the camera
3. a launcher fix so the game doesn't freeze the whole VM when you quit or log out

**Full disclosure:** this was vibe coded with Claude. I'm not a developer of any of these projects. It works for me,
but the changes are small and readable, and I'd encourage you to have your own agent (or yourself) review them
before running anything. [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) explains every change.

Not affiliated with Chief Rebel, Easy Anti-Cheat/Epic, Valve, FX Games, StonkGuy or FEX-Emu. Running an anti-cheat
game in an emulator is not officially supported. I haven't had problems, but use it at your own risk.

## What you need

- An Apple Silicon Mac (tested: M3 Max, macOS 27). Other M-series Macs should work but are untested.
- Roughly 100 GB free disk space (SteamOS disk plus the game).
- A Steam account that owns Fellowship.
- About an hour, most of it downloads.

## Steps

### 1. Install the launcher

Download **FX Steam Launcher 1.9-eac.1** from StonkGuy's releases:
<https://github.com/StonkGuy/steamac/releases/tag/v1.9-eac.1> (`FX-Steam-Launcher-1.9-eac.1-adhoc.dmg`).

Use exactly this version; the fixes below are made for it. Drag the app to Applications and open it. macOS will block
it the first time: go to System Settings > Privacy & Security and click **Open Anyway**.

### 2. Set up SteamOS and Steam

Follow the launcher's first-run steps: it creates the SteamOS disk and starts Steam. Sign in to Steam.

Then, in the launcher's **Settings** (Cmd+,):

- **Advanced > Graphics path: DXMT**
- **Advanced > Enable SSH: on** (the scripts below use it to install FEX in the VM)

Restart the VM when it asks.

### 3. Install Fellowship in Steam (inside the VM)

- Install Fellowship.
- Fellowship > Properties > Compatibility: force **Proton Experimental**.
- In your Library, under Tools, install **Proton EasyAntiCheat Runtime**.
- Start Fellowship once and let it fail or close it. This makes Steam download its FEX tool.

### 4. Install the newer FEX build

On your Mac, in Terminal, with the launcher running and Steam up:

```
git clone https://github.com/wkbevill-svg/fellowship-on-mac.git
cd fellowship-on-mac
./mac/vm.sh fex
```

This copies `vm/install-fex.sh` into SteamOS and runs it. It downloads the prebuilt FEX bundle (or run
`./mac/vm.sh fex build` to compile it inside SteamOS yourself, 15-25 minutes), backs up Valve's FEX and installs
it. At the end it prints Fellowship's **launch options**, one long line. Copy it, then in Steam:
Fellowship > Properties > Launch Options, paste. (The launcher shares the Mac clipboard with SteamOS.)

### 5. Install the launcher fixes

Quit FX Steam Launcher (shut down SteamOS), then:

```
./mac/install-launcher-fixes.sh
```

It checks that your launcher really is 1.9-eac.1, backs up the two files it changes, installs the fixed launcher
binary and re-signs the app. To build that binary yourself instead of downloading it: `./mac/build-launcher.sh`
first (needs Xcode).

### 6. Play

Start the launcher and Fellowship. The first start takes a few minutes (anti-cheat and shader compiling).

Tips:

- Ctrl+Cmd+F for full screen. If it's slow, lower Settings > Display > Render scale.
- Right-drag turning is about twice as fast as before the fix; lower the in-game mouse sensitivity if needed.
- If Steam updates its FEX tool, Fellowship stops starting: run `./mac/vm.sh fex` again.

## Undo

- FEX: `./mac/vm.sh fex restore` (puts Valve's FEX back)
- Launcher: quit it, then `./mac/install-launcher-fixes.sh restore`

## Troubleshooting

- **`./mac/vm.sh` says no SSH:** turn on Settings > Advanced > Enable SSH, restart the VM.
- **EAC error at launch:** check that the launch options are pasted as one line and that Proton Experimental is
  forced. `./mac/vm.sh fex status` shows which FEX is installed (`FEX-eac-2610.3`).
- **"This is not the original 1.9-eac.1 launcher":** reinstall the app from the DMG, then run the script again.

## Credits

All the real work is StonkGuy's ([steamac](https://github.com/StonkGuy/steamac), [FEX](https://github.com/StonkGuy/FEX),
[write-up](https://github.com/StonkGuy/eac-arm64-emulation-poc)), built on FX Steam Launcher by FX Games
([fxgl/steamac](https://github.com/fxgl/steamac)), FEX-Emu, libkrun, DXMT, Wine/Proton and Valve's SteamOS.
See [NOTICE](NOTICE).
