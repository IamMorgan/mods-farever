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

    /** The burst joins the damage numbers' own `layer` (same level as the numbers), at a random place around the hit's world point `position`. */
    public function show(layer:Dynamic, position:Dynamic, sc:Float):Void {
        clear();
        var tile = tile(NAMES[Std.random(NAMES.length)]);
        var box = G.create("h2d.Object", [layer]);
        // the game's panels are flows: our child stays out of their layout, or the reflow never ends
        try G.set(G.call("h2d.Flow", "getProperties", layer, [box]), "isAbsolute", true) catch (_:Dynamic) {}
        G.call("h2d.Object", "addChildAt", layer, [box, 0]);
        var picture = G.create("h2d.Bitmap", [tile, box]);
        var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
        var ma = G.number(G.field(layer, "matA"), 1);
        var k = SIZE * sc / ma / Math.max(tw, th);
        G.call("h2d.Object", "setScale", picture, [k]);
        G.set(picture, "x", -tw * k / 2);
        G.set(picture, "y", -th * k / 2);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        // from half the picture's width to two widths away from the target's centre
        var width = Math.max(tw, th) * k;
        var angle = Math.random() * Math.PI * 2;
        var radius = width * (0.5 + Math.random() * 1.5);
        dx = Math.cos(angle) * radius;
        dy = Math.sin(angle) * radius;
        wx = G.number(G.field(position, "x"));
        wy = G.number(G.field(position, "y"));
        wz = G.number(G.field(position, "z"));
        this.layer = layer;
        G.set(box, "visible", false);
        burst = box;
        age = 0;
    }

    public function update(s2d:Dynamic, s3d:Dynamic, dt:Float, on:Bool):Void {
        if (burst == null) return;
        age += dt;
        if (!on || age >= LIFETIME || G.field(layer, "parent") == null) return clear();
        var spot = G.call("h3d.Camera", "project", G.field(s3d, "camera"), [wx, wy, wz,
            G.number(G.field(s2d, "width")), G.number(G.field(s2d, "height")), false, null]);
        var ma = G.number(G.field(layer, "matA"), 1), md = G.number(G.field(layer, "matD"), 1);
        G.set(burst, "x", (G.number(G.field(spot, "x")) - G.number(G.field(layer, "absX"))) / ma + dx);
        G.set(burst, "y", (G.number(G.field(spot, "y")) - G.number(G.field(layer, "absY"))) / md + dy);
        G.set(burst, "visible", true);
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
        layer = null;
    }
}
