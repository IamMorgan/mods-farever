package farmer;

import farmer.GameAccess as G;

/**
 * The solid things the ground heights do not show: benches, posts, flower beds, statues. They are bodies of the game's physics
 * world (the hero's body collides with them), so they are found with the game's own ray cast (World.raycast, mask 4 = physics bodies).
 */
class Solid {
    /** The ray mask bit of physics bodies (World.raycast tests `mask & 4`). */
    static inline var BODIES = 4;
    static var from:Dynamic;
    static var to:Dynamic;
    static var world:Dynamic;
    /** False once the cast failed (the planner then works from the heights alone). */
    public static var works = true;
    public static var error = "";

    /** The distance to the first body on the segment, -1 when the way is free (NaN when the cast failed). */
    public static function ray(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, mask:Int = BODIES):Float {
        if (!works) return Math.NaN;
        try {
            if (world == null) world = G.current("world.World", "inst");
            if (from == null) {
                from = G.create("h3d.VectorImpl", [0.0, 0.0, 0.0]);
                to = G.create("h3d.VectorImpl", [0.0, 0.0, 0.0]);
            }
            G.set(from, "x", x0); G.set(from, "y", y0); G.set(from, "z", z0);
            G.set(to, "x", x1); G.set(to, "y", y1); G.set(to, "z", z1);
            return G.number(G.call("world.World", "raycast", world, [from, to, mask]), -1);
        } catch (e:Dynamic) {
            works = false;
            error = Std.string(e);
            Log.t("nav", "Solid.ray failed: " + error);
            return Math.NaN;
        }
    }

    /** True when the box touches the bounds of a physics body (a cheap test of the broad phase; a hit may still miss the body itself). */
    public static function anyBox(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float):Bool {
        if (!works) return false;
        try {
            if (world == null) world = G.current("world.World", "inst");
            return G.call("world.World", "hasPhysicsBodies", world, [x0, y0, z0, x1, y1, z1]) == true;
        } catch (e:Dynamic) {
            works = false;
            error = Std.string(e);
            Log.t("nav", "Solid.anyBox failed: " + error);
            return false;
        }
    }

    /**
     * A body in the cell around (x, y) whose ground is at z, at the height of the hero's legs and waist: a bench, a post, a flower
     * bed, a statue. Two bands of rays cross the cell on both axes, a little off the middle too (a thin post is easy to miss).
     * The cell's own edge is not tested (a ledge's face stands there), only 0.45 m round the middle.
     */
    public static function blocksCell(x:Float, y:Float, z:Float):Bool {
        if (!works) return false;
        if (!anyBox(x - 0.45, y - 0.45, z + 0.4, x + 0.45, y + 0.45, z + 1.4)) return false;
        for (h in [0.45, 1.0]) {
            for (off in [-0.3, 0.0, 0.3]) {
                if (ray(x - 0.45, y + off, z + h, x + 0.45, y + off, z + h) >= 0) return true;
                if (ray(x + off, y - 0.45, z + h, x + off, y + 0.45, z + h) >= 0) return true;
            }
        }
        return false;
    }
}
