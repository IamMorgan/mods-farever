## Dungeon Party Finder

Matchmaking for dungeons. A **DPF** button on the screen opens the list of dungeons; pick one, choose a difficulty in the game's own dungeon window and press **Search** under **Start**: the mod puts you together with other players who are looking for the same dungeon on the same difficulty and are in the same level bracket, invites them into a group with the game's own group invitation and then the same window is the group's dungeon lobby.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings
- Copy the `hlx` folder from the archive into the Farever game folder

Other players need the mod too: it finds only players who use it.

### Main features

- **DPF button:** a small plate in the look of the game's windows. A click opens the list of dungeons. While searching it carries an orange dot, once a group is formed a green one.
- **Dungeon list:** a window of the game itself, in the style of the Dungeon Button mod's list: every dungeon of the game as a row with its level and name. Ten rows are visible, the rest is reached with the mouse wheel or the scroll bar.
- **Dungeon window:** the game's own dungeon window (the one the portal opens). The mod adds a **Search** button under **Start**.
- **Searching:** a circle turns and *Searching...* is written above the buttons, **Start** is off and **Search** has become **Cancel**. Closing the dungeon window ends the search.
- **Matching:** you meet only players who chose the **same dungeon**, the **same difficulty** and whose level is in the **same bracket**: 1-3, 4-7, 8-10, 11-14, 15-18, 19-20, 21-24 and the maximum level on its own (level-25 players only meet level-25 players). The difficulties you cannot use (the maximum-level one below the maximum level, the heroic one before it is unlocked for this dungeon) are greyed out, by the game's own rules.
- **Leader:** the player who started searching earliest leads. As soon as a second player is found the leader sends the game's own group invitation (in-game, not a Steam invite) to the others. Accept it in the game's invitation window. Whoever declines or does not answer within 30 seconds is set aside and the leader invites the next searcher who arrives, until the group is full of four. The leader can press **Cancel** to go on with fewer.
- **Dungeon lobby:** after you are grouped everyone gets the group's dungeon window of the game, with its usual **Start** (leader) and **Ready** (the others).
- **Crown:** the group leader is marked with a small crown in the list of party members on the left of the screen.
- **Language:** the windows and the settings page follow the client's language (all 14 languages of the game; English for any other).

### Settings (Esc > Mod Settings > Dungeon Party Finder)

- **Show the DPF button**
- **Unpin:** lets you move the button: hold the left mouse button on it and drag. A click without moving still opens the list. The position is saved.
- **Button size %**

### Notes

- The search runs on the platform's own lobbies through the game's multiplayer code (on Steam these are Steam lobbies); the mod has no server of its own. Lobbies carry only an id of the search, the search time and your account id (needed to invite you).
- The group is made with the game's group invitation, so the usual rules apply: someone who is already in a group, is inside a dungeon, ignores you, or accepts invitations from friends only will not join, and the leader invites someone else in their place.
- Players are ordered by their own computers' clocks, so the "earliest searcher" is exact to within the clocks' difference.
- You cannot search while you are in a group with other players.

### Changelog

#### 2026-10-24 (1.1.0)

- The dungeon list is a window of the game itself (like the Dungeon Button mod's), with all dungeons and a scroll bar for the rows beyond the first ten.
- The dungeon window is the game's own; the mod adds a **Search** button under **Start**, which is off while a search runs. The turning circle of the search now turns.
- The invitation goes out as soon as a second searcher is found (it used to wait for a full group); later arrivals are invited as they come.
- After **Cancel** the leader of a group that is still short of players keeps the **Search** button and can search again for the missing places.
- A declined or ignored group invitation is replaced by the next searcher; the search goes on until the group is full.
- The mod's texts and settings page follow the client's language, whichever of the game's 14 it is. A click on a dungeon opens its window (the group is read from the hero's player, as the game's own dungeon buttons do), the list's scroll bar is the flow's own and shows itself.
- The DPF button is one of the game's own buttons (as in the Esc menu). The list has a visible scroll bar.
- Closing the dungeon window no longer ends the search; the DPF button, while a search runs, opens the window of the searched dungeon again.
- While a search runs the window keeps its height (the turning circle no longer resizes the bottom of the window), and the mod loads a dungeon's picture again if the game has dropped its texture.
- The settings "players needed to start" and "write a log" are gone.
- First version: the DPF button, the dungeon list, matching by dungeon, difficulty and level bracket, group invitations and the crown of the group leader.

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
