import dpf.Search;
import dpf.Search.LobbyApi;
import dpf.Search.LobbyRef;
import dpf.Search.PartyApi;
import dpf.Search.Peer;

/** The platform and the game's parties, simulated for several players at once. */
class FakeLobby {
    public var id:String;
    public var key:String;
    public var created:Float;
    public var max:Int;
    public var members:Array<Peer> = [];
    public var withData:Map<String, Bool> = new Map();
    public function new(id:String, key:String, created:Float, max:Int) {
        this.id = id; this.key = key; this.created = created; this.max = max;
    }
}

class FakeWorld {
    public var lobbies:Array<FakeLobby> = [];
    public var groups:Map<String, Array<String>> = new Map(); // account uid -> uids of its group
    public var invites:Array<{from:String, to:String}> = [];
    public var failJoin = 0;
    public var failList = false;
    public var staleLists = false; // the platform list is a snapshot taken before anyone created anything
    var counter = 0;
    public function new() {}
    public function nextId():String return "L" + (++counter);
    public function groupOf(uid:String):Array<String> { var g = groups.get(uid); return g == null ? [uid] : g; }
    public function form(leader:String, others:Array<String>):Void {
        var all = [leader].concat(others);
        for (u in all) groups.set(u, all);
    }
}

class FakeApi implements LobbyApi implements PartyApi {
    public var world:FakeWorld;
    public var peer:Peer;
    public var current:FakeLobby = null;
    public var autoAccept = true;
    public var acceptDelayed = false;
    public function new(world:FakeWorld, peer:Peer) { this.world = world; this.peer = peer; }

    function ref(l:FakeLobby):LobbyRef return {id: l.id, created: l.created, members: l.members.length, max: l.max, handle: l};
    public function list(key:String, done:Array<LobbyRef> -> Void, fail:String -> Void):Void {
        if (world.failList) { fail("down"); return; }
        if (world.staleLists) { done([]); return; }
        done([for (l in world.lobbies) if (l.key == key && l.members.length > 0) ref(l)]);
    }
    public function create(key:String, created:Float, me:Peer, max:Int, done:Bool -> Void):Void {
        var l = new FakeLobby(world.nextId(), key, created, max);
        l.members.push(me);
        l.withData.set(me.id, true);
        world.lobbies.push(l);
        current = l;
        done(true);
    }
    public function join(lobby:LobbyRef, me:Peer, done:Bool -> Void):Void {
        if (world.failJoin > 0) { world.failJoin--; done(false); return; }
        var l:FakeLobby = lobby.handle;
        if (l.members.length >= l.max) { done(false); return; }
        l.members.push(me);
        l.withData.set(me.id, true);
        current = l;
        done(true);
    }
    public function leave():Void {
        if (current == null) return;
        current.members = current.members.filter(m -> m.id != peer.id);
        if (current.members.length == 0) world.lobbies.remove(current);
        current = null;
    }
    public function inLobby():Bool return current != null;
    public function lobbyId():String return current == null ? "" : current.id;
    public function created():Float return current == null ? 0 : current.created;
    public function members():Array<Peer> return current == null ? [] : [for (m in current.members) current.withData.get(m.id) ? m : {id: m.id, uid: "", name: m.name, level: m.level}];
    public function ownerId():String return current == null || current.members.length == 0 ? "" : current.members[0].id;
    public function selfId():String return peer.id;

    public function inviteUid(uid:String):Void world.invites.push({from: peer.uid, to: uid});
    public function groupUids():Array<String> return world.groupOf(peer.uid);
}

class SearchTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static var KEY = "dpf1|Dungeon_A|d0|b3";

    static function player(world:FakeWorld, n:Int, min = 4):{api:FakeApi, search:Search} {
        var peer:Peer = {id: "steam" + n, uid: "acc" + n, name: "P" + n, level: 12};
        var api = new FakeApi(world, peer);
        var clock = {t: 1000.0 + n};
        return {api: api, search: new Search(api, api, () -> clock.t, 4, min)};
    }

    /** Runs every search for `seconds` of fake time; accepts the invitations the way a player clicking "accept" would. */
    static function run(world:FakeWorld, players:Array<{api:FakeApi, search:Search}>, from:Float, seconds:Float, accept = true):Float {
        var t = from;
        var end = from + seconds;
        while (t < end) {
            for (p in players) p.search.update(t);
            if (accept) acceptInvites(world, players);
            t += 0.5;
        }
        return t;
    }

    static function acceptInvites(world:FakeWorld, players:Array<{api:FakeApi, search:Search}>):Void {
        var pending = world.invites;
        world.invites = [];
        for (inv in pending) {
            var target = players.filter(p -> p.api.peer.uid == inv.to)[0];
            if (target == null || !target.api.autoAccept) continue;
            var group = world.groupOf(inv.from);
            if (group.indexOf(inv.to) < 0) world.form(group[0], group.slice(1).concat([inv.to]));
        }
    }

    static function states(players:Array<{api:FakeApi, search:Search}>):String
        return [for (p in players) Std.string(p.search.state)].join(",");

    static function main():Void {
        // two players, minimum two: the first one leads
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            a.search.start(KEY, a.api.peer, 0);
            run(w, [a, b], 0, 1);
            b.search.start(KEY, b.api.peer, 1);
            run(w, [a, b], 1, 20);
            check("two players end up in one party, the first leads", states([a, b]) == "Grouped,Grouped" && w.groupOf("acc1")[0] == "acc1" && w.groupOf("acc1").indexOf("acc2") >= 0, states([a, b]));
            check("the platform lobby is left and gone", !a.api.inLobby() && !b.api.inLobby() && w.lobbies.length == 0);
        }
        // four players: invited at once when the lobby is full
        {
            var w = new FakeWorld();
            var ps = [for (i in 1...5) player(w, i)];
            var t = 0.0;
            for (p in ps) { p.search.start(KEY, p.api.peer, t); t = run(w, ps, t, 1.5); }
            t = run(w, ps, t, 10);
            check("four players form one party", states(ps) == "Grouped,Grouped,Grouped,Grouped", states(ps));
            check("the earliest searcher leads the party", w.groupOf("acc4")[0] == "acc1" && w.groupOf("acc4").length == 4);
        }
        // fewer than the minimum never starts, the minimum starts after a pause
        {
            var w = new FakeWorld();
            var a = player(w, 1, 3), b = player(w, 2, 3), c = player(w, 3, 3);
            a.search.start(KEY, a.api.peer, 0);
            b.search.start(KEY, b.api.peer, 0);
            var t = run(w, [a, b], 0, 30);
            check("two of three required keep searching", states([a, b]) == "InLobby,InLobby", states([a, b]));
            c.search.start(KEY, c.api.peer, t);
            t = run(w, [a, b, c], t, 6);
            check("no start right after the last arrival", a.search.state == InLobby);
            t = run(w, [a, b, c], t, 10);
            check("start once the lobby has been quiet", states([a, b, c]) == "Grouped,Grouped,Grouped", states([a, b, c]));
        }
        // different keys never meet
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            a.search.start(KEY, a.api.peer, 0);
            b.search.start("dpf1|Dungeon_A|d1|b3", b.api.peer, 0);
            run(w, [a, b], 0, 30);
            check("another difficulty is another group", states([a, b]) == "InLobby,InLobby" && w.lobbies.length == 2, states([a, b]));
        }
        // two lobbies made at the same moment merge into the older one
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            a.search.start(KEY, a.api.peer, 0);
            b.search.start(KEY, b.api.peer, 0);
            w.staleLists = true;
            a.search.update(0); b.search.update(0); // both listed an empty platform and created their own lobby
            w.staleLists = false;
            check("setup: two lobbies", w.lobbies.length == 2);
            run(w, [a, b], 0.5, 30);
            check("the younger lobby's owner moved into the older, party formed", states([a, b]) == "Grouped,Grouped" && w.groupOf("acc1")[0] == "acc1", states([a, b]));
        }
        // cancelling leaves the lobby, the platform keeps no empty lobby
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2);
            a.search.start(KEY, a.api.peer, 0);
            run(w, [a], 0, 3);
            check("searching in a lobby", a.search.state == InLobby && w.lobbies.length == 1);
            a.search.cancel();
            check("cancel leaves", a.search.state == Idle && w.lobbies.length == 0 && !a.api.inLobby());
        }
        // a joiner that cancels does not take the others down
        {
            var w = new FakeWorld();
            var a = player(w, 1, 3), b = player(w, 2, 3);
            a.search.start(KEY, a.api.peer, 0);
            b.search.start(KEY, b.api.peer, 0);
            var t = run(w, [a, b], 0, 3);
            b.search.cancel();
            t = run(w, [a, b], t, 12);
            check("the leader keeps searching alone", a.search.state == InLobby && w.lobbies.length == 1 && w.lobbies[0].members.length == 1);
        }
        // an invitation nobody accepts times out, the leader searches again
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            b.api.autoAccept = false;
            a.search.start(KEY, a.api.peer, 0);
            b.search.start(KEY, b.api.peer, 0);
            run(w, [a, b], 0, 12);
            check("invitations sent", a.search.state == Inviting, Std.string(a.search.state));
            run(w, [a, b], 12, Search.INVITE_TIMEOUT + 2);
            check("nobody accepted: the leader is searching again", a.search.state == InLobby || a.search.state == Listing || a.search.state == Creating || a.search.state == Joining, Std.string(a.search.state));
            check("the one who declined is still searching", b.search.isActive());
        }
        // one of two invited accepts, one does not: the party goes on with the one who did
        {
            var w = new FakeWorld();
            var a = player(w, 1, 3), b = player(w, 2, 3), c = player(w, 3, 3);
            c.api.autoAccept = false;
            var t = 0.0;
            for (p in [a, b, c]) { p.search.start(KEY, p.api.peer, t); t = run(w, [a, b, c], t, 1); }
            run(w, [a, b, c], t, 12 + Search.INVITE_TIMEOUT);
            check("the party goes on with who accepted", a.search.state == Grouped && b.search.state == Grouped && w.groupOf("acc1").length == 2, states([a, b, c]));
            check("the decliner stays in the search", c.search.isActive());
        }
        // a failing join is retried
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            a.search.start(KEY, a.api.peer, 0);
            run(w, [a], 0, 1);
            w.failJoin = 2;
            b.search.start(KEY, b.api.peer, 1);
            run(w, [a, b], 1, 30);
            check("join failures are retried", states([a, b]) == "Grouped,Grouped", states([a, b]));
        }
        // the platform down: gives up with a reason
        {
            var w = new FakeWorld();
            w.failList = true;
            var a = player(w, 1, 2);
            a.search.start(KEY, a.api.peer, 0);
            run(w, [a], 0, 60);
            check("a platform that never answers ends the search", Type.enumEq(a.search.state, Failed("list")), Std.string(a.search.state));
            a.search.start(KEY, a.api.peer, 60);
            check("a failed search can start again", a.search.state == Listing);
        }
        // already in a party
        {
            var w = new FakeWorld();
            w.form("acc1", ["acc9"]);
            var a = player(w, 1, 2);
            a.search.start(KEY, a.api.peer, 0);
            check("no search from inside a party", Type.enumEq(a.search.state, Failed("party")));
        }
        // a member whose data has not arrived yet is not counted
        {
            var w = new FakeWorld();
            var a = player(w, 1, 2), b = player(w, 2, 2);
            a.search.start(KEY, a.api.peer, 0);
            run(w, [a], 0, 1);
            b.search.start(KEY, b.api.peer, 1);
            b.search.update(1);
            w.lobbies[0].withData.set("steam2", false);
            run(w, [a], 1, 15, false);
            check("a member without data is waited for", a.search.state == InLobby, Std.string(a.search.state));
            w.lobbies[0].withData.set("steam2", true);
            run(w, [a, b], 16, 15);
            check("and invited once the data is there", a.search.state == Grouped, Std.string(a.search.state));
        }
        // a late accepter of a stale invitation is pulled out of the search
        {
            var w = new FakeWorld();
            var a = player(w, 1, 3), b = player(w, 2, 3), c = player(w, 3, 3);
            c.api.autoAccept = false;
            var t = 0.0;
            for (p in [a, b, c]) { p.search.start(KEY, p.api.peer, t); t = run(w, [a, b, c], t, 1); }
            t = run(w, [a, b, c], t, 12 + Search.INVITE_TIMEOUT);
            w.form("acc1", ["acc2", "acc3"]);
            run(w, [a, b, c], t, 3);
            check("late accepter joins the party", c.search.state == Grouped, Std.string(c.search.state));
        }

        // removed from the lobby by the platform: the search starts over and finds a lobby again
        {
            var w = new FakeWorld();
            var a = player(w, 1, 4);
            a.search.start(KEY, a.api.peer, 0);
            var t = run(w, [a], 0, 2);
            a.api.current.members = []; // the platform emptied the lobby behind the player's back
            t = run(w, [a], t, 12);
            check("a lobby that lost me is replaced", a.search.state == InLobby && w.lobbies.length >= 1 && a.api.current != null && a.api.current.members.length == 1, Std.string(a.search.state));
        }

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
