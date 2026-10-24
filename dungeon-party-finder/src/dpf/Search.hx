package dpf;

/** A searcher as the others see them. `id` is the platform user id, `uid` the account id the game invites by. */
typedef Peer = {id:String, uid:String, name:String, level:Int};

/** A lobby found in the platform's list. `handle` is whatever the adapter needs to join it. */
typedef LobbyRef = {id:String, created:Float, members:Int, max:Int, handle:Dynamic};

/** The platform's lobbies (Steam through the game's own mpman.Lobby). Callbacks may fire at once or later. */
interface LobbyApi {
    function list(key:String, done:(lobbies:Array<LobbyRef>) -> Void, fail:(why:String) -> Void):Void;
    function create(key:String, created:Float, me:Peer, max:Int, done:(ok:Bool) -> Void):Void;
    function join(lobby:LobbyRef, me:Peer, done:(ok:Bool) -> Void):Void;
    /** Leaves the lobby the adapter is in, if any. */
    function leave():Void;
    function inLobby():Bool;
    function lobbyId():String;
    /** When the current lobby was created (the creator's stamp). */
    function created():Float;
    /** The members of the current lobby; `uid` is empty while a member's data has not arrived yet. */
    function members():Array<Peer>;
    function ownerId():String;
    function selfId():String;
}

/** The game's own parties. */
interface PartyApi {
    /** Sends the game's group invitation to the account. */
    function inviteUid(uid:String):Void;
    /** Account ids of everyone in my current group (me included; a lone player is a group of one). */
    function groupUids():Array<String>;
    /** Whether I lead my group (true for a lone player too). */
    function isGroupLeader():Bool;
}

enum SearchState {
    Idle;
    Listing;
    Creating;
    Joining;
    InLobby;
    Inviting;
    /** A party has formed (the platform lobby is already left); the dungeon lobby takes over. */
    Grouped;
    /** "list": the platform lobbies keep failing, "party": already in a party. */
    Failed(reason:String);
}

/**
 * The matchmaking itself, free of the game: everyone with the same key meets in one platform lobby. The lobby's owner is the
 * leader, and the oldest lobby wins: whoever finds nothing creates a lobby, a younger lobby's owner moves into an older one,
 * so the earliest searcher ends up leading. As soon as a second searcher is in the lobby the leader invites everyone
 * there with the game's own group invitation, and goes on inviting whoever arrives later. Whoever accepts sees the party form and leaves the
 * lobby; whoever declines or lets the invitation lapse is set aside and the leader keeps looking: the next searcher to
 * arrive in the lobby is invited in their place, until the party is full.
 */
class Search {
    public static inline var POLL = 1.0;          // seconds between looks at the lobby
    public static inline var SETTLE = 8.0;        // a lobby below full is started this long after its last change
    public static inline var INVITE_TIMEOUT = 30.0;  // an invitation not accepted by then counts as declined
    public static inline var LOBBY_CAP = 8;          // room for searchers who declined and are still sitting in the lobby
    public static inline var RETRY = 3.0;
    public static inline var MERGE_EVERY = 4.0;
    public static inline var MAX_FAILURES = 5;
    public static inline var ABSENT_POLLS = 4;     // looks without me in my own lobby before it is given up

    public var state(default, null):SearchState = Idle;
    /** True while I own the platform lobby I am in. */
    public var leader(default, null) = false;
    /** Players in the lobby (with data) as of the last look. */
    public var count(default, null) = 0;
    /** The last problem reported by the platform. */
    public var lastError(default, null) = "";

    var lobbies:LobbyApi;
    var party:PartyApi;
    var clock:() -> Float;
    var maxPlayers:Int;
    public var minPlayers:Int;

    var key = "";
    var me:Peer = null;
    var now = 0.0;
    var token = 0;            // bumped by every restart/cancel: answers of older requests are ignored
    var pending = false;
    var nextList = 0.0;
    var nextPoll = 0.0;
    var nextMerge = 0.0;
    var mergePending = false;
    var failures = 0;
    var absent = 0;
    var lastChange = 0.0;
    var invitedAt:Map<String, Float> = new Map();   // account uid -> when its invitation was sent
    var rejected:Map<String, Bool> = new Map();     // declined or ignored: not invited again in this search
    var seen:Map<String, Bool> = new Map();

    /** `clock` is the cross-player time stamp of lobbies (server or wall time), `maxPlayers` the party size. */
    public function new(lobbies:LobbyApi, party:PartyApi, clock:() -> Float, maxPlayers = 4, minPlayers = 4) {
        this.lobbies = lobbies;
        this.party = party;
        this.clock = clock;
        this.maxPlayers = maxPlayers;
        this.minPlayers = minPlayers;
    }

    public function isActive():Bool return switch state { case Listing | Creating | Joining | InLobby | Inviting: true; default: false; };

    public function start(key:String, me:Peer, now:Float):Void {
        if (isActive() || state == Grouped) return;
        this.now = now;
        this.key = key;
        this.me = me;
        seen = new Map();
        invitedAt = new Map();
        rejected = new Map();
        if (me == null || me.uid == "" || party.groupUids().length > 1 && !party.isGroupLeader()) { state = Failed("party"); return; }
        begin();
    }

    public function cancel():Void {
        token++;
        pending = false;
        mergePending = false;
        if (lobbies.inLobby()) lobbies.leave();
        leader = false;
        count = 0;
        invitedAt = new Map();
        rejected = new Map();
        state = Idle;
    }

    /** Back to nothing at all (the party is over). */
    public function reset():Void cancel();

    function begin():Void {
        token++;
        pending = false;
        mergePending = false;
        leader = false;
        count = 0;
        failures = 0;
        invitedAt = new Map();
        state = Listing;
        nextList = now;
    }

    function restart(delay:Float):Void {
        token++;
        if (lobbies.inLobby()) lobbies.leave();
        begin();
        nextList = now + delay;
    }

    public function update(now:Float):Void {
        this.now = now;
        switch state {
            case Listing:
                if (!pending && now >= nextList) requestList();
            case InLobby:
                if (now >= nextPoll) { nextPoll = now + POLL; poll(); }
            case Inviting:
                if (now >= nextPoll) { nextPoll = now + POLL; pollInviting(); }
            default:
        }
    }

    // ---- finding or making a lobby ----

    function requestList():Void {
        pending = true;
        var t = token;
        lobbies.list(key, found -> {
            if (t != token) return;
            pending = false;
            if (state == Listing) choose(found);
        }, why -> {
            if (t != token) return;
            pending = false;
            lastError = why;
            failures++;
            nextList = now + RETRY;
            if (failures >= MAX_FAILURES) { token++; state = Failed("list"); }
        });
    }

    static function before(aCreated:Float, aId:String, bCreated:Float, bId:String):Bool
        return aCreated < bCreated || (aCreated == bCreated && aId < bId);

    function older(found:Array<LobbyRef>, excludeId:String, thanCreated:Null<Float>, thanId:String):Array<LobbyRef> {
        var out = found.filter(l -> l.id != excludeId && l.members < l.max
            && (thanCreated == null || before(l.created, l.id, thanCreated, thanId)));
        out.sort((a, b) -> before(a.created, a.id, b.created, b.id) ? -1 : (before(b.created, b.id, a.created, a.id) ? 1 : 0));
        return out;
    }

    function choose(found:Array<LobbyRef>):Void {
        var candidates = older(found, lobbies.lobbyId(), null, "");
        if (candidates.length > 0) joinLobby(candidates[0]);
        else createLobby();
    }

    function joinLobby(target:LobbyRef):Void {
        state = Joining;
        var t = token;
        lobbies.join(target, me, ok -> {
            if (t != token) { if (ok) lobbies.leave(); return; }
            if (ok) enterLobby();
            else { state = Listing; nextList = now + 1; }
        });
    }

    function createLobby():Void {
        state = Creating;
        var t = token;
        lobbies.create(key, clock(), me, LOBBY_CAP, ok -> {
            if (t != token) { if (ok) lobbies.leave(); return; }
            if (ok) enterLobby();
            else { state = Listing; nextList = now + RETRY; }
        });
    }

    function enterLobby():Void {
        state = InLobby;
        lastChange = now;
        absent = 0;
        count = 0;
        nextPoll = now;
        nextMerge = now + MERGE_EVERY;
        mergePending = false;
    }

    // ---- in the lobby ----

    function poll():Void {
        if (!lobbies.inLobby()) { restart(1); return; }
        var self = lobbies.selfId();
        var all = lobbies.members();
        var present = false;
        for (p in all) if (p.id == self) present = true;
        // The platform dropped me from the lobby (it was closed, or I was removed): look for another one.
        if (self != "" && !present) {
            if (++absent >= ABSENT_POLLS) { restart(1); return; }
        } else absent = 0;
        var group = party.groupUids();
        // Members of my own group are not "found": they are already with me.
        for (p in all) if (p.uid != "" && p.id != self) seen.set(p.uid, true);
        var peers = all.filter(p -> p.uid != "" && (p.id == self || group.indexOf(p.uid) < 0));

        // The game's party has formed around someone from this lobby: the search is over.
        if (group.length > 1) {
            for (u in group) if (u != me.uid && seen.exists(u)) { finishToParty(); return; }
        }

        if (peers.length != count) { count = peers.length; lastChange = now; }
        // The leader of a group that is still short of players invites from whatever lobby it is in.
        leader = self != "" && (lobbies.ownerId() == self || (group.length > 1 && party.isGroupLeader()));
        if (!leader) return;

        var open = peers.filter(p -> !rejected.exists(p.uid));
        var n = open.length;
        if (n >= 2) { invite(open, self); return; }

        if (!mergePending && now >= nextMerge) {
            nextMerge = now + MERGE_EVERY;
            mergePending = true;
            var t = token;
            lobbies.list(key, found -> {
                if (t != token) return;
                mergePending = false;
                if (state == InLobby) maybeMerge(found);
            }, why -> {
                if (t == token) mergePending = false;
            });
        }
    }

    /** An older lobby with room exists: its leader came first, so this lobby's owner moves in. */
    function maybeMerge(found:Array<LobbyRef>):Void {
        var candidates = older(found, lobbies.lobbyId(), lobbies.created(), lobbies.lobbyId());
        if (candidates.length == 0) return;
        token++;
        lobbies.leave();
        leader = false;
        count = 0;
        joinLobby(candidates[0]);
    }

    function invite(peers:Array<Peer>, self:String):Void {
        invitedAt = new Map();
        state = Inviting;
        nextPoll = now;
        pollInviting();
    }

    /**
     * The leader's look while invitations are out: invites go to as many searchers as there are free places, the ones who
     * did not accept in time are set aside, and the places they leave are offered to whoever else is in the lobby.
     */
    function pollInviting():Void {
        var group = party.groupUids();
        if (!lobbies.inLobby()) {
            if (group.length > 1) finishToParty(); else restart(1);
            return;
        }
        var self = lobbies.selfId();
        var peers = lobbies.members().filter(p -> p.uid != "" && p.id != self && p.uid != me.uid);
        for (p in peers) seen.set(p.uid, true);
        count = 1 + peers.filter(p -> group.indexOf(p.uid) < 0).length;

        var lapsed = [for (u in invitedAt.keys()) if (group.indexOf(u) < 0 && now - invitedAt.get(u) >= INVITE_TIMEOUT) u];
        for (u in lapsed) { rejected.set(u, true); invitedAt.remove(u); lastChange = now; }

        var free = maxPlayers - group.length;
        if (free <= 0) { finishToParty(); return; }

        var outstanding = [for (u in invitedAt.keys()) if (group.indexOf(u) < 0) u].length;
        for (p in peers) {
            if (outstanding >= free) break;
            if (group.indexOf(p.uid) >= 0 || rejected.exists(p.uid) || invitedAt.exists(p.uid)) continue;
            party.inviteUid(p.uid);
            invitedAt.set(p.uid, now);
            outstanding++;
            lastChange = now;
        }
        if (outstanding > 0) return;

        if (group.length > 1) {
            // Everyone answered and nobody else is waiting: go on with a short party if it is allowed to start.
            if (group.length >= minPlayers) finishToParty();
        } else {
            // Nobody accepted: back to waiting for searchers (the ones who declined are not asked again).
            state = InLobby;
            lastChange = now;
        }
    }

    function finishToParty():Void {
        token++;
        if (lobbies.inLobby()) lobbies.leave();
        leader = false;
        state = Grouped;
    }
}
