## Codex Loot

Shows the **complete drop list** of every monster in the Farever Codex, with the **drop chance** on each item, a separate block for **heroic mode** loot, and **Boss / Elite / Spark** tags in the monster list.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings
- Copy the `hlx` folder from the archive into the Farever game folder

### Main features

- **Full loot list:** Open *Esc > Codex > Monsters* and pick a monster. Under *Trophies* the window lists every item the monster can drop, not only the items the Codex already knows about. The added items are normal Codex buttons: hover an item for the game's own tooltip.
- **Drop chance on every item:** The chance is written in percent on the lower edge of each icon (for example `40%`, `3.5%`, `0.1%`), in white with a black outline so it stays readable on any icon.
- **Heroic mode loot:** Monsters with a heroic loot table (dungeon bosses) get a separate block under the caption *Heroic mode* (*Героический режим* in a Russian client). Its chances are orange.
- **No rank lock:** The Codex normally hides the loot of a monster until its Codex rank is high enough. The mod shows the loot panel for every monster.
- **Boss / Elite / Spark tags:** In the monster list every Boss, Elite and Spark monster gets its tag on the lower edge of its frame: **Boss** (red), **Elite** (gold), **Spark** (blue).
- **Works with new content:** The mod does not contain any monster or item lists. It reads the loot tables, monsters and items from the game's own data when you open the Codex, so monsters and items added by a game update are included automatically.

### Settings (Esc > Mod Settings > Codex Loot)

| Setting | Default | Meaning |
| --- | --- | --- |
| Enabled | on | Turns the whole mod on or off. |
| Boss / Elite / Spark tags in the monster list | on | Shows or hides the tags in the monster list. |
| Hide loot limited to other monster levels | off | Off: show all loot of the monster. On: hide entries the game would not drop at the monster's level. |
| Max extra items | 60 | Upper bound for the number of icons the mod adds to the window (most likely drops first). |

### How the chance is calculated

The mod follows the game's own loot rules:
- The tables used are the monster's own loot table and the loot table of its monster type; unique and elite monsters also use the game's unique/elite tables; bosses use their boss table, and heroic mode uses the heroic table.
- A loot table with the weight flag picks one entry by weight (chance = entry weight / total weight). Any other table rolls every entry on its own (chance = the entry's `proba`). Entries that point to another table multiply their chances.
- Entries meant for another kind of monster (the entry's condition value differs from the monster's) are skipped. If the same item can drop from several places, the chances are combined.
- The percentage is the chance for one kill under normal conditions. Player reputation, activity difficulty and luck are not applied.
- Monster classes: **Boss** = the monster has the game's boss flag, **Elite** = elite or unique flag, **Spark** = the monster id or type is a Spark variant.

### Notes

- The mod only changes the Codex window on your screen. It does not change loot, monsters or the game's data and sends nothing over the network.
- The mod writes nothing to the log and creates no files except its settings file.
- The mod hooks two Codex window functions (`setSelectedUnit` and `updateUnitNodes`) and reads the game's data sheets by name. If a game update renames these, the mod does nothing (it never crashes the game) until it is updated.


LICENSE

Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)

Copyright (c) 2026 IamMorgan

You are free to:
* Share — copy and redistribute the material in any medium or format.
* Adapt — remix, transform, and build upon the material.

Under the following terms:
* Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
* NonCommercial — You may not use the material for commercial purposes (including selling it, or using it in any other software that is sold for money).

The software is provided "as is", without warranty of any kind, express or implied. In no event shall the authors or copyright holders be liable for any claim, damages or other liability.

