package farmer;

import farmer.GameAccess as G;

/**
 * Where the hero must not step: the terrain's liquids. Water is told by the game's own function (World.getWaterLevel: the
 * surface height of the liquid in a spot, -infinity without water); any other liquid of the terrain (lava, poison) is told by the
 * liquid record of the cell (Cell.getLiquid) in the game's trigger-zone sheet: a liquid that has effects hurts.
 * Nothing is written to the game: the questions are the ones the game asks itself every frame about the hero.
 */
class Hazard {
    static inline var WATER_DEPTH = 0.1;
    static inline var WATER_FLAG = 8;

    static var world:Dynamic;
    static var kinds:Map<String, Bool> = new Map();

    static function waterAt(x:Float, y:Float, groundZ:Float):Bool {
        var level = G.number(G.call("world.World", "getWaterLevel", world, [x, y, groundZ + 0.6]), Math.NEGATIVE_INFINITY);
        return level > groundZ + WATER_DEPTH;
    }

    /**
     * True when the ground at (x, y), `groundZ` high, lies under water or in a harmful liquid. With `margin` > 0 the water within
     * that distance of the spot (up, down, left, right) counts too: a path along the edge of a lake keeps the hero's body dry.
     */
    public static function deadly(x:Float, y:Float, groundZ:Float, margin:Float = 0):Bool {
        try {
            if (world == null) world = G.current("world.World", "inst");
            if (world == null) return false;
            var probe = groundZ + 0.6;
            if (waterAt(x, y, groundZ)) return true;
            if (margin > 0 && (waterAt(x + margin, y, groundZ) || waterAt(x - margin, y, groundZ) || waterAt(x, y + margin, groundZ) || waterAt(x, y - margin, groundZ))) return true;
            var cell = G.call("world.World", "getCellFromWorld", world, [x, y, probe, null]);
            if (cell == null) return false;
            var layer = G.call("world.terrain.CellDataProxy", "getClosestInterval", cell, [probe]);
            var liquid = G.call("world.terrain.CellDataProxy", "getLiquid", layer == null ? cell : layer);
            if (liquid == null) return false;
            return harmful(G.s(G.field(liquid, "kind")));
        } catch (_:Dynamic) {
            return false;
        }
    }

    /** A liquid kind (a row of the trigger-zone sheet) that is water or has effects of its own. */
    static function harmful(kind:String):Bool {
        if (kind == "") return false;
        var known = kinds.get(kind);
        if (known != null) return known;
        var bad = false;
        for (rec in G.sheet("triggerZone")) {
            if (G.s(G.field(rec, "id")) != kind) continue;
            bad = (G.integer(G.field(rec, "flags")) & WATER_FLAG) != 0 || G.len(G.field(rec, "effects")) > 0;
            break;
        }
        kinds.set(kind, bad);
        return bad;
    }

    /** True when the hero stands in water (the game's own water state of its body). */
    public static function heroInLiquid(hero:Dynamic):Bool {
        try return G.integer(G.call("ent.Entity", "checkWaterState", hero)) != 0 catch (_:Dynamic) return false;
    }

    /** True when a harmful spot lies on the straight line from (x0, y0) to (x1, y1), sampled every ~0.7 m. */
    public static function lineDeadly(x0:Float, y0:Float, x1:Float, y1:Float, z:Float):Bool {
        var dx = x1 - x0, dy = y1 - y0;
        var n = Std.int(Math.min(6, Math.ceil(Math.sqrt(dx * dx + dy * dy) / 0.7)));
        for (i in 1...n + 1) {
            var t = i / n;
            if (deadly(x0 + dx * t, y0 + dy * t, z)) return true;
        }
        return false;
    }
}
