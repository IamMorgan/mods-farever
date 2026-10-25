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
    static inline var NX = 100;
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

    static function wanted(index:Int, level:Int):Bool {
        var l = levels[index];
        return l >= level && l <= level + 2;
    }

    /**
     * The best hunting ground for a hero of `level`, not in `visited` (cell -> time until which it is left alone): a spot in the
     * middle of a zone of the right level, near the hero or near an opened obelisk (the flight costs little).
     */
    public static function find(hero:Dynamic, level:Int, visited:Map<Int, Float>, now:Float, obelisks:Array<Nav.ObeliskInfo>):Null<{key:Int, x:Float, y:Float, zone:String, level:Int, away:Float}> {
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
            if (around < 5) continue;
            var x = X0 + ix * STEP, y = Y0 + iy * STEP;
            var direct = Math.sqrt((x - hx) * (x - hx) + (y - hy) * (y - hy));
            var viaObelisk = Math.POSITIVE_INFINITY;
            for (o in obelisks) viaObelisk = Math.min(viaObelisk, Math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)) + 120);
            var cost = Math.min(direct, viaObelisk) + (levels[index] - level) * 40;
            if (cost < bestCost) { bestCost = cost; best = {key: index, x: x, y: y, zone: ids[index], level: levels[index], away: direct}; }
        }
        return best;
    }
}
