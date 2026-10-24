package dpf;

import dpf.GameAccess as G;

/**
 * Plain h2d building blocks for the mod's own windows, drawn on the game's 2D scene: texts in the game's font, filled shapes
 * (h2d.Graphics polygons), invisible click areas (h2d.Interactive), the dungeon's picture.
 */
class UiKit {
    /** Text height the sizes below are relative to: a text of size 18 is one line of the game's font. */
    public static inline var LINE = 18.0;

    var font:Dynamic;
    var fontScale = 1.0;

    public function new() {}

    /** Picks the font; call before drawing texts on `scene`. */
    public function prepare(scene:Dynamic):Void {
        if (font == null) font = findFont(scene);
        var lineHeight = G.number(G.field(font, "lineHeight"), 16);
        fontScale = lineHeight > 0 ? Math.min(1.5, Math.max(0.5, LINE / lineHeight)) : 1;
    }

    /** A font from the game's own texts, preferring one that shows non-Latin text (so it has the client language's letters). */
    function findFont(root:Dynamic):Dynamic {
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
            var count = G.integer(G.call("h2d.Object", "get_numChildren", node));
            for (i in 0...count) stack.push(G.call("h2d.Object", "getChildAt", node, [i]));
        }
        return fallback != null ? fallback : G.staticCall("hxd.res.DefaultFont", "get", []);
    }

    function scaleOf(size:Float):Float return fontScale * size / LINE;

    /** A text of `size` (18 = one line) at (x, y); wraps at `maxWidth` when given. */
    public function text(parent:Dynamic, value:String, color:Int, x:Float, y:Float, size = LINE, ?maxWidth:Float):Dynamic {
        var t = G.create("h2d.Text", [font, parent]);
        G.call("h2d.Text", "set_textColor", t, [color]);
        if (maxWidth != null) G.call("h2d.Text", "set_maxWidth", t, [maxWidth / scaleOf(size)]);
        G.call("h2d.Text", "set_text", t, [value]);
        G.call("h2d.Object", "setScale", t, [scaleOf(size)]);
        G.call("h2d.Object", "setPosition", t, [x, y]);
        return t;
    }

    /** A text centred on `cx` (one line). */
    public function centered(parent:Dynamic, value:String, color:Int, cx:Float, y:Float, size = LINE, ?maxWidth:Float):Dynamic {
        var t = text(parent, value, color, 0, y, size, maxWidth);
        var w = textWidth(t, size);
        G.call("h2d.Object", "setPosition", t, [Math.round(cx - w / 2), y]);
        return t;
    }

    /** A text that ends at `right`. */
    public function right(parent:Dynamic, value:String, color:Int, rightX:Float, y:Float, size = LINE):Dynamic {
        var t = text(parent, value, color, 0, y, size);
        G.call("h2d.Object", "setPosition", t, [Math.round(rightX - textWidth(t, size)), y]);
        return t;
    }

    /** The width a text takes on screen. */
    public function textWidth(t:Dynamic, size = LINE):Float {
        try return G.number(G.call("h2d.Text", "get_textWidth", t), 0) * scaleOf(size)
        catch (_:Dynamic) return 0;
    }

    public function textHeight(t:Dynamic, size = LINE):Float {
        try return G.number(G.call("h2d.Text", "get_textHeight", t), size) * scaleOf(size)
        catch (_:Dynamic) return size;
    }

    /** `value` broken into lines no wider than `maxWidth` at `size` (measured with a throw-away text on `parent`). */
    public function wrap(parent:Dynamic, value:String, size:Float, maxWidth:Float):Array<String> {
        var probe = text(parent, "", 0, -10000, -10000, size);
        var lines:Array<String> = [];
        for (paragraph in value.split("\n")) {
            var current = "";
            for (word in paragraph.split(" ")) {
                var candidate = current == "" ? word : current + " " + word;
                setText(probe, candidate);
                if (current == "" || textWidth(probe, size) <= maxWidth) current = candidate;
                else { lines.push(current); current = word; }
            }
            lines.push(current);
        }
        remove(probe);
        return lines;
    }

    public function setText(t:Dynamic, value:String):Void {
        if (t != null) try G.call("h2d.Text", "set_text", t, [value]) catch (_:Dynamic) {}
    }

    public function setColor(t:Dynamic, color:Int):Void {
        if (t != null) try G.call("h2d.Text", "set_textColor", t, [color]) catch (_:Dynamic) {}
    }

    /** An empty object: a group of things that move, hide or scale together. */
    public function group(parent:Dynamic, x:Float, y:Float):Dynamic {
        var o = G.create("h2d.Object", [parent]);
        G.call("h2d.Object", "setPosition", o, [x, y]);
        return o;
    }

    /** An invisible click area. */
    public function area(parent:Dynamic, x:Float, y:Float, w:Float, h:Float):Dynamic {
        var a = G.create("h2d.Interactive", [w, h, parent, null]);
        G.call("h2d.Object", "setPosition", a, [x, y]);
        return a;
    }

    public function handCursor(a:Dynamic):Void
        try G.call("h2d.Interactive", "set_cursor", a, [G.current("hxd.Cursor", "Button")]) catch (_:Dynamic) {}

    public function visible(object:Dynamic, on:Bool):Void
        if (object != null) try G.call("h2d.Object", "set_visible", object, [on]) catch (_:Dynamic) {}

    public function remove(object:Dynamic):Void
        if (object != null) try G.call("h2d.Object", "remove", object, []) catch (_:Dynamic) {}

    // ---- shapes (one h2d.Graphics collects as many as you like) ----

    public function shapes(parent:Dynamic):Dynamic return G.create("h2d.Graphics", [parent]);

    /** A filled polygon: points as x0, y0, x1, y1, ... */
    public function poly(g:Dynamic, points:Array<Float>, color:Int, alpha = 1.0):Void {
        G.call("h2d.Graphics", "beginFill", g, [color, alpha]);
        G.call("h2d.Graphics", "moveTo", g, [points[0], points[1]]);
        var i = 2;
        while (i < points.length) {
            G.call("h2d.Graphics", "lineTo", g, [points[i], points[i + 1]]);
            i += 2;
        }
        G.call("h2d.Graphics", "lineTo", g, [points[0], points[1]]);
        G.call("h2d.Graphics", "endFill", g);
    }

    public function rect(g:Dynamic, x:Float, y:Float, w:Float, h:Float, color:Int, alpha = 1.0):Void
        poly(g, [x, y, x + w, y, x + w, y + h, x, y + h], color, alpha);

    /** A rectangle with its corners cut in steps of `r` (a rounded look at a few pixels' cost). */
    public function plate(g:Dynamic, x:Float, y:Float, w:Float, h:Float, r:Float, color:Int, alpha = 1.0):Void {
        var c = r * 0.3;
        poly(g, [x + r, y, x + w - r, y, x + w - c, y + c, x + w, y + r, x + w, y + h - r, x + w - c, y + h - c, x + w - r, y + h,
            x + r, y + h, x + c, y + h - c, x, y + h - r, x, y + r, x + c, y + c], color, alpha);
    }

    public function circle(g:Dynamic, cx:Float, cy:Float, r:Float, color:Int, alpha = 1.0, segments = 14):Void {
        var points:Array<Float> = [];
        for (i in 0...segments) {
            var a = Math.PI * 2 * i / segments;
            points.push(cx + Math.cos(a) * r);
            points.push(cy + Math.sin(a) * r);
        }
        poly(g, points, color, alpha);
    }

    /** A plate with a darker outline of `line` pixels. */
    public function framed(g:Dynamic, x:Float, y:Float, w:Float, h:Float, r:Float, fill:Int, outline:Int, line = 2.0, alpha = 1.0):Void {
        plate(g, x, y, w, h, r, outline, alpha);
        plate(g, x + line, y + line, w - line * 2, h - line * 2, Math.max(0, r - line * 0.5), fill, alpha);
    }

    // ---- pictures ----

    /** A tile as a bitmap fitted into (w, h) keeping its shape, centred in it; false when it cannot be drawn. */
    public function fitTile(parent:Dynamic, tile:Dynamic, x:Float, y:Float, w:Float, h:Float, fill = false):Bool {
        if (tile == null) return false;
        try {
            var tw = G.number(G.field(tile, "width")), th = G.number(G.field(tile, "height"));
            if (tw <= 0 || th <= 0) return false;
            var holder = fill ? G.create("h2d.Mask", [Std.int(w), Std.int(h), parent]) : G.create("h2d.Object", [parent]);
            G.call("h2d.Object", "setPosition", holder, [x, y]);
            var bitmap = G.create("h2d.Bitmap", [tile, holder]);
            var scale = fill ? Math.max(w / tw, h / th) : Math.min(w / tw, h / th);
            G.call("h2d.Object", "setScale", bitmap, [scale]);
            G.call("h2d.Object", "setPosition", bitmap, [(w - tw * scale) / 2, (h - th * scale) / 2]);
            return true;
        } catch (_:Dynamic) {
            return false;
        }
    }
}
