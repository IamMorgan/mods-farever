## Codex Loot

Shows the **complete drop list** of every monster in the Farever Codex, with the **drop chance** on each item, separate blocks for **heroic mode** loot and **equipment (world loot)**, a **search by loot name** in the Codex monster list, and **Boss / Elite / Spark** tags. A new **Chests tab** lists every chest item of the game (Hero Weapon Cache, Chaotic Gear Cache...) with where to buy it, what is inside and the chance of each item.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings
- Copy the `hlx` folder from the archive into the Farever game folder

### Main features

- **Chests tab:** the Codex window has two tabs under it: **Codex** (the game's own Codex, opened by default) and **Chests**. The Chests page looks like the Monsters page: the list of chests on the left (hover a chest for its name and description), in the middle what the chest is, **where to get it** (the merchant, the towns, the price), how it opens and its **contents with the chance of each item**, on the right a picture of the chest. All chest items are listed: Hero Weapon / Gear Cache, Chaotic (Demonic) Gear / Weapon / Gift Cache, Mysterious Cache... World chests (part of the map) and dungeon reward chests are not items and are not listed. The list is read from the game's data, so chests added by a game update appear by themselves.
- **Search in the Chests tab:** the field above the chest list filters the chests by the name of an item they can contain, letter by letter, **in English and in Russian** whatever the client's language; the matching items are highlighted in the contents.

- **Full loot list:** Open *Esc > Codex > Monsters* and pick a monster. Under *Trophies* the window lists every item the monster can drop, not only the items the Codex already knows about. The added items are normal Codex buttons: hover an item for the game's own tooltip.
- **Drop chance on every item:** The chance is written in percent on the lower edge of each icon (for example `40%`, `3.5%`, `0.1%`), in white with a black outline so it stays readable on any icon.
- **Equipment (world loot):** Most monsters can also drop equipment that is not in their loot tables: the game picks a random item from the world loot of the monster's level. A separate block *Equipment (world loot)* (*Экипировка (мировой лут)*) lists that pool. When a monster's loot table asks for world loot (for example 1% for many monsters, 100% for unique ones) the chance of each item is shown; for monsters whose data has no such entry the server decides, so those items show **?**.
- **Search by loot:** The Codex monster search also finds monsters by their loot. Type part of an item's name in the client's language and the list keeps only the monsters that can drop it (or whose own name matches). It works letter by letter, like the game's search, and uses the item names exactly as the game shows them. Can be turned off in the settings.
- **Heroic mode loot:** Monsters with a heroic loot table (dungeon bosses) get a separate block under the caption *Heroic mode* (*Героический режим* in a Russian client). Its chances are orange.
- **No rank lock:** The Codex normally hides the loot of a monster until its Codex rank is high enough. The mod shows the loot panel for every monster.
- **Boss / Elite / Spark tags:** In the monster list every Boss, Elite and Spark monster gets its tag on the lower edge of its frame: **Boss** (red), **Elite** (gold), **Spark** (blue).
- **Spawn point and kill rewards included:** Loot tables of spawn points (which replace a monster's own tables), the items and tables given for the kill (the monster's *gains*) and faction loot are taken into account. Faction loot currently has a drop chance of 0 for monsters in the game's data, so it appears only if the game changes that.
- **In your language:** The settings page, the captions and the tags follow the client's language (English or Russian). Texts drawn on the Codex window fall back to English when the window's font has no Cyrillic letters.
- **Works with new content:** The mod does not contain any monster or item lists. It reads the loot tables, monsters, items, spawn points and flags from the game's own data, so monsters and items added by a game update are included automatically.

### Settings (Esc > Mod Settings > Codex Loot)

| Setting | Default | Meaning |
| --- | --- | --- |
| Enabled | on | Turns the whole mod on or off. |
| Boss / Elite / Spark tags in the monster list | on | Shows or hides the tags in the monster list. |
| Chests tab in the Codex | on | Adds the Chests tab (and the tab bar under the Codex window). |
| Search finds monsters by the name of their loot | on | The Codex search also keeps monsters that can drop an item whose name contains the text. |
| Hide loot limited to other monster levels | off | Off: show all loot of the monster. On: hide entries the game would not drop at the monster's level. |
| Max extra items | 200 | Upper bound for the number of icons the mod adds to the window (most likely drops first), 10-500. |

### How the chance is calculated

The mod follows the game's own loot rules:
- The tables used are the monster's own loot table and the loot table of its monster type; unique and elite monsters also use the game's unique/elite tables; bosses use their boss table, and heroic mode uses the heroic table.
- A loot table with the weight flag picks one entry by weight (chance = entry weight / total weight). Any other table rolls every entry on its own (chance = the entry's `proba`). Entries that point to another table multiply their chances.
- Counts: an entry drops a random amount between its minimum and maximum. An entry whose minimum is 0 can drop nothing; the mod counts only the rolls that give at least one item (for example 0-1 halves the chance). Level-scaled amounts use the monster's level.
- An entry that points to a weighted table with an amount of N makes the game pick from that table N times, so its items get the chance of at least one hit in N picks.
- Faction loot: on every kill the game drops, with the chance `Const.Items.Loot_FactionDropRate.Foes`, one rare item of the monster's faction, weapons and gear weighted by `Loot_FactionDropWeight`. The mod uses the game's own faction table (`HItem.getFactionLootTable`), so its chance is that drop rate times the item's weight share.
- World loot: the pool is every item with the game's world loot flag that is not a recipe and whose level lies in the monster's level + `Const.Items.WorldLootLevel` (the level counts up to 20), `WorldLootWithAffinity` limits it to items of your class, `WorldLoot` uses all classes. One item of the pool is picked, so a known world loot chance is shared by the pool.
- Spawn points: a spawn point's override table replaces all tables of the monsters it spawns; a monster met at several spawn points shows each item with its best chance.
- Gains: tables and items in the monster's `gains` are given on every kill and are added like its own loot table.
- Entries meant for another kind of monster are skipped: an entry's condition is a set of bits (1 normal, 2 elite/unique/boss) and must include the monster's bit. If the same item can drop from several places, the chances are combined.
- The percentage is the chance for one kill under normal conditions. Player reputation, activity difficulty and luck are not applied.
- Monster classes come from the monster's own flags, looked up by name in the game's data: **Boss** = `Boss`, **Spark** = `Spark`, **Elite** = `Elite` or `Unique`.

### How the chests work

- A chest is an item with an *open* action in the game's data. Opening it rolls its loot table at a level (your level, kept inside the chest's level range; without a range the item's level), offers up to *max items* of the rolled items and lets you keep one (mode *Chose*); a chest with a weighted table (the Chaotic Gift Cache) gives one random item.
- Chests whose table is limited to your class (*WithAffinity*) show the items for the class of the hero you play. The chance is the chance to be among the offered items: with 12 possible items and 2 offered it is 2 / 12 = 17%. Items you already own are put last by the game, which the mod does not take into account.
- **Complete contents:** a chest limited to your class offers only the items of your class, but the list shows the items of every class. The ones you can be offered have a full colour; the items of other classes are dimmed and show the chance they have for a hero of their class.
- Who sells a chest is not in the game's data (it is in the shop lists of the hub NPCs), so it is written down in `sellers.json` (data file, no code): Hero Weapon / Gear Cache from the Glory merchant (100 Medals of Glory), the epic Chaotic Gear Cache (level 25) from Rumi (**100 Medals of Glory + 20 Nightblood**, both are paid), the Chaotic Gear / Weapon Cache (10 Nightblood) and Gift Cache (5 Nightblood) from Mira, in the hubs of the three regions. A chest that is not in the file says that the game's data does not tell where to get it.
- English and Russian names for the search come from the game's own files (the base data and `lang/export_ru.xml`).

### Notes

- The mod only changes the Codex window on your screen. It does not change loot, monsters or the game's data and sends nothing over the network.
- The mod writes nothing to the log and creates no files except its settings file and its settings page (`configFormats.json`, rewritten in the client's language).
- The mod hooks the Codex window (`setSelectedUnit`, `updateUnitNodes`, `matchSearch`), the loading of spawn points (`HSpawner.add`, `HSpawner.clear`) and the game's update loop (to follow the client's language), and reads the game's data sheets by name. If a game update renames these, the mod does nothing (it never crashes the game) until it is updated.

### Changelog

#### 1.2.2

- **Chest contents are complete for every level:** a chest's list now holds every item it can give at any hero level of its level range (rows with a minimum / maximum level are followed), not only the ones for the level of your hero. Items you are not offered now (another class or another level) are dimmed and show the chance they have for a hero who can get them.
- **Rarity of the items:** the items of a chest are shown with the rarity the chest gives, not the rarity of the item in the data. The weapons of the Hero Weapon Cache are **Epic** (purple frame, Epic tooltip) instead of Rare.
- **No chest is written in the code:** the chests, their contents and their rarity come from the game's data. The only thing the data lacks, who sells a chest and for what, is read from the file `sellers.json` next to the mod (a list of `{item, unit, hubs, costs}` with ids of the game's data); a chest that is not in the file is still listed with its complete contents, and a new chest of a game update appears by itself.
- The dimmed-items note and the text for a chest of unknown origin say what they mean.

#### 1.2.1

- **Chests tab fixes:**
  - the price of the epic *Chaotic Gear Cache* (Rumi) is now complete: 100 Medals of Glory **and** 20 Nightblood (only the Medals were shown);
  - *Sold by*, *Where* and *Price* are written in bold;
  - the chest you pick in the list gets a gold frame;
  - the item tooltips are drawn over the *Codex* / *Chests* tabs, not under them;
  - the tabs touch the window without a gap;
  - the complete contents of every chest are listed: items of all classes (the Hero Weapon Cache showed only 2 weapons, the ones of your class, now all 4), the items of other classes are dimmed.

#### 1.2.0

- **New: Chests tab** in the Codex window (tabs *Codex* / *Chests* under the window; the Codex tab, the game's own Codex, is shown by default). Every chest item with where to get it, how it opens, its contents and the chance of each item, a picture of the chest, and a search by item name in English and Russian.
- The Boss / Elite / Spark tags and the captions on the Codex window now use the Cyrillic font of the Codex, so they are written in Russian in a Russian client (they were always English before).
- New setting *Chests tab in the Codex*.
- Test mode for development: the mod listens for commands only while the folder `hlx/config/codexloot/test` exists (it is not in the archive).

#### 1.1.0

- **Loot display fixed:**
  - the list now shows all loot the game can drop: spawn point loot tables (monsters without own tables now show their loot), kill rewards (*gains*) and a new block *Equipment (world loot)* with the equipment of the monster's level;
  - the icon grid no longer runs under the Codex panel's scroll bar;
  - Boss / Elite / Spark tags are read from the game's monster flags, so new monsters are tagged correctly;
  - *Max extra items* now defaults to 200 (up to 500), so large loot tables are no longer cut. A saved value of 60 (the old default) is raised to 200.
- **Drop chance fixed:** chances follow the game's roll step by step: entries that can roll an amount of 0, tables picked from several times, level-scaled amounts and the entries' monster conditions are taken into account. Very small chances are shown with three decimals (for example `0.012%`). The calculation is checked against a simulation of the game's own loot roll.
- **Search by loot in the Codex filter:** typing part of an item name in the Codex monster search keeps only the monsters that can drop that item. The search works letter by letter in the client's language, with the item names exactly as the game shows them.
- **Mod in the client's language:** the settings page, the block captions and the tags follow the client's language (English or Russian).

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

