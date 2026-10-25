package farmer;

import farmer.GameAccess as G;

typedef NodeSpot = {key:Int, id:String, gatherable:String, x:Float, y:Float, z:Float};

/**
 * Where the ore and plant nodes of the big world are. The game only loads the nodes near the hero, but its element table
 * (HElement.all) lists every node of the world with its place, so the bot can go to the nearest node of a wanted resource
 * wherever it lies (by obelisk when far, see Nav.travel), as it does for monsters (see Hunt).
 */
class Nodes {
    static var spots:Array<NodeSpot> = [];
    static var built = false;
    static var wantCache:Map<String, Bool> = new Map();

    static inline var FILE = "hlx/config/farmer/nodes.json";
    /** Nodes seen in the loaded world (the generic ore and plant nodes are not in the element table before their chunk is loaded), by place. */
    static var seen:Map<String, NodeSpot> = new Map();
    static var seenLoaded = false;
    static var seenDirty = false;
    static var rememberedAt = -100.0;
    static var savedAt = 0.0;
    static var nextKey = 100000;

    /** True once the table was read (it needs the big world: dungeons have no such table). */
    public static function ready():Bool return built;

    /** Reads the world's gatherable elements, once. */
    public static function build():Void {
        if (built) return;
        built = true;
        spots = [];
        try {
            var all = G.fastArray(G.staticCall("HElement", "all", []));
            var k = 0;
            for (def in all) {
                if (def == null) continue;
                var gid = G.s(G.field(G.field(G.field(def, "inf"), "props"), "gatherable"));
                if (gid == "") continue;
                if (!StringTools.startsWith(G.s(G.field(def, "mapId")), "World/")) continue;
                var pre = G.field(def, "prefab");
                spots.push({key: k++, id: G.s(G.field(G.field(def, "inf"), "id")), gatherable: gid, x: G.number(G.field(pre, "x")), y: G.number(G.field(pre, "y")), z: G.number(G.field(pre, "z"), Math.NaN)});
            }
            Log.t("hunt", "node map: " + spots.length + " ore/plant nodes in the world");
        } catch (e:Dynamic) Log.t("err", "node map failed: " + Std.string(e));
    }

    /** Every few seconds: notes the nodes the game has loaded around the hero (their places are kept in a file for the next sessions). */
    public static function remember(hero:Dynamic, now:Float):Void {
        if (now - rememberedAt < 5) return;
        rememberedAt = now;
        if (!seenLoaded) load();
        try {
            if (!Hunt.onWorld(hero)) return;
            for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                var gid = G.s(G.field(G.field(e, "gatherInf"), "id"));
                if (gid == "") continue;
                var x = G.number(G.field(e, "posx")), y = G.number(G.field(e, "posy"));
                var k = Math.round(x) + "," + Math.round(y);
                if (seen.exists(k)) continue;
                seen.set(k, {key: nextKey++, id: G.s(G.field(G.field(e, "inf"), "id")), gatherable: gid, x: x, y: y, z: G.number(G.field(e, "posz"), Math.NaN)});
                seenDirty = true;
            }
            if (seenDirty && now - savedAt > 60) save(now);
        } catch (_:Dynamic) {}
    }

    static function load():Void {
        seenLoaded = true;
        try {
            if (!sys.FileSystem.exists(FILE)) return;
            var list:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(FILE));
            for (d in list) {
                var s:NodeSpot = {key: nextKey++, id: Std.string(Reflect.field(d, "id")), gatherable: Std.string(Reflect.field(d, "g")), x: Reflect.field(d, "x"), y: Reflect.field(d, "y"), z: Reflect.field(d, "z") == null ? Math.NaN : Reflect.field(d, "z")};
                seen.set(Math.round(s.x) + "," + Math.round(s.y), s);
            }
            Log.t("hunt", "node memory: " + list.length + " nodes known from earlier sessions");
        } catch (e:Dynamic) Log.t("err", "node memory not read: " + Std.string(e));
    }

    static function save(now:Float):Void {
        savedAt = now;
        seenDirty = false;
        try {
            var list = [for (s in seen) {id: s.id, g: s.gatherable, x: Math.round(s.x * 10) / 10, y: Math.round(s.y * 10) / 10, z: Math.isFinite(s.z) ? Math.round(s.z * 10) / 10 : null}];
            sys.io.File.saveContent(FILE, haxe.Json.stringify(list));
        } catch (e:Dynamic) Log.t("err", "node memory not saved: " + Std.string(e));
    }

    /** The nodes known now: the world's element table and the ones seen. */
    static function all():Array<NodeSpot> {
        var out = spots.copy();
        for (s in seen) out.push(s);
        return out;
    }

    /** True when the gatherable (data id) gives something the plan still wants. */
    static function wants(gid:String, plan:FarmPlan):Bool {
        var rec = Catalog.gatherable(gid);
        if (rec == null) return false;
        for (id in Catalog.gatherItems(rec).keys()) if (plan.count(false, id) > 0) return true;
        return false;
    }

    /** The nodes of the wanted resources, nearest first by the cost of getting there (a walk, or by obelisk), not in `visited` (key -> time until which it is left alone). */
    public static function find(hero:Dynamic, plan:FarmPlan, visited:Map<Int, Float>, now:Float, obelisks:Array<Nav.ObeliskInfo>, ?ok:(Float, Float, Float) -> Bool):Null<{spot:NodeSpot, away:Float, count:Int}> {
        build();
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var toHero = Math.POSITIVE_INFINITY;
        for (o in obelisks) toHero = Math.min(toHero, Math.sqrt((hx - o.x) * (hx - o.x) + (hy - o.y) * (hy - o.y)));
        var best = null;
        var bestCost = Math.POSITIVE_INFINITY;
        var bestDirect = 0.0;
        var usable = 0;
        wantCache = new Map();
        for (s in all()) {
            var w = wantCache.get(s.gatherable);
            if (w == null) { w = wants(s.gatherable, plan); wantCache.set(s.gatherable, w); }
            if (!w) continue;
            usable++;
            var until = visited.get(s.key);
            if (until != null && now < until) continue;
            if (ok != null && !ok(s.x, s.y, s.z)) continue; // (the reach map says no way leads there)
            var direct = Math.sqrt((s.x - hx) * (s.x - hx) + (s.y - hy) * (s.y - hy));
            var cost = direct;
            if (obelisks.length >= 2) {
                var fromSpot = Math.POSITIVE_INFINITY;
                for (o in obelisks) fromSpot = Math.min(fromSpot, Math.sqrt((s.x - o.x) * (s.x - o.x) + (s.y - o.y) * (s.y - o.y)));
                cost = Math.min(direct, toHero + fromSpot + 150);
            }
            if (Math.isFinite(s.z) && Math.abs(s.z - hz) > 8) cost += Math.abs(s.z - hz) * 5; // another tier: the way there is a guess, the nodes of the hero's own tier come first
            if (cost < bestCost) { bestCost = cost; best = s; bestDirect = direct; }
        }
        return best == null ? null : {spot: best, away: bestDirect, count: usable};
    }

    /** The spots within `r` metres of (x, y) (the nodes of one outcrop are visited together). */
    public static function near(x:Float, y:Float, r:Float):Array<NodeSpot> {
        return [for (s in all()) if ((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) <= r * r) s];
    }
}
