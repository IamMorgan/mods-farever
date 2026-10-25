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
                if (scanFinished && scanned.length > 0 && checkHits + checkMisses < 40 && !seen.exists(k)) {
                    if (nearScanned(x, y)) checkHits++; else checkMisses++;
                    if (checkHits + checkMisses == 40) Log.t("hunt", "node scan check: " + checkHits + " of 40 nodes loaded around the hero were in the scanned list (" + checkMisses + " not)");
                }
                if (seen.exists(k) || nearScanned(x, y)) continue;
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

    // ---- the whole map's nodes, from the game's own chunk files ----

    /**
     * The game reads the prefabs of EVERY chunk of the world when a level loads (prefab.World.loadDataFromFiles: gameplayData.chunkPrefabs),
     * the unloaded ones too. Their element prefabs are the nodes of the whole map: ore and plants anywhere, known before the hero ever went
     * there. The chunks are read a few per call (see scanStep) and the nodes put in `scanned`.
     */
    static var scanned:Array<NodeSpot> = [];
    static var scanGrid:Map<Int, Bool> = new Map();
    static var scanChunks:Array<Dynamic> = null;
    static var scanMap:Dynamic = null;
    static var scanPos = 0;
    static var scanFinished = false;
    static var scanElements = 0;
    static var scanRefs = 0;
    static var scanRefSamples:Array<String> = [];
    static var scanRefSeen:Map<String, Bool> = new Map();
    static var gidOfId:Map<String, String> = new Map();
    static var checkHits = 0;
    static var checkMisses = 0;

    /** True while the chunk files of the world are still being read. */
    public static function scanning():Bool return !scanFinished;

    static inline function cellKey(x:Float, y:Float):Int return Math.floor(x / 4) * 100003 + Math.floor(y / 4);

    static function nearScanned(x:Float, y:Float):Bool {
        for (dx in -1...2) for (dy in -1...2) if (scanGrid.exists(cellKey(x + dx * 4, y + dy * 4))) return true;
        return false;
    }

    /** The gatherable (data id) an element gives, "" when the element is none. */
    static function gatherableOf(elementId:String):String {
        var g = gidOfId.get(elementId);
        if (g != null) return g;
        g = "";
        try {
            var def = G.call("haxe.ds.StringMap", "get", G.current("HElement", "allElements"), [elementId]);
            if (def != null) g = G.s(G.field(G.field(G.field(def, "inf"), "props"), "gatherable"));
        } catch (_:Dynamic) {}
        gidOfId.set(elementId, g);
        return g;
    }

    /** Developer: what the element table says about an id. */
    public static function elementInfo(id:String):String {
        try {
            var def = G.call("haxe.ds.StringMap", "get", G.current("HElement", "allElements"), [id]);
            if (def == null) return id + ": no element";
            var props = G.field(G.field(def, "inf"), "props");
            return id + ": element, gatherable '" + G.s(G.field(props, "gatherable")) + "', status " + G.field(props, "releaseStatus") + ", inherit '" + G.s(G.field(G.field(def, "inf"), "inherit")) + "'";
        } catch (e:Dynamic) { return id + ": error " + Std.string(e); }
    }

    /** Reads up to `budget` chunks of the world's chunk table. */
    public static function scanStep(budget:Int = 40):Void {
        if (scanFinished) return;
        try {
            if (scanChunks == null) {
                var world = G.current("world.World", "inst");
                var gp = G.field(world, "gameplayData");
                scanChunks = G.fastArray(G.field(gp, "chunkData"));
                scanMap = G.field(gp, "chunkPrefabs");
                if (scanMap == null || scanChunks.length == 0) throw "no chunk table (" + scanChunks.length + " chunks)";
                Log.t("hunt", "node scan: " + scanChunks.length + " chunks in the world's table");
            }
            var end = Std.int(Math.min(scanChunks.length, scanPos + budget));
            while (scanPos < end) {
                var d = scanChunks[scanPos++];
                var wcd = G.call("haxe.ds.StringMap", "get", scanMap, [G.s(G.field(d, "id"))]);
                if (wcd == null) continue;
                for (p in G.fastArray(G.call("prefab.WorldChunkData", "getPrefabs", wcd))) visit(p, 0, 0, 0, 0);
            }
            if (scanPos >= scanChunks.length) {
                scanFinished = true;
                var wanted = 0;
                for (s in scanned) if (s.gatherable != "") wanted++;
                Log.t("hunt", "node scan done: " + scanElements + " element prefabs, " + scanned.length + " ore/plant nodes in the whole world");
            }
        } catch (e:Dynamic) {
            scanFinished = true;
            Log.t("err", "node scan failed (the search of zones is used instead): " + Std.string(e));
        }
    }

    static function visit(p:Dynamic, ox:Float, oy:Float, oz:Float, depth:Int):Void {
        if (p == null || depth > 6) return;
        var cdb = "";
        try cdb = G.s(G.call("hrt.prefab.Prefab", "getCdbType", p)) catch (_:Dynamic) {}
        var x = G.number(G.field(p, "x")) + ox, y = G.number(G.field(p, "y")) + oy, z = G.number(G.field(p, "z")) + oz;
        if (cdb == "element") {
            scanElements++;
            var id = G.s(G.field(G.field(p, "props"), "id"));
            var gid = id == "" ? "" : gatherableOf(id);
            if (gid != "" && !nearScanned(x, y)) {
                scanGrid.set(cellKey(x, y), true);
                scanned.push({key: 200000 + scanned.length, id: id, gatherable: gid, x: x, y: y, z: z});
            }
            return;
        }
        if (cdb == "" && G.isA(p, "hrt.prefab.Reference")) {
            // a placed copy of a prefab file (the generic ore and plant nodes: ".../CopperOre_Small_Generic.prefab"): the file's name is the element's id
            var src = G.s(G.field(p, "source"));
            var cut = src.lastIndexOf("/");
            var base = src.substr(cut + 1);
            if (StringTools.endsWith(base, ".prefab")) base = base.substr(0, base.length - 7);
            scanRefs++;
            if (base != "") {
                if (scanRefSamples.length < 400 && !scanRefSeen.exists(base)) { scanRefSeen.set(base, true); scanRefSamples.push(base); }
                var rg = gatherableOf(base);
                if (rg == "") { rg = gatherableOf(base + "_Generic"); if (rg != "") base += "_Generic"; } // (the element of "CopperOre_Small" is "CopperOre_Small_Generic")
                if (rg != "" && !nearScanned(x, y)) {
                    scanGrid.set(cellKey(x, y), true);
                    scanned.push({key: 200000 + scanned.length, id: base, gatherable: rg, x: x, y: y, z: z});
                }
            }
            return;
        }
        var children = G.field(p, "_children");
        if (children != null) for (c in G.fastArray(children)) visit(c, x, y, z, depth + 1);
    }

    /** The nodes known now: the whole map's (read from the chunks), the world's element table and the ones seen (the last two only where the scan has none). */
    static function all():Array<NodeSpot> {
        var out = scanned.copy();
        for (s in spots) if (!nearScanned(s.x, s.y)) out.push(s);
        for (s in seen) if (!nearScanned(s.x, s.y)) out.push(s);
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
    public static function find(hero:Dynamic, plan:FarmPlan, visited:Map<Int, Float>, now:Float, obelisks:Array<Nav.ObeliskInfo>, ?ok:(Float, Float, Float) -> Bool, ?extra:(Float, Float, Float) -> Float):Null<{spot:NodeSpot, away:Float, count:Int}> {
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
            if (extra != null) cost += extra(s.x, s.y, s.z); // (what the caller knows of the way there: the reach map's yes costs nothing, an unknown way costs a detour)
            if (Math.isFinite(s.z) && Math.abs(s.z - hz) > 8) cost += Math.abs(s.z - hz) * 5; // another tier: the way there is a guess, the nodes of the hero's own tier come first
            if (cost < bestCost) { bestCost = cost; best = s; bestDirect = direct; }
        }
        return best == null ? null : {spot: best, away: bestDirect, count: usable};
    }

    /** Developer: reads every chunk at once and reports what was found (count by resource, how many loaded nodes the list holds). */
    public static function debugScan(hx:Float, hy:Float, loaded:Array<{x:Float, y:Float}>):Dynamic {
        var t0 = haxe.Timer.stamp();
        while (!scanFinished && haxe.Timer.stamp() - t0 < 20) scanStep(200);
        var byGid:Map<String, Int> = new Map();
        for (n in scanned) byGid.set(n.gatherable, (byGid.exists(n.gatherable) ? byGid.get(n.gatherable) : 0) + 1);
        var hits = 0;
        for (l in loaded) if (nearScanned(l.x, l.y)) hits++;
        return {finished: scanFinished, chunks: scanChunks == null ? -1 : scanChunks.length, chunksRead: scanPos, elementPrefabs: scanElements, references: scanRefs, referenceNames: scanRefSamples.slice(0, 150), nodes: scanned.length,
            seconds: Math.round((haxe.Timer.stamp() - t0) * 100) / 100, loadedNodes: loaded.length, loadedFoundInScan: hits,
            byGatherable: [for (k => v in byGid) k + "=" + v]};
    }

    /** The places of every known node of the wanted resources. */
    public static function wanted(plan:FarmPlan):Array<{x:Float, y:Float}> {
        build();
        var cache:Map<String, Bool> = new Map();
        var out = [];
        for (s in all()) {
            var w = cache.get(s.gatherable);
            if (w == null) { w = wants(s.gatherable, plan); cache.set(s.gatherable, w); }
            if (w) out.push({x: s.x, y: s.y});
        }
        return out;
    }

    /** The spots within `r` metres of (x, y) (the nodes of one outcrop are visited together). */
    public static function near(x:Float, y:Float, r:Float, ?z:Float):Array<NodeSpot> {
        return [for (s in all()) if ((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) <= r * r && (z == null || !Math.isFinite(z) || !Math.isFinite(s.z) || Math.abs(s.z - z) < 12)) s];
    }
}
