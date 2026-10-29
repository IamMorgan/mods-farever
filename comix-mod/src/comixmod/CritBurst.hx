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
    var world:Dynamic;
    var source:Dynamic;
    var shiftX = 0.0;
    var shiftY = 0.0;
    var anchored = false;
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
    public function show(s2d:Dynamic, position:Dynamic, widget:Dynamic, sc:Float):Void {
        clear();
        var tile = tile(NAMES[Std.random(NAMES.length)]);
        var box = G.create("h2d.Object", [s2d]);
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
        G.set(box, "visible", false);
        world = position;
        source = widget;
        shiftX = shiftY = 0;
        anchored = false;
        burst = box;
        age = 0;
    }

    public function update(dt:Float, on:Bool, s2d:Dynamic, s3d:Dynamic):Void {
        if (burst == null) return;
        age += dt;
        if (!on || age >= LIFETIME) return clear();
        // the burst follows the damage numbers' widget on the screen (they stand at the target); once the widget is gone, the projected hit position plus the last offset
        var point = G.call("h3d.Camera", "project", G.field(s3d, "camera"), [G.number(G.field(world, "x")), G.number(G.field(world, "y")),
            G.number(G.field(world, "z")), G.number(G.field(s2d, "width")), G.number(G.field(s2d, "height")), false, null]);
        var px = G.number(G.field(point, "x")), py = G.number(G.field(point, "y"));
        var wx = G.number(G.field(source, "absX")), wy = G.number(G.field(source, "absY"));
        if (G.field(source, "parent") != null && (wx != 0 || wy != 0)) {
            shiftX = wx - px;
            shiftY = wy - py;
            anchored = true;
        }
        if (anchored) {
            G.set(burst, "visible", true);
            G.set(burst, "x", px + shiftX + dx);
            G.set(burst, "y", py + shiftY + dy);
        }
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
    }
}
