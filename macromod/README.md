## Farever Macros

Chain key presses with delays into macros and start them with one hotkey. Three independent macros, up to ten steps each, all configurable from the in-game mod settings.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings

### Main features

- **Three independent macros:** Each macro has its own name, activation key, mode and up to ten steps. All three can run at the same time.
- **Steps with delays:** Every step is a key plus the delay (60-5000 ms) before the next step. Empty steps are skipped. The minimum delay is 60 ms so every key press is registered by the game.
- **Press (Toggle) or Hold:** In Toggle mode press the activation key to start the macro and press it again to stop. In Hold mode the macro runs only while the key is held down.
- **Repeat in loop:** Run the steps once, or loop them until you stop the macro.
- **Hotkey modifiers:** Activation keys accept Ctrl, Shift or Alt combinations, with Farever's strict matching: Ctrl+1 does not also trigger a plain 1.
- **Clear buttons:** A small red X next to every key button resets the key to "Not set" and updates the button right away. Right-clicking a key button works too.
- **Background hotkeys (optional):** The setting "Work when the game window is not focused" reads your activation keys from Windows, so hotkeys are still detected while another window is in front.
- **Better Mod Settings integration:** Press Esc to open the Game Menu and choose "Mod Settings" > "Farever Macros" to see all settings.

### Quick start

1. Open Esc > Mod Settings > Farever Macros.
2. Under "M1 Activation Key" click the key button and press the key (or a combination) that should start the macro.
3. Pick the mode: Press (Toggle) or Hold. Tick "Repeat in loop" if the macro should keep going.
4. Set "Step 1 Key" and "Step 1 Delay (ms)", then the next steps. Leave unused steps at "Not set".
5. Close the settings and press the activation key in game.

### Notes

- Macros send key presses to Farever's own key input, the same way the keyboard does. They do nothing outside the game.
- Background hotkeys use a small native plugin (*macro_keys.hdll*, included, Windows x64 only). It only answers whether a key is down right now: it installs no hook and records nothing. If the file is missing or blocked by your antivirus, hotkeys simply work only while the game window is in focus.
- Macros run inside the game's own update loop, so they keep running in the background only as long as Farever itself keeps updating while it is not in focus.


## LICENSE

Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)

Copyright (c) 2026 IamMorgan

You are free to:
- Share — copy and redistribute the material in any medium or format.
- Adapt — remix, transform, and build upon the material.

Under the following terms:
- Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- NonCommercial — You may not use the material for commercial purposes (including selling it, or using it in any other software that is sold for money).

The software is provided "as is", without warranty of any kind, express or implied. In no event shall the authors or copyright holders be liable for any claim, damages or other liability.