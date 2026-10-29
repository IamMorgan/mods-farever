package comixmod;

import comixmod.GameAccess as G;

private typedef Bubble = {box:Dynamic, hero:Dynamic, spot:Dynamic, left:Float};

/** Speech bubbles above the characters that wrote in the chat: one per character, a new message replaces the old one. */
class Bubbles {
    static inline var HEAD = 2.2; // world units above the character's feet
    var bubbles = new Map<String, Bubble>();
    var pending:Array<{uid:String, hero:Dynamic, spot:Dynamic, text:String}> = [];

    public function new() {}

    public function say(uid:String, hero:Dynamic, spot:Dynamic, text:String):Void {
        pending.push({uid: uid, hero: hero, spot: spot, text: text});
    }

    public function update(s2d:Dynamic, s3d:Dynamic, dt:Float, on:Bool, sc:Float):Void {
        if (!on || s2d == null || s3d == null) {
            pending = [];
            return clear();
        }
        for (p in pending) {
            drop(p.uid);
            bubbles.set(p.uid, {box: build(s2d, p.text, sc), hero: p.hero, spot: p.spot, left: Math.min(8, 3 + p.text.length * 0.06)});
        }
        pending = [];
        var camera = G.field(s3d, "camera");
        var width = G.number(G.field(s2d, "width")), height = G.number(G.field(s2d, "height"));
        for (uid in [for (k in bubbles.keys()) k]) {
            var b = bubbles.get(uid);
            b.left -= dt;
            if (b.left <= 0 || (b.hero != null && G.field(b.hero, "removed") == true)) {
                drop(uid);
                continue;
            }
            var at = b.hero != null ? b.hero : b.spot;
            var point = G.call("h3d.Camera", "project", camera, [G.number(G.field(at, "x")), G.number(G.field(at, "y")),
                G.number(G.field(at, "z")) + HEAD, width, height, false, null]);
            G.set(b.box, "x", G.number(G.field(point, "x")));
            G.set(b.box, "y", G.number(G.field(point, "y")));
        }
    }

    /** The bubble's origin is the tip of its tail; the oval stands above it. */
    static function build(s2d:Dynamic, text:String, sc:Float):Dynamic {
        var box = G.create("h2d.Object", [s2d]);
        var shapes = G.create("h2d.Graphics", [box]);
        var label = Fonts.text(box, text, 0x000000, sc, 240 * sc);
        var w = Fonts.width(label), h = Fonts.height(label);
        var rx = w / 2 * 1.3 + 12 * sc, ry = h / 2 * 1.3 + 8 * sc, tail = 16 * sc;
        var cy = -(tail + ry);
        var line = Math.max(2, 2 * sc);
        // the tail first: the oval's outline then covers where they meet
        Shapes.polygon(shapes, [-10 * sc, cy + ry - 3 * sc, 0, 0, 10 * sc, cy + ry - 3 * sc], 0xFFFFFF, 0x000000, line);
        Shapes.polygon(shapes, Shapes.ellipse(0, cy, rx, ry), 0xFFFFFF, 0x000000, line);
        G.set(label, "x", -w / 2);
        G.set(label, "y", cy - h / 2);
        return box;
    }

    function drop(uid:String):Void {
        var b = bubbles.get(uid);
        if (b != null) G.call("h2d.Object", "remove", b.box, []);
        bubbles.remove(uid);
    }

    public function clear():Void {
        for (uid in [for (k in bubbles.keys()) k]) drop(uid);
    }
}
