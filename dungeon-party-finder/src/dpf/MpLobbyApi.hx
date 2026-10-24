package dpf;

import dpf.GameAccess as G;
import dpf.Search.LobbyApi;
import dpf.Search.LobbyRef;
import dpf.Search.Peer;

/**
 * The platform's lobbies through the game's own mpman.Lobby (Steam lobbies on Steam): create, list by a filter, join, leave.
 * A lobby carries the search key (as a number, see Codec) and its creation time; each member carries their account id.
 * Only numbers and plain objects are handed to the game, which serializes them with its own code.
 *
 * The game's Steam lobby caches a member's data the first time it is read, even an empty one, so the cache entry is dropped
 * before every read (the data of a member who has just joined arrives a moment after they do).
 */
class MpLobbyApi implements LobbyApi {
    /** The last thing that went wrong, for the log. */
    public var problem = "";

    var lobby:Dynamic = null;
    var distance:Dynamic = null;
    var distanceTried = false;

    public function new() {}

    /** The widest reach the platform offers: players in other regions find each other too. */
    function reach():Dynamic {
        if (!distanceTried) {
            distanceTried = true;
            try distance = HlxRuntime.constructEnum(HlxRuntime.resolveType("mpman.Distance"), "Worldwide", []) catch (_:Dynamic) distance = null;
        }
        return distance;
    }

    static function userId(user:Dynamic):String {
        var id = G.str(G.field(user, "id"));
        return id == null ? "" : id;
    }

    static function readNumbers(data:Dynamic):Array<Int> {
        var out:Array<Int> = [];
        if (data == null) return out;
        for (i in 0...((Codec.MAX_TEXT + 1) >> 1)) {
            var value:Dynamic = G.field(data, "u" + i);
            if (value == null) break;
            out.push(G.integer(value));
        }
        return out;
    }

    static function memberData(me:Peer):Dynamic {
        var data:Dynamic = {};
        var numbers = Codec.pack(me.uid);
        for (i in 0...numbers.length) Reflect.setField(data, "u" + i, numbers[i]);
        return data;
    }

    static function lobbyData(key:String, created:Float):Dynamic {
        var data:Dynamic = {};
        Reflect.setField(data, SearchKey.FIELD, Codec.hash(key));
        Reflect.setField(data, "ts", created);
        return data;
    }

    // ---- LobbyApi ----

    public function list(key:String, done:(lobbies:Array<LobbyRef>) -> Void, fail:(why:String) -> Void):Void {
        try {
            var filters:Dynamic = {};
            Reflect.setField(filters, SearchKey.FIELD, Codec.hash(key));
            G.staticCall("mpman.Lobby", "requestList", [(found:Dynamic) -> {
                var out:Array<LobbyRef> = [];
                try {
                    for (l in G.array(found)) {
                        var data = G.field(l, "data");
                        if (data == null) continue;
                        var max = G.integer(G.field(l, "maxMembers"), 4);
                        out.push({
                            id: userId(l),
                            created: G.number(G.field(data, "ts")),
                            members: G.array(G.callVirtual(l, "getMembers")).length,
                            max: max < 1 || max > Search.LOBBY_CAP ? Search.LOBBY_CAP : max,
                            handle: l
                        });
                    }
                } catch (error:Dynamic) { problem = "list: " + Std.string(error); fail(problem); return; }
                done(out);
            }, filters, reach()]);
        } catch (error:Dynamic) {
            problem = "list: " + Std.string(error);
            fail(problem);
        }
    }

    public function create(key:String, created:Float, me:Peer, max:Int, done:(ok:Bool) -> Void):Void {
        try {
            var settings:Dynamic = {data: lobbyData(key, created), isPrivate: false, maxPlayers: max, myData: memberData(me)};
            G.staticCall("mpman.Lobby", "create", [settings, (made:Dynamic) -> {
                if (made == null) { problem = "create: no lobby"; done(false); return; }
                lobby = made;
                done(true);
            }]);
        } catch (error:Dynamic) {
            problem = "create: " + Std.string(error);
            done(false);
        }
    }

    public function join(target:LobbyRef, me:Peer, done:(ok:Bool) -> Void):Void {
        try {
            var handle:Dynamic = target.handle;
            G.callVirtual(handle, "join", [memberData(me), (ok:Bool) -> {
                if (ok) lobby = handle; else problem = "join refused";
                done(ok);
            }]);
        } catch (error:Dynamic) {
            problem = "join: " + Std.string(error);
            done(false);
        }
    }

    public function leave():Void {
        if (lobby == null) return;
        var old = lobby;
        lobby = null;
        try G.callVirtual(old, "leave") catch (error:Dynamic) problem = "leave: " + Std.string(error);
    }

    public function inLobby():Bool return lobby != null;

    public function lobbyId():String return lobby == null ? "" : userId(lobby);

    public function created():Float {
        if (lobby == null) return 0;
        return G.number(G.field(G.field(lobby, "data"), "ts"));
    }

    public function members():Array<Peer> {
        var out:Array<Peer> = [];
        if (lobby == null) return out;
        try G.callVirtual(lobby, "syncOwner") catch (_:Dynamic) {}
        var cache = G.field(lobby, "memberData");
        for (user in G.array(G.callVirtual(lobby, "getMembers"))) {
            var id = userId(user);
            if (cache != null) try G.call("haxe.ds.StringMap", "remove", cache, [id]) catch (_:Dynamic) {}
            var uid = "";
            try uid = Codec.unpack(readNumbers(G.callVirtual(lobby, "getMemberData", [user]))) catch (_:Dynamic) {}
            out.push({id: id, uid: uid, name: "", level: 0});
        }
        return out;
    }

    public function ownerId():String return lobby == null ? "" : userId(G.field(lobby, "owner"));

    public function selfId():String {
        try return userId(G.staticCall("mpman.Api", "getUser", [])) catch (_:Dynamic) return "";
    }
}
