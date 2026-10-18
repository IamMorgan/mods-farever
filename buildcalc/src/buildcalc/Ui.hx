package buildcalc;

/** Small helpers that build h2d objects of the game through HlxRuntime. */
class Ui {
    /** Fonts that can draw Cyrillic, found in the game's UI (h2d.Font.hasChar also looks into subFonts). */
    static var cyrillic:Array<Dynamic> = null;
    static var bodyFont:Dynamic;
    static var boldFont:Dynamic;
    static var fallback:Dynamic;

    /** Can the font draw the characters of the client's language (Texts.sampleChars)? */
    static function hasCyrillic(f:Dynamic):Bool {
        try {
            for (c in Texts.sampleChars()) if (G.call("h2d.Font", "hasChar", [f, c]) != true) return false;
            return true;
        } catch (_:Dynamic) return false;
    }

    /** The language changed: the fonts are found again. */
    public static function resetFonts():Void {
        cyrillic = null;
        bodyFont = null;
        boldFont = null;
        fallback = null;
    }

    static function fontName(f:Dynamic):String return G.str(G.field(f, "name"));

    static function collect(root:Dynamic, seen:Array<Dynamic>, limit:Int):Void {
        var stack = [root];
        var visited = 0;
        while (stack.length > 0 && visited < limit) {
            var node = stack.pop();
            visited++;
            if (node == null) continue;
            var f = G.field(node, "font");
            if (f != null && seen.indexOf(f) < 0) {
                seen.push(f);
                var cyr = hasCyrillic(f);
                DebugLog.line("  font: " + fontName(f) + " size=" + G.str(G.field(f, "size")) + " type=" + G.str(G.field(f, "type"))
                    + " language=" + cyr + " subFonts=" + G.len(G.field(f, "subFonts")) + " node=" + G.typeName(node)
                    + " text=\"" + G.str(G.field(node, "text")).substr(0, 30) + "\"");
                if (fallback == null) fallback = f;
                if (cyr) cyrillic.push(f);
            }
            for (child in G.children(node)) stack.push(child);
        }
        DebugLog.line("  scanned " + visited + " UI nodes");
    }

    /** Score of a font for body (bold = false) or heading (bold = true) text: plain upright faces first. */
    static function score(f:Dynamic, bold:Bool):Float {
        var n = fontName(f).toLowerCase();
        var s = 0.0;
        if (n.indexOf("italic") >= 0) s -= 100;
        if (n.indexOf("black") >= 0) s -= 40;
        if (bold) {
            if (n.indexOf("bold") >= 0 || n.indexOf("semibold") >= 0) s += 30;
        } else {
            if (n.indexOf("regular") >= 0 || n.indexOf("medium") >= 0) s += 30;
            if (n.indexOf("bold") >= 0) s -= 10;
        }
        s += Math.min(G.num(G.field(f, "size")), 40) / 10; // bigger source fonts scale down cleaner
        return s;
    }

    static function scan(window:Dynamic):Void {
        if (cyrillic != null && cyrillic.length > 0) return;
        cyrillic = [];
        var seen = new Array<Dynamic>();
        DebugLog.line("fonts: scanning the window");
        collect(window, seen, 6000);
        try {
            var root = G.field(HlxRuntime.resolveStaticField(G.type("ui.BaseUI"), "current"), "root");
            DebugLog.line("fonts: scanning the whole UI (" + G.typeName(root) + ")");
            collect(root, seen, 30000);
        } catch (e:Dynamic) DebugLog.error("fonts: whole UI scan", e);
        for (f in cyrillic) {
            if (bodyFont == null || score(f, false) > score(bodyFont, false)) bodyFont = f;
            if (boldFont == null || score(f, true) > score(boldFont, true)) boldFont = f;
        }
        DebugLog.line("fonts: " + cyrillic.length + " draw the client's language; body=" + (bodyFont == null ? "none" : fontName(bodyFont))
            + " heading=" + (boldFont == null ? "none" : fontName(boldFont)) + " fallback=" + (fallback == null ? "none" : fontName(fallback)));
    }

    /** Body text: the heading face (bold) reads better at small sizes on the light background. */
    public static function body(window:Dynamic):Dynamic {
        scan(window);
        return boldFont != null ? boldFont : (bodyFont != null ? bodyFont : fallback);
    }

    public static function heading(window:Dynamic):Dynamic {
        scan(window);
        return boldFont != null ? boldFont : body(window);
    }

    static function align(name:String):Dynamic return HlxRuntime.constructEnum(G.type("h2d.FlowAlign"), name, []);

    /** A flow box; width > 0 fixes its width (min = max), so columns keep their size. */
    public static function flow(parent:Dynamic, vertical:Bool, spacing:Int, width:Int = 0):Dynamic {
        var f = HlxRuntime.constructInstanceByName(G.type("h2d.Flow"), 1, [parent]);
        G.call("h2d.Flow", "set_layout", [f, HlxRuntime.constructEnum(G.type("h2d.FlowLayout"), vertical ? "Vertical" : "Horizontal", [])]);
        G.call("h2d.Flow", vertical ? "set_verticalSpacing" : "set_horizontalSpacing", [f, spacing]);
        G.call("h2d.Flow", "set_verticalAlign", [f, align("Top")]);
        if (width > 0) {
            G.call("h2d.Flow", "set_minWidth", [f, width]);
            G.call("h2d.Flow", "set_maxWidth", [f, width]);
        }
        return f;
    }

    /** A text `px` pixels high in font `f` (scaled from the font's own size), wrapped at `maxWidth` if > 0. */
    public static function text(parent:Dynamic, f:Dynamic, value:String, color:Int, px:Float, maxWidth:Int = 0):Dynamic {
        var t = HlxRuntime.constructInstanceByName(G.type("h2d.Text"), 2, [f, parent]);
        G.call("h2d.Text", "set_text", [t, value]);
        try G.call("h2d.Text", "set_textColor", [t, color]) catch (_:Dynamic) {}
        var size = G.num(G.field(f, "size"));
        var scale = size > 0 ? px / size : 1.0;
        if (scale != 1.0) G.call("h2d.Object", "setScale", [t, scale]);
        if (maxWidth > 0) try G.call("h2d.Text", "set_maxWidth", [t, maxWidth / scale]) catch (_:Dynamic) {}
        try G.call("h2d.Text", "set_lineSpacing", [t, 3.0 / scale]) catch (_:Dynamic) {} // a little air between wrapped lines
        return t;
    }

    /** Width in pixels of the widest of these lines at `px` pixels high (h2d.Font.calcTextWidth). */
    public static function textWidth(f:Dynamic, lines:Array<String>, px:Float):Float {
        var size = G.num(G.field(f, "size"));
        var scale = size > 0 ? px / size : 1.0;
        var w = 0.0;
        for (l in lines) try w = Math.max(w, G.num(G.call("h2d.Font", "calcTextWidth", [f, l, null])) * scale) catch (_:Dynamic) w = Math.max(w, l.length * px * 0.55);
        return w;
    }

    /**
     * A small label inside a cell (on its lower edge, over the icon): a dark plate with light text, placed
     * absolutely so the cell keeps its size.
     */
    public static function badge(cell:Dynamic, f:Dynamic, label:String, cellSize:Int):Void {
        var px = 10.0;
        var plateH = 13;
        var plate = HlxRuntime.constructInstanceByName(G.type("h2d.Bitmap"), 2, [G.callStatic("h2d.Tile", "fromColor", [0x2E2A24, cellSize, plateH, 0.78]), cell]);
        HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [cell, plate]), "isAbsolute", true);
        G.call("h2d.Object", "setPosition", [plate, 0, cellSize - plateH]);
        var t = text(cell, f, label, 0xF2E8C9, px);
        HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [cell, t]), "isAbsolute", true);
        // the real width of the text as drawn; smaller when it does not fit the cell
        var scale = G.num(G.field(t, "scaleX"));
        if (scale <= 0) scale = 1;
        var w = G.num(G.call("h2d.Text", "get_textWidth", [t])) * scale;
        if (w > cellSize - 4 && w > 0) {
            var k = (cellSize - 4) / w;
            G.call("h2d.Object", "setScale", [t, scale * k]);
            w *= k;
        }
        G.call("h2d.Object", "setPosition", [t, Math.max(2, (cellSize - w) / 2), cellSize - plateH + 0.5]);
    }

    /** Button colors (ARGB). */
    public static inline var BTN = 0xFFD9C3B3;
    public static inline var BTN_HOVER = 0xFFE8D6C8;
    public static inline var BTN_ON = 0xFF8A5A3C;
    public static inline var BTN_ON_HOVER = 0xFF9C6A4A;
    public static inline var BTN_TEXT = 0x4A3A30;
    public static inline var BTN_TEXT_ON = 0xFFF3E6;

    /**
     * A clickable button: a coloured h2d.Interactive with the label on it. `selected` draws it pressed
     * (used for option groups). `minWidth` > 0 makes buttons of a group the same width.
     */
    public static function button(parent:Dynamic, f:Dynamic, label:String, px:Float, selected:Bool, onClick:Void->Void, minWidth:Int = 0):Dynamic {
        var padX = 10.0, padY = 5.0;
        var area = HlxRuntime.constructInstanceByName(G.type("h2d.Interactive"), 4, [10.0, 10.0, parent, null]);
        var t = text(area, f, label, selected ? BTN_TEXT_ON : BTN_TEXT, px);
        var scale = G.num(G.field(t, "scaleX"));
        if (scale <= 0) scale = 1;
        var w = G.num(G.call("h2d.Text", "get_textWidth", [t])) * scale + padX * 2;
        var h = G.num(G.call("h2d.Text", "get_textHeight", [t])) * scale + padY * 2;
        if (w < minWidth) w = minWidth;
        HlxRuntime.setField(area, "width", w);
        HlxRuntime.setField(area, "height", h);
        G.call("h2d.Object", "setPosition", [t, (w - G.num(G.call("h2d.Text", "get_textWidth", [t])) * scale) / 2, padY]);
        var normal = selected ? BTN_ON : BTN, hover = selected ? BTN_ON_HOVER : BTN_HOVER;
        HlxRuntime.setField(area, "backgroundColor", normal);
        HlxRuntime.setField(area, "onOver", (_:Dynamic) -> HlxRuntime.setField(area, "backgroundColor", hover));
        HlxRuntime.setField(area, "onOut", (_:Dynamic) -> HlxRuntime.setField(area, "backgroundColor", normal));
        HlxRuntime.setField(area, "onClick", (_:Dynamic) -> DebugLog.guard("click " + label, onClick));
        try G.call("h2d.Interactive", "set_cursor", [area, HlxRuntime.constructEnum(G.type("hxd.Cursor"), "Button", [])]) catch (_:Dynamic) {}
        return area;
    }

    public static inline var BTN_OFF = 0xFFE6DBD2;
    public static inline var BTN_TEXT_OFF = 0xB5A89D;

    /** A greyed-out button that cannot be clicked. */
    public static function disabledButton(parent:Dynamic, f:Dynamic, label:String, px:Float, minWidth:Int = 0):Dynamic {
        var box = flow(parent, false, 0, minWidth);
        G.call("h2d.Flow", "set_horizontalAlign", [box, HlxRuntime.constructEnum(G.type("h2d.FlowAlign"), "Middle", [])]);
        G.call("h2d.Flow", "set_padding", [box, 5]);
        G.call("h2d.Flow", "set_backgroundTile", [box, G.callStatic("h2d.Tile", "fromColor", [BTN_OFF & 0xFFFFFF, 1, 1, 1.0])]);
        text(box, f, label, BTN_TEXT_OFF, px);
        return box;
    }

    public static inline var BTN_LOCKED = 0xFFB8A08E;

    /** A chosen option that cannot be changed now (while the calculation runs): pressed look, dimmed, no click. */
    public static function lockedButton(parent:Dynamic, f:Dynamic, label:String, px:Float, minWidth:Int = 0):Dynamic {
        var box = flow(parent, false, 0, minWidth);
        G.call("h2d.Flow", "set_horizontalAlign", [box, HlxRuntime.constructEnum(G.type("h2d.FlowAlign"), "Middle", [])]);
        G.call("h2d.Flow", "set_padding", [box, 5]);
        G.call("h2d.Flow", "set_backgroundTile", [box, G.callStatic("h2d.Tile", "fromColor", [BTN_LOCKED & 0xFFFFFF, 1, 1, 1.0])]);
        text(box, f, label, BTN_TEXT_ON, px);
        return box;
    }

    public static function describe(o:Dynamic):String {
        var parts = [G.typeName(o)];
        for (n in ["x", "y", "calculatedWidth", "calculatedHeight", "innerWidth", "innerHeight", "minWidth", "maxWidth"]) {
            var v = G.field(o, n);
            if (v != null) parts.push(n + "=" + Std.string(v));
        }
        return parts.join(" ");
    }
}
