package dpf;

import dpf.GameAccess as G;
import dpf.Search.PartyApi;

/** The local player and the game's party, read from the live GameApp (`app` is refreshed every frame by the mod). */
class GameParty implements PartyApi {
    public var app:Dynamic;

    public function new() {}

    public function me():Dynamic return G.field(app, "me");
    public function hero():Dynamic return G.field(app, "hero");
    /** The group of the hero's player (the way the game's own dungeon buttons reach it); the app's `me` is the fallback. */
    public function group():Dynamic {
        var player = G.field(hero(), "player");
        var g = player == null ? null : G.field(player, "group");
        return g != null ? g : G.field(me(), "group");
    }

    public function uid():String return textOf(G.field(me(), "uid"));
    public function name():String return textOf(G.field(me(), "name"));

    static function textOf(value:Dynamic):String {
        var s = G.str(value);
        return s == null ? "" : s;
    }

    public function level():Int return levelOf(hero());

    public static function levelOf(hero:Dynamic):Int {
        if (hero == null) return 0;
        try return G.integer(G.call("ent.Unit", "get_level", hero)) catch (_:Dynamic) return 0;
    }

    public function maxLevel():Int {
        var value = G.integer(G.field(G.current("Const", "Hero"), "MaxLevel"), 0);
        return value > 0 ? value : 25;
    }

    /** Members of the group the party is in (me included); a lone player is a group of one. */
    public function players():Array<Dynamic> {
        var g = group();
        return g == null ? [] : G.array(G.field(g, "players"), true);
    }

    /** The group's leader is its first player. */
    public function leader():Dynamic {
        var all = players();
        return all.length == 0 ? null : all[0];
    }

    public function isLeader():Bool {
        var l = leader();
        return l != null && l == me();
    }

    public function groupSize():Int return players().length;

    public function playerName(player:Dynamic):String return textOf(G.field(player, "name"));

    /** "Priest 25": the hero's class and level, empty while the hero is not loaded. */
    public function detail(player:Dynamic):String {
        var hero = G.field(player, "hero");
        if (hero == null) return "";
        try {
            var cls = textOf(G.staticCall("HText", "unit", [G.field(hero, "inf"), null]));
            return (cls == "" ? "" : cls + " ") + levelOf(hero);
        } catch (_:Dynamic) return Std.string(levelOf(hero));
    }

    // ---- PartyApi ----

    /** The player object owns the whispers (the game's own invite buttons reach them as `player.whispers`); the app's `me` is the fallback. */
    function whispers():Dynamic {
        var player = G.field(hero(), "player");
        var w = player == null ? null : G.field(player, "whispers");
        return w != null ? w : G.field(me(), "whispers");
    }

    public function inviteUid(uid:String):Void {
        var w = whispers();
        if (w == null) { trace("[DPF] no whispers to invite " + uid); return; }
        try G.call("st.player.Whispers", "sendInviteGroup", w, [uid]) catch (error:Dynamic) trace("[DPF] invite of " + uid + " failed: " + Std.string(error));
    }

    public function groupUids():Array<String> {
        var out:Array<String> = [];
        for (p in players()) out.push(textOf(G.field(p, "uid")));
        if (out.length == 0) out.push(uid());
        return out;
    }
}
