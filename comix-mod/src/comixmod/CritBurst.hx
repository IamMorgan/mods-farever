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
    var wx = 0.0;
    var wy = 0.0;
    var wz = 0.0;
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

    /** The burst lives on the scene and stays at a fixed world point (the hit position); `dx`, `dy` is its random offset on the screen. */
    public function show(s2d:Dynamic, position:Dynamic, sc:Float):Void {
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
        // random place around the target: from half the picture's width to two widths away from its centre
        var width = Math.max(tw, th) * k;
        var angle = Math.random() * Math.PI * 2;
        var radius = width * (0.5 + Math.random() * 1.5);
        dx = Math.cos(angle) * radius;
        dy = Math.sin(angle) * radius;
        wx = G.number(G.field(position, "x"));
        wy = G.number(G.field(position, "y"));
        wz = G.number(G.field(position, "z"));
        G.set(box, "visible", false);
        burst = box;
        age = 0;
    }

    public function update(s2d:Dynamic, s3d:Dynamic, dt:Float, on:Bool):Void {
        if (burst == null) return;
        age += dt;
        if (!on || age >= LIFETIME) return clear();
        var point = G.call("h3d.Camera", "project", G.field(s3d, "camera"), [wx, wy, wz,
            G.number(G.field(s2d, "width")), G.number(G.field(s2d, "height")), false, null]);
        G.set(burst, "x", G.number(G.field(point, "x")) + dx);
        G.set(burst, "y", G.number(G.field(point, "y")) + dy);
        G.set(burst, "visible", true);
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
    }
}
