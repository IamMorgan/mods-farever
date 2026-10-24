package dpf;

import dpf.GameAccess as G;
import dpf.PartyLogic.ButtonKind;
import dpf.PartyLogic.LobbyPhase;

typedef Card = {name:String, detail:String, ready:Bool, leader:Bool, me:Bool};

/**
 * After a party has formed: the dungeon lobby of the game (st.player.InstanceLobby), driven the way the game's own dungeon
 * dialog drives it. The leader opens the lobby and sets the difficulty; the others join it; the leader starts once everyone
 * is ready, the others press ready. The mod's window only shows it; no dialog of the game is opened.
 */
class PartyFlow {
    static inline var STEP = 1.0;
    static inline var RETRY = 3.0;

    /** The last refusal of the game, in the game's own words (empty when there is none). */
    public var message = "";
    /** How many times in a row the game has refused to open the dungeon lobby. */
    public var refused = 0;

    var party:GameParty;
    var activityId = "";
    var difficulty = 0;
    var nextStep = 0.0;
    var nextCreate = 0.0;
    var nextDifficulty = 0.0;

    public function new(party:GameParty) this.party = party;

    public function begin(activityId:String, difficulty:Int):Void {
        this.activityId = activityId;
        this.difficulty = difficulty;
        message = "";
        refused = 0;
        nextStep = 0;
        nextCreate = 0;
        nextDifficulty = 0;
    }

    public function end():Void {
        activityId = "";
        message = "";
    }

    function lobby():Dynamic {
        var group = party.group();
        if (group == null || activityId == "") return null;
        try return G.call("st.Group", "getInstanceLobby", group, [activityId]) catch (_:Dynamic) return null;
    }

    function infoOf(lobby:Dynamic, player:Dynamic):Dynamic {
        try return G.call("st.player.InstanceLobby", "getPlayerInfo", lobby, [player]) catch (_:Dynamic) return null;
    }

    static function reasonName(reason:Dynamic):String return reason == null ? null : Std.string(reason);

    function stateName(lobby:Dynamic):String {
        try return Std.string(G.field(lobby, "state")) catch (_:Dynamic) return "";
    }

    /** Once a second: the leader opens the lobby and keeps its difficulty, the others join it. */
    public function update(now:Float):Void {
        if (activityId == "" || now < nextStep) return;
        nextStep = now + STEP;
        try {
            var group = party.group();
            if (group == null) return;
            var l = lobby();
            if (l == null) {
                if (party.isLeader() && now >= nextCreate) {
                    nextCreate = now + RETRY;
                    G.call("st.Group", "tryCreateInstanceLobby", group, [activityId, (ok:Bool) -> { refused = ok ? 0 : refused + 1; }]);
                }
                return;
            }
            if (infoOf(l, party.me()) == null) {
                if (now >= nextCreate) {
                    nextCreate = now + RETRY;
                    G.call("st.Group", "tryCreateInstanceLobby", group, [activityId, (ok:Bool) -> { refused = ok ? 0 : refused + 1; }]);
                }
                return;
            }
            if (party.isLeader() && G.integer(G.field(l, "difficulty"), -1) != difficulty && now >= nextDifficulty) {
                nextDifficulty = now + RETRY;
                var reason = reasonName(G.call("st.player.InstanceLobby", "setDifficulty", l, [difficulty, null]));
                if (!PartyLogic.isOk(reason)) message = reasonText(G.call("st.player.InstanceLobby", "getDifficultyReason", l, [difficulty]));
            }
        } catch (error:Dynamic) trace("[DPF] party step failed: " + Std.string(error));
    }

    function reasonText(reason:Dynamic):String {
        try {
            var text = G.str(G.staticCall("HText", "reason", [reason]));
            return text == null ? "" : text;
        } catch (_:Dynamic) return "";
    }

    public function phase():LobbyPhase {
        var l = lobby();
        if (l == null || infoOf(l, party.me()) == null) return Missing;
        return PartyLogic.phaseOf(stateName(l), true);
    }

    public function allReady():Bool {
        var l = lobby();
        if (l == null) return false;
        try return G.call("st.player.InstanceLobby", "hasAllPlayersReady", l) == true catch (_:Dynamic) return false;
    }

    public function myReady():Bool {
        var l = lobby();
        if (l == null) return false;
        var info = infoOf(l, party.me());
        return info != null && G.field(info, "ready") == true;
    }

    public function button():ButtonKind return PartyLogic.button(party.isLeader(), phase(), allReady(), myReady());

    /** The party's players for the window, leader first. */
    public function cards():Array<Card> {
        var out:Array<Card> = [];
        var l = lobby();
        var leader = party.leader();
        var me = party.me();
        for (p in party.players()) {
            var info = l == null ? null : infoOf(l, p);
            out.push({
                name: party.playerName(p),
                detail: party.detail(p),
                ready: info != null && G.field(info, "ready") == true,
                leader: p == leader,
                me: p == me
            });
        }
        return out;
    }

    /** What the game's own start / ready button does. */
    public function press():Void {
        try {
            var l = lobby();
            if (l == null) return;
            message = "";
            var reason:Dynamic = null;
            if (party.isLeader()) {
                var current = PartyLogic.phaseOf(stateName(l), true);
                reason = current == Waiting || current == AllReady
                    ? G.call("st.player.InstanceLobby", "requestStart", l, [null])
                    : G.call("st.player.InstanceLobby", "cancelStart", l, [null]);
            } else {
                reason = G.call("st.player.InstanceLobby", "setPlayerReady", l, [!myReady(), null]);
            }
            if (!PartyLogic.isOk(reasonName(reason))) message = reasonText(reason);
        } catch (error:Dynamic) trace("[DPF] press failed: " + Std.string(error));
    }
}
