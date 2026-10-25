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

    // ---- traps ----

    /** Words in an element's id that mark a trap (spikes, blades, flames, crushers, poison...). */
    static var TRAP_WORDS = ["trap", "spike", "sawblade", "buzzsaw", "blade", "thorn", "landmine", "bomb", "lava", "poison", "flame", "laser", "crusher", "piston",
        "acid", "needle", "caltrop", "geyser", "turret", "burn", "shock", "electr", "hazard", "explos", "toxic", "magma"];
    static var traps:Array<{x:Float, y:Float, z:Float, r:Float, id:String}> = [];
    static var trapsAt = -100.0;
    static var trapSeen:Map<String, Bool> = new Map();

    /** Every 2 s: the traps of the hero's layer (harmful trigger zones, spikes, crushers), told by the id of the element. */
    public static function refreshTraps(hero:Dynamic, now:Float):Void {
        if (now - trapsAt < 2.0) return;
        trapsAt = now;
        var found = [];
        try {
            for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                if (e == null || G.field(e, "removed") == true) continue;
                if (G.isA(e, "ent.interactible.Bumper") || G.isA(e, "ent.interactible.Gatherable") || G.isA(e, "ent.interactible.Obelisk")) continue;
                var id = G.s(G.field(G.field(e, "inf"), "id"));
                var isTrigger = G.isA(e, "ent.interactible.TriggerElement");
                var tid = isTrigger ? G.s(G.field(G.field(e, "triggerInf"), "id")) : "";
                var low = (id + " " + tid).toLowerCase();
                var hit = false;
                for (w in TRAP_WORDS) if (low.indexOf(w) >= 0) { hit = true; break; }
                var x = G.number(G.field(e, "posx")), y = G.number(G.field(e, "posy")), z = G.number(G.field(e, "posz"));
                if (!hit) {
                    // an unknown zone with effects is only noted (it may as well heal): the log tells what lies around
                    if (isTrigger && !trapSeen.exists("?" + id + tid) && G.len(G.field(G.field(e, "triggerInf"), "effects")) > 0
                        && (G.integer(G.field(G.field(e, "triggerInf"), "flags")) & WATER_FLAG) == 0) {
                        trapSeen.set("?" + id + tid, true);
                        Log.t("trap", "zone with effects NOT avoided (not told a trap by its name): " + id + " / " + tid + " at " + Math.round(x) + "," + Math.round(y) + "," + Math.round(z));
                    }
                    continue;
                }
                var r = isTrigger ? G.number(G.field(e, "hitRadius"), 1.5) * Math.max(1.0, G.number(G.field(e, "scaleX"), 1.0)) : 1.5;
                r = Math.max(1.2, Math.min(r, 12)) + 0.8;
                found.push({x: x, y: y, z: z, r: r, id: id});
                var k = id + Math.round(x) + "," + Math.round(y);
                if (!trapSeen.exists(k)) {
                    trapSeen.set(k, true);
                    Log.t("trap", "trap registered: " + id + " / " + tid + " (" + G.typeName(e) + ") at " + Math.round(x) + "," + Math.round(y) + "," + Math.round(z) + " radius " + Math.round(r * 10) / 10);
                }
            }
        } catch (error:Dynamic) Log.err("refreshTraps", error);
        traps = found;
    }

    /** True when (x, y) at about height z lies in a trap's area. */
    public static function trapAt(x:Float, y:Float, z:Float):Bool {
        for (t in traps) {
            if (Math.abs(t.z - z) > 5) continue;
            var dx = x - t.x, dy = y - t.y;
            if (dx * dx + dy * dy <= t.r * t.r) return true;
        }
        return false;
    }

    public static function trapCount():Int return traps.length;

    static var memo:Map<Int, Bool> = new Map();
    static var memoSince = 0.0;
    static var memoSize = 0;
    /** Fresh lookups still allowed to the callers that ask for `limited` answers (the dodge's map: thousands of cells a second). */
    public static var budget = 0;

    /**
     * `deadly` for a spot on a 0.5 m grid, remembered (the water does not move): the dodge asks about thousands of cells.
     * `z` is the height of the ground there (the water is compared with the ground, not with the hero's feet).
     */
    public static function wetCell(x:Float, y:Float, z:Float, margin:Float = 0.6, limited:Bool = false):Bool {
        var now = haxe.Timer.stamp();
        if (now - memoSince > 120 || memoSize > 200000) { memo = new Map(); memoSize = 0; memoSince = now; }
        var ix = Math.round(x * 2), iy = Math.round(y * 2);
        var k = (ix & 0x3FFF) | ((iy & 0x3FFF) << 14) | ((Math.round(z / 3) & 15) << 28);
        var known = memo.get(k);
        if (known != null) return known;
        if (limited) { if (budget <= 0) return false; budget--; }
        var bad = deadly(ix * 0.5, iy * 0.5, z, margin);
        memo.set(k, bad);
        memoSize++;
        return bad;
    }

    /**
     * True when a harmful spot lies on the straight line from (x0, y0) to (x1, y1), sampled every 0.5 m. The ground under each
     * sample is read (the lake below a bank is deeper than the hero's own height says).
     */
    public static function lineDeadly(x0:Float, y0:Float, x1:Float, y1:Float, z:Float):Bool {
        var dx = x1 - x0, dy = y1 - y0;
        var n = Std.int(Math.min(24, Math.ceil(Math.sqrt(dx * dx + dy * dy) / 0.5)));
        var ref = z;
        for (i in 1...n + 1) {
            var t = i / n;
            var px = x0 + dx * t, py = y0 + dy * t;
            var gz = AutoDodge.worldZ(px, py, ref, 2.2);
            if (!Math.isFinite(gz) || gz <= ref - 100) gz = AutoDodge.worldZ(px, py, ref - 30, 30);
            if (!Math.isFinite(gz) || gz <= ref - 100) continue;
            if (wetCell(px, py, gz, 0.5)) return true;
            ref = gz;
        }
        return false;
    }
}
