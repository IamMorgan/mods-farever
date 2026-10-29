package comixmod;

import comixmod.GameAccess as G;

/** The font of the effects: the game's own (taken from a damage number), else Heaps' default one. */
class Fonts {
    static var known:Dynamic;


    public static function remember(font:Dynamic):Void {
        if (font != null) known = font;
    }

    public static function get():Dynamic {
        if (known != null) return known;
        try known = G.staticCall("hxd.res.DefaultFont", "get", []) catch (_:Dynamic) {}
        return known;
    }

    static var ui:Array<Dynamic>;

    static function covers(font:Dynamic, value:String):Bool {
        try {
            for (i in 0...value.length) {
                var code = value.charCodeAt(i);
                if (code > 32 && G.call("h2d.Font", "hasChar", font, [code]) != true) return false;
            }
            return true;
        } catch (_:Dynamic) return false;
    }

    /** The fonts of the game's UI (found once): hasChar also looks into a font's subFonts, so one of them draws the client's language. */
    static function uiFonts(root:Dynamic):Array<Dynamic> {
        if (ui != null) return ui;
        ui = [];
        var stack = [root], visited = 0;
        while (stack.length > 0 && visited++ < 20000) {
            var node = stack.pop();
            var font = G.field(node, "font");
            if (font != null && ui.indexOf(font) < 0) ui.push(font);
            for (child in G.array(G.field(node, "children"))) stack.push(child);
        }
        return ui;
    }

    /** The font for `value`: the usual one, or the game's UI font that can draw all its characters (Cyrillic, CJK, ...). */
    public static function forText(root:Dynamic, value:String):Dynamic {
        var usual = get();
        if (covers(usual, value)) return usual;
        for (f in uiFonts(root)) if (covers(f, value)) return f;
        return usual;
    }

    /** A text object on `parent` that is `color`, scaled by `size`; the text is wrapped at `maxWidth` when it is above 0. */
    public static function text(parent:Dynamic, value:String, color:Int, size:Float, maxWidth:Float = 0, ?font:Dynamic):Dynamic {
        var t = G.create("h2d.Text", [font != null ? font : get(), parent]);
                if (maxWidth > 0) G.call("h2d.Text", "set_maxWidth", t, [maxWidth / size]);
        G.call("h2d.Text", "set_text", t, [value]);
        G.call("h2d.Text", "set_textColor", t, [color]);
        G.call("h2d.Object", "setScale", t, [size]);
        return t;
    }

    public static function width(t:Dynamic):Float return G.number(G.call("h2d.Text", "get_textWidth", t)) * G.number(G.field(t, "scaleX"), 1);

    public static function height(t:Dynamic):Float return G.number(G.call("h2d.Text", "get_textHeight", t)) * G.number(G.field(t, "scaleY"), 1);
}
