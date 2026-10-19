package macromod;

import macromod.GameAccess as G;

/**
 * Plain h2d building blocks for the mod's own windows (skill picker, rotation window), drawn straight
 * onto the game's 2D scene: texts in the game's font, flat boxes, skill icons. Only simple h2d objects
 * are used, and backgrounds are h2d.Interactive.backgroundColor: no h2d.Graphics, whose drawing methods
 * take optional (by-reference) arguments.
 */
class UiKit {
    /** Height of one text line, in scene pixels. */
    public static inline var LINE = 18.0;

    var font:Dynamic;
    var fontScale = 1.0;

    public function new() {}

    /** Picks the font and the text scale; call before drawing texts on `scene`. */
    public function prepare(scene:Dynamic):Void {
        if (font == null) font = findFont(scene);
        var lineHeight = G.number(G.field(font, "lineHeight"), 16);
        fontScale = lineHeight > 0 ? Math.min(1.5, Math.max(0.5, LINE / lineHeight)) : 1;
    }

    /** A font from the game's own texts, preferring one that is showing non-Latin text (so it
        has the client language's letters); the engine's default font only as a last resort. */
    function findFont(root:Dynamic):Dynamic {
        var tree = new GameScene();
        var stack:Array<Dynamic> = [root];
        var visited = 0;
        var fallback:Dynamic = null;
        while (stack.length > 0 && visited++ < 30000) {
            var node = stack.pop();
            if (G.isA(node, "h2d.Text")) {
                var f = G.field(node, "font");
                if (f != null) {
                    var text = G.str(G.field(node, "text"));
                    if (text != null) for (i in 0...text.length) if (StringTools.fastCodeAt(text, i) >= 0x400) return f;
                    if (fallback == null) fallback = f;
                }
            }
            for (kid in tree.children(node)) stack.push(kid);
        }
        return fallback != null ? fallback : G.staticCall("hxd.res.DefaultFont", "get", []);
    }

    public function text(parent:Dynamic, value:String, color:Int, x:Float, y:Float, ?maxWidth:Float):Dynamic {
        var t = G.create("h2d.Text", [font, parent]);
        G.call("h2d.Text", "set_textColor", t, [color]);
        if (maxWidth != null) G.call("h2d.Text", "set_maxWidth", t, [maxWidth / fontScale]);
        G.call("h2d.Text", "set_text", t, [value]);
        G.call("h2d.Object", "setScale", t, [fontScale]);
        G.call("h2d.Object", "setPosition", t, [x, y]);
        return t;
    }

    /** The width a text object takes on screen. */
    public function textWidth(t:Dynamic, value:String):Float {
        try return G.number(G.call("h2d.Text", "get_textWidth", t), value.length * 9.0) * fontScale
        catch (_:Dynamic) return value.length * 9.0 * fontScale;
    }

    public function setText(t:Dynamic, value:String):Void {
        if (t != null) try G.call("h2d.Text", "set_text", t, [value]) catch (_:Dynamic) {}
    }

    public function box(parent:Dynamic, x:Float, y:Float, w:Float, h:Float, color:Int):Dynamic {
        var area = G.create("h2d.Interactive", [w, h, parent, null]);
        G.set(area, "backgroundColor", color);
        G.call("h2d.Object", "setPosition", area, [x, y]);
        return area;
    }

    public function handCursor(area:Dynamic):Void
        try G.call("h2d.Interactive", "set_cursor", area, [G.current("hxd.Cursor", "Button")]) catch (_:Dynamic) {}

    public function remove(object:Dynamic):Void
        if (object != null) try G.call("h2d.Object", "remove", object, []) catch (_:Dynamic) {}

    /** The skill's own icon, as the action bar draws it (lib.ExtensionsUI.toTile(skill.getIcon())),
        fitted into a square cell of `size` pixels. */
    public function drawIcon(skill:Dynamic, parent:Dynamic, size:Float):Bool {
        try {
            var gfx = G.call("st.skill.BaseSkill", "getIcon", skill);
            if (gfx == null) return false;
            var tile = G.staticCall("lib.ExtensionsUI", "toTile", [gfx]);
            if (tile == null) return false;
            var w = G.number(G.field(tile, "width")), h = G.number(G.field(tile, "height"));
            if (w <= 0 || h <= 0) return false;
            var bitmap = G.create("h2d.Bitmap", [tile, parent]);
            var scale = (size - 6) / Math.max(w, h);
            G.call("h2d.Object", "setScale", bitmap, [scale]);
            G.call("h2d.Object", "setPosition", bitmap, [(size - w * scale) / 2, (size - h * scale) / 2]);
            return true;
        } catch (_:Dynamic) {
            return false;
        }
    }
}
