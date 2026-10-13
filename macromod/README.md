[size=4][b]Farever Macros[/b][/size]
Chain key presses with delays into macros and start them with one hotkey. Three independent macros, up to ten steps each, all configurable from the in-game mod settings.

[size=3][b]Installation instructions[/b][/size]
Prefer the use of [url=https://www.nexusmods.com/vortex]Vortex[/url] to install this mod.

For manual installation:
[list]
[*]Install the [url=https://www.nexusmods.com/site/mods/2118]hlx-core[/url] modding tool
[*]Install [url=https://www.nexusmods.com/farever/mods/10]Better Mod Settings[/url], which is used to control the mod's settings
[/list]

[size=3][b]Main features[/b][/size]
[list]
[*][b]Three independent macros:[/b] Each macro has its own name, activation key, mode and up to ten steps. All three can run at the same time.
[*][b]Steps with delays:[/b] Every step is a key plus the delay (60-5000 ms) before the next step. Empty steps are skipped. The minimum delay is 60 ms so every key press is registered by the game.
[*][b]Press (Toggle) or Hold:[/b] In Toggle mode press the activation key to start the macro and press it again to stop. In Hold mode the macro runs only while the key is held down.
[*][b]Repeat in loop:[/b] Run the steps once, or loop them until you stop the macro.
[*][b]Hotkey modifiers:[/b] Activation keys accept Ctrl, Shift or Alt combinations, with Farever's strict matching: Ctrl+1 does not also trigger a plain 1.
[*][b]Clear buttons:[/b] A small red X next to every key button resets the key to "Not set" and updates the button right away. Right-clicking a key button works too.
[*][b]Background hotkeys (optional):[/b] The setting "Work when the game window is not focused" reads your activation keys from Windows, so hotkeys are still detected while another window is in front.
[*][b]Better Mod Settings integration:[/b] Press Esc to open the Game Menu and choose "Mod Settings" > "Farever Macros" to see all settings.
[/list]

[size=3][b]Quick start[/b][/size]
[list=1]
[*]Open Esc > Mod Settings > Farever Macros.
[*]Under "M1 Activation Key" click the key button and press the key (or a combination) that should start the macro.
[*]Pick the mode: Press (Toggle) or Hold. Tick "Repeat in loop" if the macro should keep going.
[*]Set "Step 1 Key" and "Step 1 Delay (ms)", then the next steps. Leave unused steps at "Not set".
[*]Close the settings and press the activation key in game.
[/list]

[size=3][b]Notes[/b][/size]
[list]
[*]Macros send key presses to Farever's own key input, the same way the keyboard does. They do nothing outside the game.
[*]Background hotkeys use a small native plugin ([i]macro_keys.hdll[/i], included, Windows x64 only). It only answers whether a key is down right now: it installs no hook and records nothing. If the file is missing or blocked by your antivirus, hotkeys simply work only while the game window is in focus.
[*]Macros run inside the game's own update loop, so they keep running in the background only as long as Farever itself keeps updating while it is not in focus.
[/list]