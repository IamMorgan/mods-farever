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

    /** Digit colour that reads against each picture; every digit gets a black outline. */
    static final DIGITS:Map<String, Int> = ["wham" => 0xFFE000, "wow" => 0xFFE000, "ooops" => 0x1060FF, "kaboom" => 0x1060FF, "poof" => 0xE02020];

    var widget:Dynamic;
    var counter:Dynamic;
    var frames = 0;
    var fallbackX = 0.0;
    var fallbackY = 0.0;
    var half = 0.0;
    var sc = 1.0;

    /** The burst takes the game's own damage number (`counter` of `widget`) as its digits; it is put to the right of the widget once the game has placed it. */
    public function show(parent:Dynamic, widget:Dynamic, counter:Dynamic, x:Float, y:Float, sc:Float):Void {
        clear();
        var name = NAMES[Std.random(NAMES.length)];
        var tile = tile(name);
        var box = G.create("h2d.Object", [parent]);
        G.set(box, "visible", false);
        var picture = G.create("h2d.Bitmap", [tile, box]);
        var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
        var k = SIZE * sc / Math.max(tw, th);
        G.call("h2d.Object", "setScale", picture, [k]);
        G.set(picture, "x", -tw * k / 2);
        G.set(picture, "y", -th * k / 2);
        // the digits: the game's own text, bigger, with a black outline made of copies
        var color = DIGITS.exists(name) ? DIGITS.get(name) : 0xFFFFFF;
        G.call("domkit.Properties", "initStyle", G.field(counter, "dom"), ["color", color]);
        G.call("h2d.Text", "set_textColor", counter, [color]);
        var size = G.number(G.field(counter, "scaleX"), 1) * 1.6;
        var vw = G.number(G.call("h2d.Text", "get_textWidth", counter)) * size, vh = G.number(G.call("h2d.Text", "get_textHeight", counter)) * size;
        var value = G.text(G.field(counter, "text"));
        var o = 2.5 * sc;
        for (d in [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]]) {
            var t = G.create("h2d.Text", [G.field(counter, "font"), box]);
            G.call("h2d.Text", "set_text", t, [value]);
            G.call("h2d.Text", "set_textColor", t, [0x000000]);
            G.call("h2d.Object", "setScale", t, [size]);
            G.set(t, "x", -vw / 2 + d[0] * o);
            G.set(t, "y", -vh / 2 + d[1] * o);
        }
        G.call("h2d.Object", "addChild", box, [counter]);
        G.call("h2d.Object", "setScale", counter, [size]);
        G.set(counter, "x", -vw / 2);
        G.set(counter, "y", -vh / 2);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        burst = box;
        age = 0;
        this.widget = widget;
        this.counter = counter;
        frames = 0;
        fallbackX = x;
        fallbackY = y;
        half = tw * k / 2;
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
            G.set(burst, "x", wx + half + 40 * sc);
            G.set(burst, "y", wy);
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
        counter = null;
    }
}
