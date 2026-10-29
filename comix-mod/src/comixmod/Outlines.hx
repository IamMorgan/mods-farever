package comixmod;

import comixmod.GameAccess as G;

private typedef Outlined = {counter:Dynamic, copies:Array<Dynamic>};

/** A white outline for the critical hit numbers: white copies of the text under it, kept on the text's place. */
class Outlines {
    static inline var WIDTH = 2.0;
    var list:Array<Outlined> = [];

    public function new() {}

    /** The game's panels are flows that lay out their children: a child of ours must stay out of that layout, or the reflow never ends. */
    public static function pin(parent:Dynamic, child:Dynamic):Void {
        try G.set(G.call("h2d.Flow", "getProperties", parent, [child]), "isAbsolute", true) catch (_:Dynamic) {}
    }

    public function add(widget:Dynamic, counter:Dynamic):Void {
        var copies = [];
        var font = G.field(counter, "font"), value = G.text(G.field(counter, "text"));
        for (d in [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]]) {
            var t = G.create("h2d.Text", [font, widget]);
            G.call("h2d.Object", "addChildAt", widget, [t, 0]);
            pin(widget, t);
            G.call("h2d.Text", "set_text", t, [value]);
            G.call("h2d.Text", "set_textColor", t, [0xFFFFFF]);
            copies.push(t);
        }
        list.push({counter: counter, copies: copies});
        place();
    }

    function place():Void {
        for (o in list) {
            var x = G.number(G.field(o.counter, "x")), y = G.number(G.field(o.counter, "y"));
            var sx = G.number(G.field(o.counter, "scaleX"), 1), sy = G.number(G.field(o.counter, "scaleY"), 1);
            var i = 0;
            for (d in [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]]) {
                var t = o.copies[i++];
                G.set(t, "x", x + d[0] * WIDTH);
                G.set(t, "y", y + d[1] * WIDTH);
                G.set(t, "scaleX", sx);
                G.set(t, "scaleY", sy);
                G.set(t, "visible", G.field(o.counter, "visible") != false);
            }
        }
    }

    public function update():Void {
        // forget the numbers the game has already removed
        list = [for (o in list) if (G.field(o.counter, "parent") != null) o];
        place();
    }
}
