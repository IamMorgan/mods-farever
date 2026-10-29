package comixmod;

import comixmod.GameAccess as G;

/** The font of the effects: Heaps' bitmap default (the game's own fonts are distance fields that plain text cannot draw). */
class Fonts {
    static var known:Dynamic;


    public static function get():Dynamic {
        if (known != null) return known;
        try known = G.staticCall("hxd.res.DefaultFont", "get", []) catch (_:Dynamic) {}
        return known;
    }

    /** A text object on `parent` that is `color`, scaled by `size`; the text is wrapped at `maxWidth` when it is above 0. */
    public static function text(parent:Dynamic, value:String, color:Int, size:Float, maxWidth:Float = 0):Dynamic {
        var t = G.create("h2d.Text", [get(), parent]);
        if (maxWidth > 0) G.set(t, "maxWidth", maxWidth);
        G.call("h2d.Text", "set_text", t, [value]);
        G.call("h2d.Text", "set_textColor", t, [color]);
        G.call("h2d.Object", "setScale", t, [size]);
        return t;
    }

    public static function width(t:Dynamic):Float return G.number(G.call("h2d.Text", "get_textWidth", t)) * G.number(G.field(t, "scaleX"), 1);

    public static function height(t:Dynamic):Float return G.number(G.call("h2d.Text", "get_textHeight", t)) * G.number(G.field(t, "scaleY"), 1);
}
