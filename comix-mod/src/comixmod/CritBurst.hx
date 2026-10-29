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

    var widget:Dynamic;
    var frames = 0;
    var fallbackX = 0.0;
    var fallbackY = 0.0;
    var half = 0.0;
    var sc = 1.0;
    var lastAngle = -10.0;

    /** The burst stands at a random side of the damage number's `widget` (it is placed once the game has put the widget at the target), never at the side of the previous one. */
    public function show(parent:Dynamic, widget:Dynamic, x:Float, y:Float, sc:Float):Void {
        clear();
        var tile = tile(NAMES[Std.random(NAMES.length)]);
        var box = G.create("h2d.Object", [parent]);
        G.set(box, "visible", false);
        var picture = G.create("h2d.Bitmap", [tile, box]);
        var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
        var k = SIZE * sc / Math.max(tw, th);
        G.call("h2d.Object", "setScale", picture, [k]);
        G.set(picture, "x", -tw * k / 2);
        G.set(picture, "y", -th * k / 2);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        burst = box;
        age = 0;
        this.widget = widget;
        frames = 0;
        fallbackX = x;
        fallbackY = y;
        half = Math.max(tw, th) * k / 2;
        this.sc = sc;
    }

    public function update(dt:Float, on:Bool):Void {
        if (burst == null) return;
        if (frames >= 0 && ++frames >= 3) {
            // by now the game has put the damage number's widget at the target
            var wx = G.number(G.field(widget, "x")), wy = G.number(G.field(widget, "y"));
            if (wx == 0 && wy == 0) {
                wx = fallbackX;
                wy = fallbackY;
            }
            trace("[comix-mod] crit widget " + wx + "," + wy);
            var angle = Math.random() * Math.PI * 2;
            while (Math.abs(Math.atan2(Math.sin(angle - lastAngle), Math.cos(angle - lastAngle))) < 1.2) angle = Math.random() * Math.PI * 2;
            lastAngle = angle;
            var radius = half + 50 * sc;
            G.set(burst, "x", wx + Math.cos(angle) * radius);
            G.set(burst, "y", wy + Math.sin(angle) * radius);
            G.set(burst, "visible", true);
            frames = -1;
        }
        age += dt;
        if (!on || age >= LIFETIME) return clear();
        G.set(burst, "alpha", Math.min(1, (LIFETIME - age) / FADE));
    }

    public function clear():Void {
        if (burst != null) G.call("h2d.Object", "remove", burst, []);
        burst = null;
        widget = null;
    }
}
