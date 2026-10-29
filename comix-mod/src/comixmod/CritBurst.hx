package comixmod;

import comixmod.GameAccess as G;

/** The comic burst of a critical hit: one at a time, a new crit replaces it, it never stays longer than LIFETIME. */
class CritBurst {
    static inline var LIFETIME = 2.0;
    static inline var FADE = 0.3;
    static inline var SIZE = 240.0; // the longer side, px at 1080p
    static inline var RED = 0xFF2A1A;
    static final NAMES = ["wham", "crush", "boom", "smack", "pow", "ooops", "crack", "wow", "kaboom", "poof", "bam"];

    var tiles = new Map<String, Dynamic>();
    var burst:Dynamic;
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

    /** `x`,`y` is the target on the layer; the burst stands to the right of it, the damage number is in its middle. */
    public function show(parent:Dynamic, x:Float, y:Float, amount:Int, sc:Float):Void {
        clear();
        var tile = tile(NAMES[Std.random(NAMES.length)]);
        var box = G.create("h2d.Object", [parent]);
        var picture = G.create("h2d.Bitmap", [tile, box]);
        var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
        var k = SIZE * sc / Math.max(tw, th);
        G.call("h2d.Object", "setScale", picture, [k]);
        G.set(picture, "x", -tw * k / 2);
        G.set(picture, "y", -th * k / 2);
        // the number: red with a dark outline, centred over the burst
        var size = 1.9 * sc;
        var value = Std.string(amount);
        var vw = 0.0, vh = 0.0;
        for (d in [[-1, 0], [1, 0], [0, -1], [0, 1], [0, 0]]) {
            var t = Fonts.text(box, value, d[0] == 0 && d[1] == 0 ? RED : 0x000000, size);
            vw = Fonts.width(t);
            vh = Fonts.height(t);
            G.set(t, "x", -vw / 2 + d[0] * sc * 1.5);
            G.set(t, "y", -vh / 2 + d[1] * sc * 1.5);
        }
        G.set(box, "x", x + tw * k / 2 + 110 * sc);
        G.set(box, "y", y);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        burst = box;
        age = 0;
    }

    public function update(dt:Float, on:Bool):Void {
        if (burst == null) return;
        age += dt;
        if (!on || age >= LIFETIME) return clear();
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
    }
}
