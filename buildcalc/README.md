## Farever Build Calculator (buildcalc)

A build calculator for Farever. It adds a **"Calculator"** tab to the Hero Profile window: you set your priorities (damage, defense, health, healing) and the combat type, and the mod picks equipment, talents, skills with runes and infusions, then shows the stats of the resulting build. The mod does not equip anything, does not change anything in the game and sends nothing to the server: it is a recommendation only.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool.
- Copy `buildcalc.hl` to `hlx/mods/buildcalc/` in the game folder.

### Main features

- **Priorities:** for damage, defense, health and healing choose High, Medium, Low or Not important. Only one stat can be High and at most two can be Medium.
- **Criticality:** a checkbox under the damage priority. When it is on, the chance of a critical strike counts in the build as well (as much as the damage priority, at least Low). With High damage the build is made to reach the highest critical strike chance the items, augments, infusions and talents allow.
- **Combat type:** melee or ranged. It decides which main weapons are considered.
- **Build search:** main and arsenal weapon, shield, armor, jewelry, trinket, augment slots, infusions (sets of 4 items), talents, class skills and runes. The game's rules are respected: a shield works only with a one-handed weapon, only four class skills can be used (the class's signature skill, such as the priest's Divine Intervention, is always there), weapons with no weapon skills (the capture net) are never offered, the arsenal weapon gives 40% of its stats, and only items you can actually get (dropped, crafted or already owned) at your hero's level are used.
- **Combat simulation:** every build is valued by a combat simulator that runs on the game's own data: skills, statuses, combos, summons, passive effects of weapons, talents and infusions. Damage and healing (to yourself and to allies) are shown per second.
- **Result:** the *Result* button under *Calculate* brings back the last calculation in full: the build, talents, skills, stats and the settings it was calculated with. It becomes active after the first calculation. Switching between the result and the templates never erases anything.
- **Templates:** three slots for builds.
  - A template button only chooses the slot; the window does not switch.
  - *Show* opens the chosen template.
  - *Save* writes the last result into the chosen slot. To save: open *Result*, choose a template, press *Save*.
  - *Reset* (confirmed by a second click) clears a slot.
- **Item tooltips:** items in the calculator use the game's own tooltips; for the arsenal weapon the tooltip takes the arsenal's share of stats into account.
- **Language:** the interface follows the client's language (English, German, French, Russian, Simplified and Traditional Chinese, Portuguese, Polish, Turkish, Spanish, Italian, Korean, Japanese, Czech).

### Quick start

1. Open the hero profile and go to the *Calculator* tab.
2. Choose the priorities and the combat type.
3. Press *Calculate* and wait for the calculation to finish (the first one takes about a minute, progress is shown in the status line).
4. Look at the build, talents, skills and stats; the recommended infusions are listed under the questionnaire.
5. To save a build: *Result* > the template button > *Save*. To open a saved template: the template button > *Show*.

### Notes

- The calculation runs in a thread of its own in small portions, so the game should not stutter. Buttons are locked while it runs.
- Weapon magic formulas (`Enchant_*` skills) are not part of the calculation: neither in the start build nor in the result. Formulas for hands and feet (they give stats) are counted.
- The last result lives until the game is restarted; saved templates and the questionnaire are kept in `hlx/config/buildcalc/state.json`.
- Templates saved by older versions of the mod have no stats of their own: save them again from a result.
- Talents: the talents you wear (or those of the last result) are replaced only when the talents found gain at least 10% of the score unit (the sum of the priority weights). Smaller gains are within the model's error.
- The simulator is not an exact copy of the game. Its damage values were checked against real fights on a training dummy; absolute numbers can differ from real ones, comparing builds with each other is more reliable.

### Changelog

**2026-10-24**
- The same weapon is never chosen as both the main and the arsenal weapon; Infusions are chosen by the effects of their sets, not by item factions (the bonus attribute that works only on items of the infusion's faction adds nothing to the value); with Criticality on and High damage the chance of a critical strike weighs a quarter of the damage (it was three times as much, which cost 19% damage; at equal weight healing fell to nothing); A High priority now weighs three times a Medium one (it used to be outweighed: with High damage and Medium healing the infusions went to healing); Criticality checkbox under the damage priority; a High priority is kept (at least 97% of the worn build's value) instead of being traded for lower ones, and the search never ends below the worn build; no twin of a worn item or ranged/melee mix-up is offered as "improve"; runes follow the prioritized axes; the model fight is two minutes against a pack of three foes that die every 20 s, hit the hero and are blocked (kill, block, enemy-count and low-target-health conditions hold, shields count by what they take in); many skills, talents and infusions that were valued wrongly or not at all now work (rogue poison blast, Opportunity Strike and Urge to Kill, warrior bleed and Battle Shout, mage Chaincast, Nova's ultimate, recasts, water spheres, totems, cast multipliers, filled weapon skill slots); after a calculation the window also tells how many builds were checked and how many fights were simulated; effects that count per stack (Demon axe and Demon halos stacks, Manfish Tank heal, Bee poison), heals when stacks are consumed (Benediction mace), statuses a unit puts on itself being heard (Hold the Line, Manfish Tank shield and its burst), shields being heard (Water Orbs passive), cooldown recovery (Mystic Empowerment rune), the ranged-attack flag (Thrown Seeds) and the Sword Craft passive's range now work; the chosen build is checked against the game's rules (arsenal skills, talents, class skills, runes, infusions, duplicate items); the fight simulation is about a third faster (no per-block copies in the script interpreter, an event heap, cached hit data) and the search no longer rests while the game runs smoothly, so a calculation takes noticeably less time with the same two-minute fight.

**2026-10-19**
- Class skills: at most 4 class skills are chosen; the class's signature skill is fixed and not counted (before, 5 class skills could be offered, which inflated the damage estimate).
- Weapons without weapon skills (the capture net) are no longer offered as main or arsenal weapons.
- An off-hand item that does not work with the main weapon (a shield with a two-handed weapon) is removed from the result; after the main weapon changes the off-hand is chosen again.
- Saved templates keep their own stats and totals after a game restart (the loader used to drop them, so templates showed the current stats).
- Talents: the start's talents stay unless the found ones gain at least 10% of the score unit.
- Release builds log errors only; the development log and the test mode are off.

**Earlier**
- Main weapon swap refills the off-hand (a shield needs a one-handed weapon).
- *Result*, *Show* and *Save* buttons; the last result is kept until the game restarts.
- Weapon magic formulas and the fight log were removed; summons, rank passives and level-aware item sources were added.
- English README.

### For developers

- Sources are in `src/`; build with `haxe compile.hxml` (needs Haxe and hlx-runtime); output: `build/buildcalc/buildcalc.hl`.
- Release build (only errors are logged, test mode is off): `haxe compile.hxml -D release`.
- Development log: `hlx/buildcalc-debug.txt` in the game folder.

### LICENSE

CC BY-NC 4.0, see [LICENSE](LICENSE).
