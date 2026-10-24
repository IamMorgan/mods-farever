package dpf;

import dpf.Search.LobbyApi;
import dpf.Search.Peer;

enum Mode {
    Idle;
    Searching;
    /** A group has formed: the dungeon lobby of the group is being shown. */
    Party;
}

/**
 * The player's search for a group: the matchmaking (Search) for one dungeon and difficulty and, once a group has formed,
 * getting everyone into the group's dungeon lobby (LobbyFlow). The dungeon window itself is the game's.
 */
class Session {
    /** A group is whole at four players; the search goes on until then. */
    public static inline var GROUP = 4;

    public var activityId(default, null) = "";
    public var difficulty(default, null) = 0;
    /** What went wrong last (shown in the dungeon window), empty when nothing did. */
    public var message(default, null) = "";

    var party:GameParty;
    var lobbies:LobbyApi;
    var search:Search;
    var flow:LobbyFlow;
    var inParty = false;
    var lostAt = -1.0;

    public function new(party:GameParty, lobbies:LobbyApi) {
        this.party = party;
        this.lobbies = lobbies;
        search = new Search(lobbies, party, () -> Date.now().getTime(), GROUP, GROUP);
        flow = new LobbyFlow(party);
    }

    public function mode():Mode return inParty ? Party : (search.isActive() ? Searching : Idle);

    /** Players found in the platform lobby so far (the player included). */
    public function found():Int return search.count;

    public function isInvited():Bool return Type.enumEq(search.state, Inviting);

    public function start(activityId:String, difficulty:Int, now:Float):Void {
        if (mode() != Idle) return;
        message = "";
        if (party.hero() == null || party.me() == null) { message = Locale.noHero(); return; }
        if (party.groupSize() > 1) { message = Locale.inParty(); return; }
        this.activityId = activityId;
        this.difficulty = difficulty;
        var key = SearchKey.make(activityId, difficulty, LevelBrackets.index(party.level(), party.maxLevel()));
        var me:Peer = {id: lobbies.selfId(), uid: party.uid(), name: party.name(), level: party.level()};
        search.start(key, me, now);
    }

    public function cancel():Void {
        search.cancel();
        if (inParty) endParty();
        message = "";
    }

    function endParty():Void {
        inParty = false;
        lostAt = -1;
        flow.end();
        search.reset();
    }

    public function update(now:Float):Void {
        try {
            if (party.hero() == null) return; // loading between zones: wait
            search.update(now);
            switch search.state {
                case Grouped if (!inParty):
                    inParty = true;
                    lostAt = -1;
                    flow.begin(activityId, difficulty);
                case Failed(reason) if (message == ""):
                    message = reason == "party" ? Locale.inParty() : Locale.platformDown();
                default:
            }
            if (inParty) {
                if (party.groupSize() < 2) {
                    if (lostAt < 0) lostAt = now;
                    else if (now - lostAt > 2) { endParty(); message = Locale.partyLost(); }
                } else {
                    lostAt = -1;
                    flow.update(now);
                }
            }
        } catch (error:Dynamic) trace("[DPF] session update failed: " + Std.string(error));
    }
}
