package comixmod;

import comixmod.GameAccess as G;

private typedef Outlined = {counter:Dynamic, copies:Array<Dynamic>};

/** A white outline for the critical hit numbers: white copies of the text on the scene (never inside the game's flow panels), kept on the text's screen place. */
class Outlines {
    static inline var WIDTH = 2.0;
    static final SHIFTS = [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]];
    var list:Array<Outlined> = [];

    public function new() {}

    public function add(s2d:Dynamic, counter:Dynamic):Void {
        var copies = [];
        var font = G.field(counter, "font"), value = G.text(G.field(counter, "text"));
        for (_ in SHIFTS) {
            var t = G.create("h2d.Text", [font, s2d]);
            G.call("h2d.Object", "addChildAt", s2d, [t, 0]);
            G.call("h2d.Text", "set_text", t, [value]);
            G.call("h2d.Text", "set_textColor", t, [0xFFFFFF]);
            G.set(t, "visible", false);
            copies.push(t);
        }
        list.push({counter: counter, copies: copies});
    }

    function drop(o:Outlined):Void {
        for (t in o.copies) G.call("h2d.Object", "remove", t, []);
    }

    public function update():Void {
        var kept = [];
        for (o in list) {
            if (G.field(o.counter, "parent") == null) {
                drop(o);
                continue;
            }
            kept.push(o);
            var x = G.number(G.field(o.counter, "absX")), y = G.number(G.field(o.counter, "absY"));
            var s = G.number(G.field(o.counter, "matA"), 1);
            var shown = G.field(o.counter, "visible") != false && (x != 0 || y != 0);
            var i = 0;
            for (d in SHIFTS) {
                var t = o.copies[i++];
                G.set(t, "x", x + d[0] * WIDTH);
                G.set(t, "y", y + d[1] * WIDTH);
                G.set(t, "scaleX", s);
                G.set(t, "scaleY", s);
                G.set(t, "visible", shown);
            }
        }
        list = kept;
    }

    public function clear():Void {
        for (o in list) drop(o);
        list = [];
    }
}
