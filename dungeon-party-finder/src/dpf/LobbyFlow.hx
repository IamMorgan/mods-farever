package dpf;

import dpf.GameAccess as G;

/**
 * After a group has formed around the search: gets everyone into the one dungeon lobby of the group and in front of the
 * game's own dungeon window. The leader opens the lobby and keeps the difficulty the search was made for; the others join it.
 * A window that was open for a player's earlier, lone lobby is closed for the group's.
 */
class LobbyFlow {
    static inline var STEP = 1.0;
    static inline var RETRY = 3.0;

    var party:GameParty;
    var activityId = "";
    var difficulty = 0;
    var nextStep = 0.0;
    var nextCreate = 0.0;
    var nextDifficulty = 0.0;
    var done = false;

    public function new(party:GameParty) this.party = party;

    public function begin(activityId:String, difficulty:Int):Void {
        this.activityId = activityId;
        this.difficulty = difficulty;
        nextStep = 0;
        nextCreate = 0;
        nextDifficulty = 0;
        done = false;
    }

    public function end():Void {
        activityId = "";
        done = true;
    }

    function infoOf(lobby:Dynamic, player:Dynamic):Dynamic {
        try return G.call("st.player.InstanceLobby", "getPlayerInfo", lobby, [player]) catch (_:Dynamic) return null;
    }

    /** Once a second. */
    public function update(now:Float):Void {
        if (activityId == "" || done || now < nextStep) return;
        nextStep = now + STEP;
        try {
            var group = party.group();
            if (group == null) return;
            var lobby = DungeonScreens.groupLobby(party, activityId);
            if (lobby == null) {
                if (party.isLeader() && now >= nextCreate) { nextCreate = now + RETRY; askGroup(group); }
                return;
            }
            if (infoOf(lobby, party.me()) == null) {
                if (now >= nextCreate) { nextCreate = now + RETRY; askGroup(group); }
                return;
            }
            if (party.isLeader() && G.integer(G.field(lobby, "difficulty"), -1) != difficulty && now >= nextDifficulty) {
                nextDifficulty = now + RETRY;
                G.call("st.player.InstanceLobby", "setDifficulty", lobby, [difficulty, null]);
                return;
            }
            var screen = DungeonScreens.find();
            if (screen != null && DungeonScreens.lobbyOf(screen) != lobby) {
                DungeonScreens.close(screen);
                return;
            }
            DungeonScreens.show(lobby);
            done = true;
        } catch (error:Dynamic) trace("[DPF] lobby step failed: " + Std.string(error));
    }

    function askGroup(group:Dynamic):Void
        G.call("st.Group", "tryCreateInstanceLobby", group, [activityId, (_:Bool) -> {}]);
}
