package comixmod;

import comixmod.GameAccess as G;

/** The comic burst of a critical hit: one at a time, a new crit replaces it, it never stays longer than LIFETIME. */
class CritBurst {
    static inline var LIFETIME = 2.0;
    static inline var FADE = 0.3;
    static inline var SIZE = 240.0; // the longer side, px at 1080p
    static final NAMES = ["wham", "crush", "boom", "smack", "pow", "ooops", "crack", "wow", "kaboom", "poof", "bam"];

    var tiles = new Map<String, Dynamic>();
    var burst:Dynamic;
    var layer:Dynamic;
    var dx = 0.0;
    var dy = 0.0;
    var age = 0.0;

    public function new() {}

    /** The picture of a burst (bursts/<name>.png of the mod's folder), loaded once. */
    function tile(name:String):Dynamic {
        if (!tiles.exists(name)) {
            var path = "hlx/mods/" + HlxRuntime.moduleName() + "/bursts/" + name + ".png";
            var any = G.staticCall("hxd.res.Any", "fromBytes", [path, G.staticCall("sys.io.File", "getBytes", [path])]);
            tiles.set(name, G.call("hxd.res.Any", "toTile", any));
        }
        return tiles.get(name);
    }

    var lastAngle = -10.0;

    /** The burst lives on the scene (not in the game's panels) and follows `target`, the damage numbers' layer whose origin is the target. */
    public function show(s2d:Dynamic, target:Dynamic, sc:Float):Void {
        clear();
        var tile = tile(NAMES[Std.random(NAMES.length)]);
        var box = G.create("h2d.Object", [s2d]);
        // under everything 2D, so the damage numbers stay above it
        G.call("h2d.Object", "addChildAt", s2d, [box, 0]);
        var picture = G.create("h2d.Bitmap", [tile, box]);
        var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
        var k = SIZE * sc / Math.max(tw, th);
        G.call("h2d.Object", "setScale", picture, [k]);
        G.set(picture, "x", -tw * k / 2);
        G.set(picture, "y", -th * k / 2);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        // a full burst size plus a margin away from the target, so it does not cover the numbers around it
        var angle = Math.random() * Math.PI * 2;
        while (Math.abs(Math.atan2(Math.sin(angle - lastAngle), Math.cos(angle - lastAngle))) < 1.2) angle = Math.random() * Math.PI * 2;
        lastAngle = angle;
        var radius = Math.max(tw, th) * k + 60 * sc;
        dx = Math.cos(angle) * radius;
        dy = Math.sin(angle) * radius;
        layer = target;
        burst = box;
        G.set(box, "visible", false);
        age = 0;
    }

    public function update(dt:Float, on:Bool):Void {
        if (burst == null) return;
        age += dt;
        if (!on || age >= LIFETIME || G.field(layer, "parent") == null) return clear();
        var x = G.number(G.field(layer, "absX")), y = G.number(G.field(layer, "absY"));
        G.set(burst, "visible", x != 0 || y != 0);
        G.set(burst, "x", x + dx);
        G.set(burst, "y", y + dy);
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
        layer = null;
    }
}
