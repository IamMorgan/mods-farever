package farmer;

import farmer.GameAccess as G;

/**
 * Where the monsters of the hero's level live. The game only loads the monsters near the hero, so for a far hunting ground the
 * bot needs the map: the world's zones (Data.zone) have a level each, and World.getZone answers for any spot, loaded or not. A
 * coarse grid of the main world is read once (a little each frame); the nearest cells whose zone level is the hero's own (up to +2)
 * are the hunting grounds. The bot goes there (by obelisk when far, see Nav.travel) and the monsters load as it arrives.
 */
class Hunt {
    static inline var STEP = 32.0;
    static inline var X0 = -1250.0;
    static inline var Y0 = -850.0;
    static inline var NX = 112;
    static inline var NY = 96;
    static inline var SAMPLE_Z = 100.0;

    static var levels:Array<Int> = [];
    static var ids:Array<String> = [];
    static var next = 0;

    public static function ready():Bool return next >= NX * NY;

    /** True on the big world map (the dungeons and instances have no such zones). */
    public static function onWorld(hero:Dynamic):Bool {
        try return StringTools.startsWith(G.s(G.field(G.call("ent.Hero", "getWorldLocation", hero), "mapId")), "World/") catch (_:Dynamic) return false;
    }

    /** Reads the next `budget` cells of the grid. */
    public static function scan(budget:Int):Void {
        if (levels.length == 0) {
            levels = [for (_ in 0...NX * NY) 0];
            ids = [for (_ in 0...NX * NY) ""];
            Log.t("hunt", "zone map: reading " + NX * NY + " spots (every " + STEP + " m)");
        }
        var world = G.current("world.World", "inst");
        if (world == null) return;
        while (budget-- > 0 && next < NX * NY) {
            var ix = next % NX, iy = Std.int(next / NX);
            try {
                var zone = G.call("world.World", "getZone", world, [X0 + ix * STEP, Y0 + iy * STEP, SAMPLE_Z, null]);
                if (zone != null) {
                    levels[next] = G.integer(G.field(zone, "level"));
                    ids[next] = G.s(G.field(zone, "id"));
                }
            } catch (_:Dynamic) {}
            next++;
            if (next >= NX * NY) {
                var counts:Map<Int, Int> = new Map();
                for (l in levels) counts.set(l, (counts.exists(l) ? counts.get(l) : 0) + 1);
                Log.t("hunt", "zone map ready; spots by zone level: " + [for (l => n in counts) l + "x" + n].join(" "));
            }
        }
    }

    /** The grid cells within `r` cells of `key` (itself included). */
    public static function around(key:Int, r:Int):Array<Int> {
        var out = [];
        var ix = key % NX, iy = Std.int(key / NX);
        for (dy in -r...r + 1) for (dx in -r...r + 1) {
            var jx = ix + dx, jy = iy + dy;
            if (jx >= 0 && jy >= 0 && jx < NX && jy < NY) out.push(jy * NX + jx);
        }
        return out;
    }

    /** Is there any ground on the map whose zone level is the hero's own (up to +wide)? When none is, only lower monsters are left to fight. */
    public static function groundExists(level:Int, wide:Int):Bool {
        if (!ready()) return true; // (not read yet: nothing is known, so nothing is given up)
        for (l in levels) if (l >= level && l <= level + wide) return true;
        return false;
    }

    static var spread = 2;
    static var allow:Map<Int, Bool> = null;
    static var allowZones:Map<String, Bool> = null;

    /**
     * The zones (ids) where any of the monsters lives, from the game's own spawner tables (HSpawner.unitZones: monster -> zones). The
     * whole map is searched with them, not just the zone of the hero's level.
     */
    public static function zonesOf(unitIds:Array<String>):Map<String, Bool> {
        var out = new Map<String, Bool>();
        try {
            var table = G.current("HSpawner", "unitZones");
            for (u in unitIds) {
                var zs = G.call("haxe.ds.StringMap", "get", table, [u]);
                if (zs == null) continue;
                for (z in G.fastArray(zs)) out.set(G.s(z), true);
            }
        } catch (_:Dynamic) {}
        return out;
    }

    /** How many grid spots lie in any of the zones (to tell a usable zone set from an empty one). */
    public static function spotsIn(zones:Map<String, Bool>):Int {
        var n = 0;
        for (z in ids) if (zones.exists(z)) n++;
        return n;
    }

    static function wanted(index:Int, level:Int):Bool {
        if (allowZones != null) return allowZones.exists(ids[index]);
        var l = levels[index];
        if (allow != null) return allow.exists(l);
        return l >= level && l <= level + spread;
    }

    /**
     * The best hunting ground for a hero of `level`, not in `visited` (cell -> time until which it is left alone): a spot in the
     * middle of a zone of the right level, near the hero or near an opened obelisk (the flight costs little).
     */
    public static function find(hero:Dynamic, level:Int, visited:Map<Int, Float>, now:Float, obelisks:Array<Nav.ObeliskInfo>, ?wide:Int, ?zoneLevels:Array<Int>, ?zoneIds:Map<String, Bool>, ?ok:(Float, Float) -> Bool):Null<{key:Int, x:Float, y:Float, zone:String, level:Int, away:Float}> {
        spread = wide == null ? 2 : wide;
        allow = null;
        allowZones = zoneIds;
        if (zoneLevels != null) { allow = new Map(); for (l in zoneLevels) for (d in 0...spread + 1) allow.set(l + d, true); }
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        var best = null;
        var bestCost = Math.POSITIVE_INFINITY;
        for (index in 0...NX * NY) {
            if (!wanted(index, level)) continue;
            var until = visited.get(index);
            if (until != null && now < until) continue;
            var ix = index % NX, iy = Std.int(index / NX);
            // the middle of a zone: most of the eight neighbours are of the same kind (not a border strip)
            var around = 0;
            for (dy in -1...2) for (dx in -1...2) {
                if (dx == 0 && dy == 0) continue;
                var jx = ix + dx, jy = iy + dy;
                if (jx >= 0 && jy >= 0 && jx < NX && jy < NY && wanted(jy * NX + jx, level)) around++;
            }
            if (around < (allowZones != null ? 2 : 5)) continue; // (the places of a monster's own zones may be narrow)
            var x = X0 + ix * STEP, y = Y0 + iy * STEP;
            if (ok != null && !ok(x, y)) continue; // (the reach map says no way leads there: the hero is on a closed island)
            var direct = Math.sqrt((x - hx) * (x - hx) + (y - hy) * (y - hy));
            // by obelisk: the walk to the obelisk nearest the hero, the flight, the walk from the obelisk nearest the ground (the flight is cheap but
            // not free: a hero that is far from every obelisk gains nothing, and the cost may not make a far continent look near)
            var viaObelisk = Math.POSITIVE_INFINITY;
            if (obelisks.length >= 2) {
                var toHero = Math.POSITIVE_INFINITY, fromGround = Math.POSITIVE_INFINITY;
                for (o in obelisks) {
                    toHero = Math.min(toHero, Math.sqrt((hx - o.x) * (hx - o.x) + (hy - o.y) * (hy - o.y)));
                    fromGround = Math.min(fromGround, Math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)));
                }
                viaObelisk = toHero + fromGround + 150;
            }
            var cost = Math.min(direct, viaObelisk) + (allow != null || allowZones != null ? 0 : (levels[index] - level) * 40);
            if (allowZones != null && allow == null && levels[index] < level) cost += (level - levels[index]) * 60; // (a zone the map calls lower has fewer monsters of the hero's level)
            if (cost < bestCost) { bestCost = cost; best = {key: index, x: x, y: y, zone: ids[index], level: levels[index], away: direct}; }
        }
        return best;
    }
}
