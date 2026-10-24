package dpf;

import dpf.GameAccess as G;

/**
 * The game's own dungeon window (ui.win.element.InstanceSelectScreen) and the dungeon lobby (st.player.InstanceLobby) it
 * shows. The portal opens it by asking the player's group for a lobby of the dungeon and showing the result; this does the
 * same without the portal, the way the Dungeon Button mod does.
 */
class DungeonScreens {
    public static inline var TYPE = "ui.win.element.InstanceSelectScreen";

    /** The running GameApp (refreshed every frame by the mod). */
    public static var app:Dynamic;

    public static function gui():Dynamic return G.field(app, "gui");

    /** The open dungeon window, if there is one. */
    public static function find():Dynamic {
        var gui = gui();
        if (gui == null) return null;
        for (w in G.array(G.field(gui, "windows"))) {
            if (w != null && G.isA(w, TYPE) && G.field(w, "parent") != null && G.field(w, "removed") != true) return w;
        }
        return null;
    }

    public static function lobbyOf(screen:Dynamic):Dynamic return G.field(screen, "instanceLobby");

    public static function activityOf(screen:Dynamic):String return G.text(G.field(lobbyOf(screen), "activityId"));

    /** The lobby of the group for the dungeon, or null while there is none. */
    public static function groupLobby(party:GameParty, activityId:String):Dynamic {
        var group = party.group();
        if (group == null || activityId == "") return null;
        try return G.call("st.Group", "getInstanceLobby", group, [activityId]) catch (_:Dynamic) return null;
    }

    public static function isDungeon(activityId:String):Bool {
        try {
            var inf = G.staticCall("HActivity", "getInf", [activityId]);
            return inf != null && G.staticCall("HActivity", "isDungeon", [inf]) == true && G.staticCall("HActivity", "isRift", [inf]) != true;
        } catch (_:Dynamic) return false;
    }

    public static function close(screen:Dynamic):Void {
        var gui = gui();
        if (screen == null || gui == null) return;
        try G.call("ui.BaseUI", "closeWindow", gui, [screen, null]) catch (_:Dynamic) {}
    }

    /** Shows the dungeon window of a lobby (a window for the same lobby is not opened twice). */
    public static function show(lobby:Dynamic):Void {
        if (lobby == null) return;
        var open = find();
        if (open != null && lobbyOf(open) == lobby) return;
        G.create(TYPE, [lobby, null, null]);
    }

    /**
     * Asks the group for the dungeon's lobby (the leader makes it, the others join it) and shows the window once the game
     * has answered; `ready` runs just before the window is shown, `failed` when it cannot be.
     */
    public static function open(party:GameParty, activityId:String, ready:Void -> Void, failed:Void -> Void):Void {
        var group = party.group();
        if (group == null) { trace("[DPF] no group to ask for the lobby of " + activityId); failed(); return; }
        try {
            G.call("st.Group", "tryCreateInstanceLobby", group, [activityId, (ok:Bool) -> {
                try {
                    var lobby = groupLobby(party, activityId);
                    if (lobby == null) { trace("[DPF] no lobby for " + activityId + " (ok=" + ok + ")"); failed(); return; }
                    ready();
                    show(lobby);
                } catch (error:Dynamic) { trace("[DPF] opening the dungeon window failed: " + Std.string(error)); failed(); }
            }]);
        } catch (error:Dynamic) { trace("[DPF] asking for the lobby failed: " + Std.string(error)); failed(); }
    }
}
