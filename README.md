# No Asteroids - Mod Menu

**The first mod for No Asteroids** - an in-game mod menu for the mining sandbox game, installed as a patch of `resources\app.asar`. No game assets are shipped or redistributed; only patch scripts.

Press **HOME** in-game to open the menu. All cheats can be toggled live, at any time, no relaunch needed, and are remembered between sessions.

## Features

- **Price multiplier** - OFF / x2 / x4 / x6 / x8 / x16. Scales the daily ore price drift (what terminals PAY you per unit), not shop buy prices.
- **Infinite credits** - floors your balance at $99,999,999 every frame while active; your normal balance takes over when off.
- **Tool upgrade level cap** - x1 / x2 / x4. Lifts the level cap of the four tool upgrade rows (HIT POWER, TEMPO, SWEEP, LUCK) from 20 to 40 or 80 so you can keep buying levels. Levels are normal save progress.
- **Lance+Slicer fire rate 10/s** - ON/OFF. Pins both tools' Rate stat at exactly 10 hits/s (vanilla ~1/s and ~0.7/s with TEMPO maxed) and drops the Lance's minimum charge time so 10/s is actually reachable. OFF restores exact vanilla values.
- **Tool stats readout** - shows your current upgrade levels and what they add up to (the game only shows a static per-level text), plus live effective Lance/Slicer rates.
- **Live sale readout** - today's actual payout per unit for ice and gold, computed with the same function the terminal uses, so you can verify the multiplier instantly.

## Requirements

- No Asteroids (Steam, current build). The installer verifies the vanilla bundle's SHA256 against `resources\app.asar.bak` and refuses to run on a different game version, so a game update can never produce a half-patched file.
- Windows with PowerShell 5.1 (preinstalled) and about 2 GB free disk space.
- The vanilla `resources\app.asar.bak` backup (created by the installer on first run / by the Vortex extension).

## Install (standalone)

1. Download `NoAsteroids-ModMenu-2.2.1.zip` from the [releases](https://github.com/Timourgv/NoAsteroids-ModMenu/releases) page and extract it into the game folder (next to `No Asteroids.exe`).
2. Close the game, double-click `Install-Mod-Menu.bat`.
3. Launch the game and press **HOME**.

## Install (Vortex)

A companion Vortex game extension registers No Asteroids so this mod can be managed like a normal Vortex mod (auto-verify on deploy, automatic vanilla restore on removal). Enable the mod, deploy, then run `Install-Mod-Menu.bat` once. The mod zip installs without questions; the menu startup multiplier is set by `money-multiplier.txt` (below).

## How it works / safety

- `Install-Mod-Menu.bat` runs `Patch-ModMenu.ps1` (Windows PowerShell 5.1 compatible), which rebuilds `resources\app.asar` from the untouched `app.asar.bak` by injecting a small menu module and two hooks into the game's JavaScript bundle, then re-verifies every entry's SHA256 integrity (file + per-block hashes) before swapping it in. If any check fails, nothing is changed.
- The vanilla backup is never modified.
- `money-multiplier.txt` in the game folder (a single text file, default `4`) sets the menu's startup price multiplier; accepted values: `2`, `6`, `8`, `16`, `off`. After first launch the menu's own saved settings take over.
- Everything is logged to `modmenu-patch-log.txt`; NMM/Vortex tooling can read `modmenu-state.txt`.
- Your save file is not edited; progress is stored by the game like any normal progress.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\Patch-ModMenu.ps1 -RestoreVanilla
```

Or, with Vortex, disable/remove the mod and deploy - the extension restores the vanilla `app.asar` automatically.

## Upgrading

Re-run `Install-Mod-Menu.bat` (it always rebuilds from the pristine backup, so no leftover patches accumulate). Saved menu settings carry over. In v2.2.1 the six per-option FOMOD multiplier files were consolidated into this single `money-multiplier.txt`.

## Disclaimer

Unofficial fan mod. Not affiliated with the game's developers. Use at your own risk; competitive/leaderboard saves may flag as modded.
