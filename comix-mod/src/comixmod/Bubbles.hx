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

    static inline var MAX_LINES = 3;

    /** The bubble's origin is the tip of its tail; the cloud stands above it. */
    static function build(s2d:Dynamic, text:String, sc:Float):Dynamic {
        var box = G.create("h2d.Object", [s2d]);
        var shapes = G.create("h2d.Graphics", [box]);
        var label = Fonts.text(box, text, 0x000000, sc, 160 * sc);
        // too long: cut the end off and put "..." there
        G.call("h2d.Text", "set_text", label, ["A"]);
        var maxHeight = Fonts.height(label) * MAX_LINES + 1;
        G.call("h2d.Text", "set_text", label, [text]);
        var shown = text;
        while (Fonts.height(label) > maxHeight && shown.length > 1) {
            shown = StringTools.rtrim(shown.substr(0, shown.length - 2));
            G.call("h2d.Text", "set_text", label, [shown + "..."]);
        }
        var w = Fonts.width(label), h = Fonts.height(label);
        var rx = w / 2 * 1.6 + 14 * sc, ry = h / 2 * 1.6 + 10 * sc, tail = 18 * sc;
        var cy = -(tail + ry * 0.9);
        var line = Math.max(2, 2.5 * sc);
        var bumps = Std.int(Math.max(8, Math.min(16, Math.round((rx + ry) / (16 * sc)))));
        // the shadow, the tail (a curved horn), then the cloud: its outline covers where they meet
        Shapes.polygon(shapes, Shapes.lobes(5 * sc, cy + 5 * sc, rx, ry, bumps), 0x000000, 0x000000, 1);
        Shapes.polygon(shapes, [-rx * 0.45, cy + ry * 0.6, 0, 0, -rx * 0.1, cy + ry * 0.7], 0xFFFFFF, 0x000000, line);
        Shapes.polygon(shapes, Shapes.lobes(0, cy, rx, ry, bumps), 0xFFFFFF, 0x000000, line);
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
