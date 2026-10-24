## Dungeon Party Finder

Matchmaking for dungeons. Press **Search** in the game's own dungeon window and the mod puts you together with other players who look for the same dungeon on the same difficulty and are in the same level bracket, invites them into a group with the game's own group invitation, and the same window becomes the group's dungeon lobby.

### Installation instructions

Prefer the use of [Vortex](https://www.nexusmods.com/vortex) to install this mod.

For manual installation:
- Install the [hlx-core](https://www.nexusmods.com/site/mods/2118) modding tool
- Install [Better Mod Settings](https://www.nexusmods.com/farever/mods/10), which is used to control the mod's settings
- Copy the `hlx` folder from the archive into the Farever game folder

Other players need the mod too: it finds only players who use it.

### How it works

1. Click the **DPF** button and pick a dungeon from the list.
2. In the game's dungeon window choose a difficulty and press **Search** under **Start**.
3. While searching, a turning circle and *Searching... N/4* are shown; **Start** is off and **Search** has become **Cancel**.
4. As soon as a second player is found, the leader sends the game's group invitation; accept it in the invitation window. Later arrivals are invited as they come, until the group has four players.
5. The window is then the group's dungeon lobby: **Start** for the leader, **Ready** for the others.

### Features

- **DPF button:** a small plate in the look of the game's own buttons. An orange dot means a search is running, a green one that a group has formed.
- **Dungeon list:** every dungeon of the game with its level and name; ten rows are visible, the rest is reached with the mouse wheel or the scroll bar.
- **Dungeon window:** the game's own window with an added **Search** button. It can be moved by its title strip and stays where you leave it (also when it is opened again).
- **Matching:** only players with the **same dungeon**, the **same difficulty** and a level in the **same bracket**: 1-3, 4-7, 8-10, 11-14, 15-18, 19-20, 21-24, and the maximum level on its own.
- **Leader:** the player who started searching earliest leads and invites the others. An invitation that is declined or not answered within 30 seconds is replaced by the next searcher.
- **Short groups:** the leader can press **Cancel** to stop with fewer than four players and press **Search** again later to look for the missing places.
- **Group members** see that their leader is searching, with the size of the group (for example 2/4), in their own dungeon window.
- **Closing the dungeon window** does not end the search; the DPF button brings back the window of the searched dungeon.
- **Crown:** the group leader is marked with a small crown at the right edge of the character plate in the party list.
- **Language:** all windows and the settings page follow the client's language (the 14 languages of the game; English for any other).

### Settings (Esc > Mod Settings > Dungeon Party Finder)

- **Show the DPF button**
- **Unpin:** lets you move the button: hold the left mouse button on it and drag. A click without moving still opens the list. The position is saved.
- **Button size %**

### Notes

- The search runs on the platform's own lobbies through the game's multiplayer code (on Steam these are Steam lobbies); the mod has no server of its own. Lobbies carry only an id of the search, the search time and your account id (needed to invite you). A group leader that is still searching also keeps a small lobby of its own so that its members can see the search.
- The group is made with the game's group invitation, so the usual rules apply: someone who is already in a group, is inside a dungeon, ignores you, or accepts invitations from friends only will not join, and the leader invites someone else in their place.
- Players are ordered by their own computers' clocks, so the "earliest searcher" is exact to within the clocks' difference.
- You can start a search alone or as the leader of a group that is not full; members of someone else's group cannot search.

### Changelog

#### 2026-10-24 (1.1.0)

- The dungeon list and the DPF button are the game's own widgets; the dungeon window is the game's own with a **Search** button under **Start**.
- The invitation goes out as soon as a second searcher is found; later arrivals are invited as they come, and a declined invitation is replaced by the next searcher.
- After **Cancel** the leader of a short group keeps the **Search** button and can search again for the missing places.
- The counter counts the whole group, and the other members of the group see that their leader is searching.
- The dungeon window can be moved by its title strip and stays where you leave it; no flicker, the dungeon picture stays intact during a search.
- The crown of the group leader sits at the right edge of the character plate.
- Closing the dungeon window no longer ends the search.
- Texts and settings follow the client's language (14 languages).
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
