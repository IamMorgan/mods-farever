## Farever Macros

Chain your action-bar skills with delays into macros and start them with one hotkey. Three independent macros, up to ten steps each, all configurable from the in-game mod settings.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings

### Main features

- **Three independent macros:** Each macro has its own name, activation key, mode and up to ten steps. All three can run at the same time.
- **Skills picked from a panel:** Click *Choose* under a step and pick the skill from a panel of your action-bar icons (weapon skills and class skills). The step shows the skill's name in your client's language; the small red X next to it clears the step.
- **Steps with delays:** Every step is a skill plus the delay (60-5000 ms) before the next step. Empty steps are skipped. Skills are used the same way as pressing their key: the next step starts after its delay, once the previous skill has been used and finished casting. Skills still on cooldown are skipped. Mount, dash and block are not offered.
- **AoE skills:** Ground-aimed skills are activated twice (aim, then confirm at the mouse), or, with *AoE skills aim at the nearest enemy* on, land straight on the nearest enemy within the skill's range.
- **Press (Toggle) or Hold:** In Toggle mode press the activation key to start the macro and press it again to stop. In Hold mode the macro runs only while the key is held down.
- **Active only in combat (optional):** With this setting on, the activation key still starts and stops a macro at any time, but a started macro plays only while your character is in combat. When the fight ends it waits (it is not stopped), and in the next fight it plays again from its first step.
- **Settings in your language:** The settings page follows the client's language (English or Russian).
- **Rotations:** the *Rotations* button in *General* opens a window with your rotations. *New* adds a rotation at the top of the list: ten cells with a "+" between them. Click a cell to pick a skill (the same panel as for macro steps; right-click or the small red X clears a cell). Under the cells: *Repeat*, the activation key (click it, then press the key or a combination such as Ctrl+1; Esc cancels, the red X clears it) and the press type (*Press (Toggle)*: press to start, press again to stop; *Hold*: runs while the key is held). A rotation uses its skills in turn and has no delays: each skill is used as soon as it is ready. A skill on cooldown holds the rotation back - the next skill is not used before it. Without *Repeat* the rotation plays once, with it the rotation goes round and round. Empty cells are skipped. One key can start only one rotation (or macro); the window refuses a key that is taken. Rotations are saved on their own and follow the *General* options *Active only in combat*, *Don't use while running* and *AoE skills aim at the nearest enemy*.
- **Repeat in loop:** Run the steps once, or loop them until you stop the macro.
- **Hotkey modifiers:** Activation keys accept Ctrl, Shift or Alt combinations, with Farever's strict matching: Ctrl+1 does not also trigger a plain 1.
- **Clear buttons:** A small red X next to every key button resets the key to "Not set" and updates the button right away. Right-clicking a key button works too.
- **Background hotkeys (optional):** The setting "Work when the game window is not focused" reads your activation keys from Windows, so hotkeys are still detected while another window is in front.
- **Better Mod Settings integration:** Press Esc to open the Game Menu and choose "Mod Settings" > "Farever Macros" to see all settings.

### Quick start

1. Open Esc > Mod Settings > Farever Macros.
2. Under "M1 Activation Key" click the key button and press the key (or a combination) that should start the macro.
3. Pick the mode: Press (Toggle) or Hold. Tick "Repeat in loop" if the macro should keep going.
4. Under "M1 Step 1" click *Choose* and click a skill icon, then set "M1 Step 1 Delay (ms)". Do the same for the next steps; leave unused steps empty.
5. Optional: under "General" tick *Active only in combat* if macros should play only during fights.
6. Close the settings and press the activation key in game.

### Notes

- In a Russian client the settings rows are named in Russian (for example *М1: шаг 1* instead of *M1 Step 1*). Switching the game language keeps all saved macros.
- *Active only in combat* uses the game's own in-combat state of your character.
- Macros request skills through Farever's own skill input, the same way a skill key does. They do nothing outside the game.
- Background hotkeys use a small native plugin (*macro_keys.hdll*, included, Windows x64 only). It only answers whether a key is down right now: it installs no hook and records nothing. If the file is missing or blocked by your antivirus, hotkeys simply work only while the game window is in focus.
- Macros run inside the game's own update loop, so they keep running in the background only as long as Farever itself keeps updating while it is not in focus.
- Skills that must be held down are stopped by the game right after they start, because their key isn't physically held.

### Changelog

#### 1.3.1

- **Per character:** macros and rotations are saved separately for every character; a macro made on one character does not appear on another. The first character to log in takes over the macros and rotations saved before.

#### 1.3.0

- **Rotations:** a new window (button *Rotations* in *General*) for skill rotations. Each rotation is ten cells; its skills are used in turn, each as soon as it is ready (no delays), and the next skill waits for a skill that is on cooldown. *Repeat* loops the rotation, otherwise it plays once. Own activation key (one rotation per key) and press type (Toggle / Hold) per rotation. The window is drawn by the mod itself and follows the client's language (English or Russian). Macros and rotations are saved per character: `hlx/config/macromod/macros_<uid>_<name>.json` and `rotations_<uid>_<name>.json` (the first character to log in takes over the older shared data).
- **Combos:** basic attacks work in rotations as combos. The rotation presses the Attack key, so the game picks the next hit of the combo itself.
- **No cancelled skills:** the next skill of a rotation waits until the game has started the requested one and the hero has finished the current one.
- The skills of the action bars are now re-read while you play (every two seconds), not only while the settings page is open, so ground-aimed skills always confirm with the right key.

#### 1.2.2

- **Active only in combat:** a new option in *General*. When it is on, a started macro plays only while your character is in combat: out of combat it waits, and each new fight it plays again from its first step. The activation key starts and stops it as usual. Off: macros work as before.
- **Settings in your language:** the settings page and the skill picker are shown in the client's language (English or Russian). Saved macros, keys and modes are kept when the language changes.

#### 1.2.1

- **Steps are skills, not keys:** each step uses a skill instead of simulating a key press. Skills are requested through Farever's own skill input, so the game handles auto-target, checks and its short request queue exactly as for a real key press.
- **Skill picker:** the new *Choose* button under every step opens a panel with the icons of your action-bar skills (weapon skills on the first row, class skills on the second). Hover an icon for the skill's name; click outside the panel, *Cancel* or Esc to close it. Mount, dash and block are not offered.
- **Skill names in your language:** a step shows the skill's name in the client's language. Steps saved by older versions as skill ids are switched to names automatically.
- **Red X for steps:** a small red X next to every step's skill name clears the step.
- **AoE skills:** ground-aimed skills are activated twice (aim, then confirm at the mouse position). With *AoE skills aim at the nearest enemy* on, they land straight on the nearest enemy (the same target a normal skill picks), within the skill's range.
- **Reliable sequencing:** the next step starts after its delay once the previous skill has been used and finished casting; skills still on cooldown are skipped instead of holding the macro up.
- **Independent macros:** each macro keeps its own progress, so one macro waiting for its skill never holds up another.
- **Settings:** step rows are now named *M1 Step 1*, *M2 Step 1*... so every row is unique.


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