# No Asteroids Mod Menu v2.2.0

In-game mod menu for No Asteroids. Press **HOME** in-game to open the menu; settings are remembered between sessions.

## Features

- **Price multiplier**: OFF / x2 / x4 / x6 / x8 / x16, applied as a daily drift range (x4 drifts between 3.0x and 5.4x of base prices)
- **Infinite credits** toggle (safe floor, never lets the run stat go negative)
- **Tool upgrade level cap**: x1 / x2 / x4 on the HIT POWER / TEMPO / SWEEP / LUCK tracks
- **Lance + Slicer fire rate**: 10/s toggle
- Live **tool stats** and **today's sale payout** readouts
- The untouched vanilla `app.asar` is kept as `app.asar.bak`; restore any time with `-RestoreVanilla`

## Downloads

| File | What it is |
| --- | --- |
| `NoAsteroids-ModMenu-2.2.0.zip` | The mod: manual install or Vortex (FOMOD installer) |
| `noasteroids-vortex-game-extension-2.0.0.zip` | Vortex game extension (Vortex users only, install once before the mod) |

## Manual install

1. Close the game.
2. Unzip into the game folder (next to `resources\app.asar`).
3. Double-click `Install-Mod-Menu.bat`. Needs ~500 MB free disk (temporary build copy) and PowerShell 5.1 (bundled with Windows).
4. Launch the game and press HOME.

## Vortex install

1. Install the game extension zip first (Vortex prompts for it, or Mods -> Install from file).
2. Install the mod zip; Vortex asks for your default price multiplier, then deploys.
3. The extension warns you to run `Install-Mod-Menu.bat` after deployment, and restores the vanilla `app.asar` automatically when you remove the mod.

## Uninstall

Either run `Patch-ModMenu.ps1 -RestoreVanilla`, or in Vortex just remove the mod (the game extension restores vanilla automatically).
