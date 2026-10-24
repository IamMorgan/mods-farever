## Dungeon Party Finder

Matchmaking for dungeons. A **DPF** button on the screen opens the list of dungeons; pick one, choose a difficulty and press **Search**: the mod puts you together with other players who are looking for the same dungeon on the same difficulty and are in the same level bracket, invites them into a group with the game's own group invitation and then turns into the dungeon lobby.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings
- Copy the `hlx` folder from the archive into the Farever game folder

Other players need the mod too: it finds only players who use it.

### Main features

- **DPF button:** a small plate in the look of the game's windows. A click opens the list of dungeons. While searching it carries an orange dot, once a group is formed a green one.
- **Dungeon list:** every dungeon of the game with its name and level, in the style of the game's dialogs (the mouse wheel scrolls it). Dungeons above your level are dimmed.
- **Dungeon window:** looks like the game's own dungeon dialog: the dungeon's picture and description, the three difficulty buttons, the required level and your hero's card. The big button is **Search** instead of "Start".
- **Searching:** a circle turns and *Searching...* is written above the button, which has become **Cancel**. The window may be closed meanwhile: the search goes on and the DPF button shows it.
- **Matching:** you meet only players who chose the **same dungeon**, the **same difficulty** and whose level is in the **same bracket**: 1-3, 4-7, 8-10, 11-14, 15-18, 19-20, 21-24 and the maximum level on its own (level-25 players only meet level-25 players). The difficulties you cannot use (the maximum-level one below the maximum level, the heroic one before it is unlocked for this dungeon) are greyed out, by the game's own rules.
- **Leader:** the player who started searching earliest leads. When four players are found (or, with fewer, after a short quiet time, see the settings) the leader sends the game's own group invitation (in-game, not a Steam invite) to the others. Accept it in the game's invitation window. Whoever declines or does not answer within 30 seconds is set aside and the leader invites the next searcher who arrives, until the group is full.
- **Dungeon lobby:** after you are grouped the same window shows the group's cards and the button turns into **Start** (leader, active once everyone is ready) or **Ready** (the others) and works like the buttons of the game's own dialog.
- **Crown:** the group leader is marked with a small crown in the list of party members on the left of the screen.
- **Language:** the windows and the settings page follow the client's language (English or Russian).

### Settings (Esc > Mod Settings > Dungeon Party Finder)

- **Show the DPF button**
- **Unpin:** lets you move the button: hold the left mouse button on it and drag. A click without moving still opens the list. The position is saved.
- **Button size %**
- **Players needed to start:** 4 (a full group) by default. With 2 or 3 the leader starts the group once the lobby has been quiet for a few seconds.
- **Write a log to hlx/dpf-debug.txt:** for bug reports.

### Notes

- The search runs on the platform's own lobbies through the game's multiplayer code (on Steam these are Steam lobbies); the mod has no server of its own. Lobbies carry only an id of the search, the search time and your account id (needed to invite you).
- The group is made with the game's group invitation, so the usual rules apply: someone who is already in a group, is inside a dungeon, ignores you, or accepts invitations from friends only will not join, and the leader invites someone else in their place.
- Players are ordered by their own computers' clocks, so the "earliest searcher" is exact to within the clocks' difference.
- You cannot search while you are in a group with other players.

### Changelog

#### 2026-10-24 (1.0.0)

- Group invitations: a declined or ignored invitation is replaced by the next searcher instead of being retried.
- First version: the DPF button, the dungeon list, the dungeon window with difficulty choice and search, matching by dungeon, difficulty and level bracket, group invitations, the dungeon lobby (Start / Ready) and the crown of the group leader.

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
