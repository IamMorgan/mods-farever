package comixmod;

import comixmod.GameAccess as G;

private typedef Outlined = {counter:Dynamic, widget:Dynamic, frames:Int, copies:Array<Dynamic>};

/** A white outline for the critical hit numbers: white copies of the text on the scene (never inside the game's flow panels), kept on the text's screen place. */
class Outlines {
    static inline var WIDTH = 2.0;
    static final SHIFTS = [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]];
    var list:Array<Outlined> = [];

    public function new() {}

    public function add(s2d:Dynamic, counter:Dynamic, widget:Dynamic):Void {
        var copies = [];
        var font = G.field(counter, "font"), value = G.text(G.field(counter, "text"));
        for (_ in SHIFTS) {
            var t = G.create("h2d.Text", [font, s2d]);
            G.call("h2d.Text", "set_text", t, [value]);
            G.call("h2d.Text", "set_textColor", t, [0xFFFFFF]);
            G.set(t, "visible", false);
            copies.push(t);
        }
        list.push({counter: counter, widget: widget, frames: 0, copies: copies});
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
            if (o.frames++ < 4) trace("[comix-mod] outline abs=" + x + "," + y + " local=" + G.field(o.counter, "x") + "," + G.field(o.counter, "y")
                + " widget abs=" + G.field(o.widget, "absX") + "," + G.field(o.widget, "absY") + " widget local=" + G.field(o.widget, "x") + "," + G.field(o.widget, "y")
                + " vis=" + G.field(o.counter, "visible") + " alpha=" + G.field(o.counter, "alpha") + " text=" + G.field(o.counter, "text") + " parent=" + Type.getClassName(Type.getClass(G.field(o.widget, "parent"))));
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
