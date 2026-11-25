# No Asteroids - Mod Menu

An in-game **MOD MENU** for No Asteroids (press **HOME**):

- **Price multiplier**: OFF / x2 / x4 / x6 / x8 / x16 - multiplies the daily ore
  price drift (what terminals pay you per unit), switchable live at any time,
  no relaunch needed.
- **Infinite credits**: tops your credits up to $99,999,999 every frame while
  active, so every purchase, bet and upgrade is affordable. Turn it off and
  your normal balance takes over again.
- **Tool upgrade level cap**: x1 / x2 / x4 - lifts the level cap of the four
  tool upgrade rows (HIT POWER, TEMPO, SWEEP, LUCK) from 20 to 40 or 80, so
  you can keep buying levels. Works for every tool, no relaunch needed.
- **Lance+Slicer fire rate 10/s**: ON/OFF - pins the Lance and Slicer Rate
  stat at 10 hits/s (vanilla: about 1/s and 0.7/s once TEMPO is maxed) and
  drops the Lance's minimum charge time so 10/s is actually reachable.
  OFF restores the exact vanilla values.
- **Tool stats readout**: the menu shows your current upgrade levels and what
  they add up to (the game itself only shows a static per-level text), plus
  the live effective Lance/Slicer rates.
- **Live sale readout**: the menu shows today's actual payout per unit for
  ice and gold, so you can instantly verify the multiplier working.

Settings are remembered between sessions and can be changed any time. Your
save file is not edited; the game saves your upgrade levels and balance like
any normal progress. The menu can be dragged around by its title bar and
hidden with Home or Esc.

## What the multiplier changes

The multiplier scales the price TERMINALS PAY when you sell ore (the daily
drift between 0.75x and 1.35x of base in vanilla). It does NOT change shop
BUY prices (tools, slot upgrades): those are fixed game prices.

## Startup default: money-multiplier.txt

The menu's startup multiplier comes from `money-multiplier.txt` in the game
folder - a single plain text file containing `4` by default. Before the first
launch you can edit it to `2`, `6`, `8`, `16` or `off`. After the first launch
the menu remembers your in-game choice instead, and every setting is always
changeable live (HOME), no relaunch needed.

## What the level cap changes

The game blocks the four tool upgrade rows at level 20 ("20/20 Max"). The cap
option raises that limit to 40 (x2) or 80 (x4). Prices per level keep growing
the way the game intends. Levels you bought stay in your save like normal
progress; setting the cap back to x1 does not remove levels you already own
(you just cannot buy more until you are below 20 again).

## Install with Vortex (recommended)

Vortex does not know this game by default, so there are two one-time installs:

1. **Game extension (one time, updates 1.x):** Vortex -> Settings ->
   Extensions -> `Install from file` -> pick
   `noasteroids-vortex-game-extension-2.0.0.zip` -> restart Vortex.
2. In the Vortex dashboard, find **No Asteroids** under Apps, click **Manage**
   and point it to your game folder (the one containing `No Asteroids.exe`).
3. **The mod:** Mods -> `Install from file` -> pick
   `NoAsteroids-ModMenu-2.2.1.zip`. It installs without questions; the menu
   starts at x4. (Different startup multiplier? Edit `money-multiplier.txt`
   in the game folder before first launch - or just change it in-game.)
4. Enable the mod and let Vortex deploy. The extension detects that the menu
   is not installed yet and notifies you: open the game folder and
   **double-click `Install-Mod-Menu.bat`** once. Close the game first; the
   installer rebuilds `resources\app.asar` (about 500 MB, a few minutes).

From then on it behaves like a normal Vortex mod:

- **Enable the mod + deploy** -> extension verifies the menu is installed.
- **Disable or remove the mod (deploy again)** -> the vanilla `app.asar` is
  restored automatically from the backup.

## Install manually (no Vortex)

1. Extract the zip contents into the game folder (next to `No Asteroids.exe`).
2. Close the game, double-click `Install-Mod-Menu.bat`.
3. Launch the game and press **HOME**.

## How it works / safety

- The installer rebuilds `resources\app.asar` from the untouched backup
  `resources\app.asar.bak` by injecting a small menu module and two hooks into
  the game's JavaScript bundle. Nothing about the game's assets is
  redistributed; the mod ships only patch scripts.
- Before the rebuilt `app.asar` replaces the live one, every entry's SHA256
  integrity (file hash + per-block hashes) is re-verified. If any check fails,
  nothing is changed.
- Your original vanilla `app.asar` is always kept as `resources\app.asar.bak`
  and is never modified.
- Everything is logged to `modmenu-patch-log.txt` in the game folder.

## Uninstall

- With Vortex: disable/remove the mod and deploy - the extension restores the
  vanilla `app.asar` automatically.
- Manually: run

  ```
  powershell -ExecutionPolicy Bypass -File .\Patch-ModMenu.ps1 -RestoreVanilla
  ```

## Upgrading from v2.0.0 / v2.1.0 / v2.2.0

Re-run `Install-Mod-Menu.bat` (it always rebuilds from the pristine backup).
Your saved menu settings (multiplier, infinite credits) carry over.
- v2.2.0 added the tool upgrade level cap (x2/x4), the Lance+Slicer 10/s fire
  rate toggle and the tool stats readout.
- v2.2.1 is a packaging cleanup: a single `money-multiplier.txt` replaces the
  per-option FOMOD multiplier files. No functional changes.

## Upgrading from v1.x

Install this mod and run the installer once - it rebuilds the game from the
pristine backup, so no leftover patches accumulate. `Patch-Money-Multiplier.ps1`
and `Install-Money-Multiplier.bat` are superseded and can be deleted after
upgrading.
