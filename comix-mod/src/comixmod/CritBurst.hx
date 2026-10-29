package comixmod;

import comixmod.GameAccess as G;

private typedef BurstStyle = {word:String, outer:Int, inner:Int, cloud:Bool, count:Int};

/** The comic burst of a critical hit: one at a time, a new crit replaces it, it never stays longer than LIFETIME. */
class CritBurst {
    static inline var LIFETIME = 2.0;
    static inline var FADE = 0.3;
    static inline var RED = 0xFF2A1A;
    static final STYLES:Array<BurstStyle> = [
        {word: "CRASH", outer: 0xFFD400, inner: 0xFFF2A8, cloud: false, count: 12},
        {word: "WHAM", outer: 0x2E9BFF, inner: 0xFFF2A8, cloud: false, count: 10},
        {word: "SNAP", outer: 0xFFC800, inner: 0xFFF6B8, cloud: false, count: 9},
        {word: "SMASH", outer: 0x35D0C0, inner: 0xB5F5EC, cloud: true, count: 8},
        {word: "BOOM", outer: 0x3FA8F0, inner: 0xBFE5FF, cloud: true, count: 7},
        {word: "CRACK", outer: 0x4CD964, inner: 0xFFF2A8, cloud: false, count: 11},
        {word: "BAM", outer: 0xE5322D, inner: 0xFFE27A, cloud: false, count: 9},
        {word: "GRRR", outer: 0x57C84D, inner: 0xD3F7B0, cloud: true, count: 9},
        {word: "POW", outer: 0x3FB6FF, inner: 0xFFFFFF, cloud: false, count: 10}
    ];

    var burst:Dynamic;
    var age = 0.0;

    public function new() {}

    public function show(s2d:Dynamic, x:Float, y:Float, amount:Int, sc:Float):Void {
        clear();
        var style = STYLES[Std.random(STYLES.length)];
        var box = G.create("h2d.Object", [s2d]);
        var shapes = G.create("h2d.Graphics", [box]);
        var shadow = 2 * sc;
        var wordShadow = Fonts.text(box, style.word, 0x000000, 1.2 * sc), word = Fonts.text(box, style.word, 0xFFFFFF, 1.2 * sc);
        var valueShadow = Fonts.text(box, Std.string(amount), 0x000000, 1.9 * sc), value = Fonts.text(box, Std.string(amount), RED, 1.9 * sc);
        var ww = Fonts.width(word), wh = Fonts.height(word), vw = Fonts.width(value), vh = Fonts.height(value);
        var radius = Math.max(60 * sc, Math.max(ww, vw) * 0.75 + 24 * sc);
        var turn = Math.random() * Math.PI;
        var line = Math.max(2, 3 * sc);
        Shapes.polygon(shapes, style.cloud ? Shapes.cloud(0, 0, radius, style.count, turn) : Shapes.star(0, 0, radius, radius * 0.62, style.count, turn),
            style.outer, 0x000000, line);
        Shapes.polygon(shapes, style.cloud ? Shapes.cloud(0, 0, radius * 0.72, style.count, turn) : Shapes.star(0, 0, radius * 0.7, radius * 0.45, style.count, turn),
            style.inner, 0x000000, line * 0.6);
        // the word sits above the value
        var top = -(wh + vh) / 2;
        place(word, wordShadow, -ww / 2, top, shadow);
        place(value, valueShadow, -vw / 2, top + wh, shadow);
        G.set(box, "x", x + 90 * sc);
        G.set(box, "y", y);
        G.set(box, "rotation", (Math.random() - 0.5) * 0.3);
        burst = box;
        age = 0;
    }

    static function place(front:Dynamic, back:Dynamic, x:Float, y:Float, shadow:Float):Void {
        G.set(back, "x", x + shadow);
        G.set(back, "y", y + shadow);
        G.set(front, "x", x);
        G.set(front, "y", y);
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
