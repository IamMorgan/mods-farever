package farmer;

import farmer.GameAccess as G;

typedef Pad = {id:String, x:Float, y:Float, z:Float, force:Float, ux:Float, uy:Float, uz:Float, entity:Dynamic};

/**
 * The bumpers ("dandelions", the trampolines of the world): stepping on one throws the hero along the bumper's up vector. They are the
 * way up onto ledges and islands no path leads to, so the planner (NavGrid) treats each as a launch: from the pad's cell the hero lands
 * on any higher ground within the flight's reach. The flight is measured in the game (watch) and the figures learnt are kept in `rise`.
 */
class Pads {
    /** The pads of the loaded world, nearest first when asked (see `near`). */
    public static var list:Array<Pad> = [];
    static var scannedAt = -100.0;
    /** How high above the pad a flight went (m), per kind of pad (measured). */
    static var riseById:Map<String, Float> = new Map();
    /** Measured rise / the rise the force promises, over the pads measured so far: scales the pads not measured yet. */
    static var riseScale = 1.0;
    /** The farthest the hero got from the pad sideways in a steered flight (m; 0: not yet measured). */
    public static var reach = 0.0;
    /** How far sideways the last flight went (m). */
    public static var lastOut = 0.0;
    /** The rise a flight is expected to make when nothing is measured yet: the force as a launch speed under the hero's own gravity. */
    static inline var GRAVITY = 47.0;

    public static function scan(hero:Dynamic, now:Float):Void {
        if (now - scannedAt < 3) return;
        scannedAt = now;
        var out:Array<Pad> = [];
        try {
            for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Bumper") || G.field(e, "enabled") == false) continue;
                var id = G.s(G.field(G.field(e, "inf"), "id"));
                var bumper = G.field(G.field(G.field(e, "inf"), "props"), "bumper");
                var force = bumper == null ? 0.0 : G.number(G.field(bumper, "force"), 0);
                if (force <= 0) continue;
                var ux = 0.0, uy = 0.0, uz = 1.0;
                try {
                    var up = G.call("ent.EntityTransform", "getUp", G.field(e, "trigger"));
                    ux = G.number(G.field(up, "x")); uy = G.number(G.field(up, "y")); uz = G.number(G.field(up, "z"), 1);
                } catch (_:Dynamic) {}
                out.push({id: id, x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy")), z: G.number(G.field(e, "posz")), force: force, ux: ux, uy: uy, uz: uz, entity: e});
            }
        } catch (_:Dynamic) {}
        list = out;
    }

    /** Developer: every pad with what the game says about it. */
    public static function describe(hero:Dynamic):Array<String> {
        var rows = [];
        scannedAt = -100;
        scan(hero, haxe.Timer.stamp());
        for (p in list) {
            var bumper = G.field(G.field(G.field(p.entity, "inf"), "props"), "bumper");
            rows.push(p.id + " at " + Math.round(p.x) + "," + Math.round(p.y) + "," + Math.round(p.z) + " force " + p.force + " up " + Math.round(p.ux * 100) / 100 + "," + Math.round(p.uy * 100) / 100 + "," + Math.round(p.uz * 100) / 100
                + " centerAttraction " + G.field(bumper, "centerAttraction") + " resetVelocity " + G.field(bumper, "resetVelocity") + " d=" + Math.round(Nav.distance(hero, p.x, p.y)));
        }
        return rows;
    }

    /** The rise above a pad's cell the planner counts on (a measured flight, else a modest figure from the force). */
    public static function expectedRise(p:Pad):Float {
        var known = riseById.get(p.id);
        if (known != null) return Math.max(2.0, known - 0.5);
        return Math.min(60.0, p.force * p.force * p.uz * p.uz / (2 * GRAVITY) * riseScale);
    }

    /** A flight that missed its landing: the reach is cut to what was really made. */
    public static function shrink():Void {
        if (lastOut <= 0) return;
        reach = Math.max(14.0, (reach > 0 ? reach : MAX_REACH) * 0.9);
        Log.t("nav", "BUMP reach cut to " + Math.round(reach) + " m");
    }

    /** How far sideways a flight from a pad can be steered (m): measured, else a modest figure (the glider falls slowly). */
    public static function expectedReach(p:Pad):Float {
        return reach > 0 ? Math.min(MAX_REACH, reach) : MAX_REACH;
    }

    /** The widest a throw is planned (m): the rise, then the glider (about 2.4 m forward per metre of sinking, planned with 1.8). */
    static inline var MAX_REACH = 36.0;
    public static inline var GLIDE_RATIO = 1.8;
    /** The sideways way of the rising part of a throw (m). */
    public static inline var RISE_RUN = 10.0;

    // ---- measuring a flight ----

    static var armedPad:Pad = null;
    static var flightPad:Pad = null;
    static var flightT0 = 0.0;
    static var flightX0 = 0.0;
    static var flightY0 = 0.0;
    static var flightZ0 = 0.0;
    static var flightPeak = 0.0;
    static var flightMaxReach = 0.0;
    static var flightGlided = false;
    static var flightLogAt = 0.0;
    static var flightProfile:Array<String> = [];

    /** True while a flight that started on a pad is going on. */
    public static function flying():Bool return flightPad != null;

    /** Every frame: notices a throw (the hero near a pad rises quickly) and logs the flight, keeping the figures learnt. */
    public static function watch(hero:Dynamic, now:Float, groundZ:Float):Void {
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        if (flightPad == null) {
            armedPad = null;
            for (p in list) if (Math.abs(p.x - hx) < 2.0 && Math.abs(p.y - hy) < 2.0 && Math.abs(p.z - hz) < 3.0) { armedPad = p; break; }
            if (armedPad != null && hz - groundZ > 2.5 && hz > armedPad.z + 1.0) {
                flightPad = armedPad;
                flightT0 = now; flightX0 = hx; flightY0 = hy; flightZ0 = armedPad.z;
                flightPeak = 0; flightMaxReach = 0; flightGlided = false; flightLogAt = now; flightProfile = [];
                Log.t("nav", "BUMP: thrown from " + flightPad.id + " at " + Math.round(flightPad.x) + "," + Math.round(flightPad.y) + "," + Math.round(flightPad.z) + " (force " + flightPad.force + ")");
            }
            return;
        }
        var above = hz - flightZ0;
        if (above > flightPeak) flightPeak = above;
        var out = Math.sqrt((hx - flightPad.x) * (hx - flightPad.x) + (hy - flightPad.y) * (hy - flightPad.y));
        if (out > flightMaxReach) flightMaxReach = out;
        if (G.field(hero, "gliding") == true) flightGlided = true;
        if (now - flightLogAt >= 0.5) {
            flightLogAt = now;
            if (flightProfile.length < 60) flightProfile.push(Math.round((now - flightT0) * 10) / 10 + ":" + Math.round(above) + "/" + Math.round(out) + (G.field(hero, "gliding") == true ? "g" : ""));
        }
        var landed = hz - groundZ < 0.3 && now - flightT0 > 0.6;
        if (landed || now - flightT0 > 40) {
            Log.t("nav", "BUMP flight over after " + Math.round((now - flightT0) * 10) / 10 + " s: peak " + Math.round(flightPeak * 10) / 10 + " m above the pad, farthest " + Math.round(flightMaxReach) + " m sideways, landed at "
                + Math.round(hx) + "," + Math.round(hy) + "," + Math.round(hz) + " (" + Math.round(hz - flightZ0) + " m above the pad), glided " + flightGlided + " | t:rise/out " + flightProfile.join(" "));
            lastOut = Math.sqrt((hx - flightPad.x) * (hx - flightPad.x) + (hy - flightPad.y) * (hy - flightPad.y));
            if (landed && flightPeak > 2) {
                riseById.set(flightPad.id, flightPeak);
                var promised = flightPad.force * flightPad.force * flightPad.uz * flightPad.uz / (2 * GRAVITY);
                if (promised > 0.5) riseScale = Math.max(0.2, Math.min(4.0, flightPeak / promised));
            }
            flightPad = null;
        }
    }
}
