# No Asteroids Mod Menu v2.2.1

Packaging cleanup release: the six per-option FOMOD multiplier files (`multipliers/off.txt` ... `multipliers/x16.txt`) are replaced by **one** `money-multiplier.txt`. In-game functionality is unchanged from v2.2.0.

## What changed

- Mod and Vortex installs no longer ask for a startup multiplier; the FOMOD install step is gone.
- The menu starts at **x4** by default. To pre-set a different startup multiplier, edit `money-multiplier.txt` (game folder / mod root, one line: `4`) to `2`, `6`, `8`, `16` or `off` before the first launch.
- After the first launch the menu remembers your in-game choice; everything stays changeable live (HOME).

## Features (unchanged)

- **Price multiplier**: OFF / x2 / x4 / x6 / x8 / x16, applied as a daily drift range (x4 drifts between 3.0x and 5.4x of base prices)
- **Infinite credits** toggle (safe floor, never lets the run stat go negative)
- **Tool upgrade level cap**: x1 / x2 / x4 on the HIT POWER / TEMPO / SWEEP / LUCK tracks
- **Lance + Slicer fire rate**: 10/s toggle
- Live **tool stats** and **today's sale payout** readouts
- The untouched vanilla `app.asar` is kept as `app.asar.bak`; restore any time with `-RestoreVanilla`

## Downloads

| File | What it is |
| --- | --- |
| `NoAsteroids-ModMenu-2.2.1.zip` | The mod: manual install or Vortex (FOMOD) |
| `noasteroids-vortex-game-extension-2.0.0.zip` | Vortex game extension (Vortex users only, install once before the mod) |

## Manual install

1. Close the game.
2. Unzip into the game folder (next to `resources\app.asar`).
3. Double-click `Install-Mod-Menu.bat`. Needs ~500 MB free disk (temporary build copy) and PowerShell 5.1 (bundled with Windows).
4. Launch the game and press HOME.

## Upgrade from v2.2.0 (or older)

Re-run `Install-Mod-Menu.bat`. Saved menu settings carry over. If you previously picked a non-x4 startup multiplier in the Vortex installer, edit `money-multiplier.txt` accordingly or set it once in the menu.

## Uninstall

Either run `Patch-ModMenu.ps1 -RestoreVanilla`, or in Vortex just remove the mod (the game extension restores vanilla automatically).
