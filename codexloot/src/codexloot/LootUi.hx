package codexloot;

/** Draws on the Codex window: the missing loot buttons, the drop chances and the monster tags. */
class LootUi {
    public static function percent(p:Float):String {
        var v = p * 100;
        if (v >= 10) return Std.string(Math.round(v)) + "%";
        if (v >= 1) return Std.string(Math.round(v * 10) / 10) + "%";
        if (v >= 0.1) return Std.string(Math.round(v * 100) / 100) + "%";
        if (v >= 0.001) return Std.string(Math.round(v * 1000) / 1000) + "%";
        return "<0.001%";
    }

    static var maxLevelCache:Int = -1;

    /** The hero's maximum level (the game's Const.Hero.MaxLevel), or 0 when it cannot be read. */
    static function maxLevel():Int {
        if (maxLevelCache >= 0) return maxLevelCache;
        maxLevelCache = 0;
        try {
            var hero = HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Const"), "Hero");
            maxLevelCache = Std.int(G.num(G.field(hero, "MaxLevel")));
        } catch (_:Dynamic) {}
        return maxLevelCache;
    }

    /**
     * The item as the game makes it when it drops at `level` from a source that guarantees at least rarity `minRarity`
     * (st.Item.create: weapons take the drop's rarity, other items keep the rarity of their data), or null when `level` is 0.
     */
    public static function realItem(item:Dynamic, level:Int, minRarity:String = ""):Dynamic {
        if (level <= 0) return null;
        try {
            var id = G.str(G.field(item, "id"));
            var drop = {count: 1, flags: null, item: id, itemFlags: null, lootLevel: level, lootTableFlags: null, maxRarity: null, minRarity: minRarity == "" ? null : minRarity, rarity: minRarity == "" ? null : minRarity};
            return G.callStatic("st.Item", "create", [id, drop]);
        } catch (_:Dynamic) {}
        return null;
    }

    /** The rarity of a made item (a weapon has its own, the others the one of their data), "" when unknown. */
    public static function rarityOf(real:Dynamic, item:Dynamic):String {
        var r = G.str(G.field(real, "rarity"));
        if (r == "") r = G.str(G.field(G.field(real, "inf"), "rarity"));
        return r != "" ? r : G.str(G.field(item, "rarity"));
    }

    /** The tooltip of an item. With `level` > 0 the item is created at that level (and with at least rarity `minRarity`, when set), as a drop of that level would be. */
    public static function tooltip(item:Dynamic, level:Int, minRarity:String = ""):Dynamic {
        return G.callStatic("ui.Tooltip", "fromItem", [item, realItem(item, level, minRarity)]);
    }

    /** A Codex button for an item, built the way the game builds them (CodexData.createItemNode), without registering anything. `level` > 0: the tooltip shows the item at that level. */
    public static function makeButton(item:Dynamic, parent:Dynamic, level:Int, minRarity:String = "", clickable:Bool = false, small:Bool = true):Dynamic {
        var node = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("data.CodexNode"), 0, []);
        HlxRuntime.setField(node, "name", G.str(G.field(item, "id")));
        HlxRuntime.setField(node, "data", item);
        HlxRuntime.setField(node, "_icon", G.field(item, "gfx"));
        HlxRuntime.setField(node, "clickable", clickable);
        HlxRuntime.setField(node, "forcedRevealed", true);
        try HlxRuntime.setField(node, "progressThresholds", G.callStatic("st.player.Progress", "getItemProgressThreshold", [item])) catch (_:Dynamic) {}
        var real = realItem(item, level, minRarity);
        var tip = function():Dynamic return G.callStatic("ui.Tooltip", "fromItem", [item, real]);
        HlxRuntime.setField(node, "getTooltip", tip);

        var button = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("ui.win.codex.CodexButton"), 2, [node, parent]);
        var dom = G.field(button, "dom");
        // the frame colour follows the rarity of the data record; a drop of a chest can be better (weapons of the Hero Weapon Cache are Epic)
        var rarity = real == null ? "" : rarityOf(real, item);
        if (rarity != "" && rarity != G.str(G.field(item, "rarity")))
            try G.call("domkit.Properties", "setClassKind", [dom, "rarity", rarity.toLowerCase()]) catch (_:Dynamic) {}
        if (small) try G.call(G.typeName(dom), "addClass", [dom, "small"]) catch (_:Dynamic) {
            try G.call(G.typeName(dom), "addClass", [dom, "small", null]) catch (_:Dynamic) {}
        }
        return button;
    }

    public static var font:Dynamic;
    static var searched:Dynamic;
    static var fontSize:Float = 0;

    /** True when the font can draw `code` (h2d.Font.hasChar also looks into the sub fonts the game adds for other alphabets). */
    static function hasGlyph(f:Dynamic, code:Int):Bool {
        try return G.call("h2d.Font", "hasChar", [f, code]) == true catch (_:Dynamic) return false;
    }

    /** True when our font can draw every letter of `text` (else the caller falls back to English). */
    public static function canDraw(text:String):Bool {
        if (font == null) return false;
        for (i in 0...text.length) {
            var c = text.charCodeAt(i);
            if (c != null && c > 0x7F && !hasGlyph(font, c)) return false;
        }
        return true;
    }

    /** A font used by a text of the window that can also draw Cyrillic; else any font found there. */
    static function findFont(root:Dynamic):Dynamic {
        var any:Dynamic = null;
        var stack = [root];
        var seen = 0;
        while (stack.length > 0 && seen < 3000) {
            var node = stack.pop();
            seen++;
            if (node == null) continue;
            if (G.typeName(node).indexOf("Text") >= 0) {
                var f = G.field(node, "font");
                if (f != null) {
                    if (hasGlyph(f, 0x0411) && hasGlyph(f, 0x25)) return f; // "Б" and "%"
                    if (any == null) any = f;
                }
            }
            for (child in G.children(node)) stack.push(child);
        }
        return any;
    }

    static var lastSearch = 0.0;

    /**
     * A font for our texts: a font the Codex window already uses (one with Cyrillic if possible), the engine's default font otherwise.
     * The texts of a window get their fonts a frame after the window is built, so while the font in use cannot draw Cyrillic the
     * window is searched again (at most every 0.4 s) instead of keeping the default font for good.
     */
    public static function prepare(sheet:Dynamic, button:Dynamic):Bool {
        if (font != null && hasGlyph(font, 0x0411)) return true;
        var now = haxe.Timer.stamp();
        if (font != null && now - lastSearch < 0.4) return true;
        lastSearch = now;
        searched = sheet;
        var f:Dynamic = null;
        try f = findFont(sheet) catch (_:Dynamic) {}
        if (f == null) try f = findFont(G.field(sheet, "parent")) catch (_:Dynamic) {}
        if (f != null && (font == null || hasGlyph(f, 0x0411))) {
            font = f;
            fontSize = G.num(G.field(f, "size"));
            return true;
        }
        if (font != null) return true;
        try {
            var d = G.callStatic("hxd.res.DefaultFont", "get", []);
            if (d != null) { font = d; fontSize = 0; return true; }
        } catch (_:Dynamic) {}
        return false;
    }

    /** Scale that gives the font a height of about `px` pixels. */
    public static function scaleFor(px:Float):Float {
        var s = fontSize > 0 ? px / fontSize : 2.0;
        return Math.max(0.5, Math.min(4.0, s));
    }

    public static function newText(parent:Dynamic, text:String, color:Int, scale:Float):Dynamic {
        var t = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Text"), 2, [font, parent]);
        G.call("h2d.Text", "set_text", [t, text]);
        try G.call("h2d.Text", "set_textColor", [t, color]) catch (_:Dynamic) {}
        if (scale != 1.0) G.call("h2d.Object", "setScale", [t, scale]);
        return t;
    }

    /** Text with a black outline (shifted black copies under the coloured text). */
    public static function outlined(parent:Dynamic, text:String, color:Int, px:Float):Dynamic {
        var box = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Object"), 1, [parent]);
        var s = scaleFor(px);
        for (o in [[-1.0, 0.0], [1.0, 0.0], [0.0, -1.0], [0.0, 1.0], [-1.0, -1.0], [1.0, 1.0]]) {
            var shadow = newText(box, text, 0x000000, s);
            G.call("h2d.Object", "setPosition", [shadow, o[0], o[1]]);
        }
        newText(box, text, color, s);
        return box;
    }

    static function align(name:String):Dynamic {
        return HlxRuntime.constructEnum(HlxRuntime.resolveType("h2d.FlowAlign"), name, []);
    }

    /** Large coloured text on a dark plate, on the lower edge of a Codex button. `px` = text height in pixels. */
    public static function tag(button:Dynamic, text:String, color:Int, px:Float):Void {
        var flow = G.field(button, "mainFrame");
        if (flow == null || font == null) return;
        var box = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Object"), 1, [flow]);
        var s = scaleFor(px);
        var t = newText(box, text, color, s);
        var w = G.num(G.call("h2d.Text", "get_textWidth", [t])) * s;
        var h = G.num(G.call("h2d.Text", "get_textHeight", [t])) * s;
        var plate = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Graphics"), 1, [null]);
        G.call("h2d.Graphics", "beginFill", [plate, 0x000000, 0.75]);
        G.call("h2d.Graphics", "drawRect", [plate, -4.0, -1.0, w + 8.0, h + 2.0]);
        G.call("h2d.Graphics", "endFill", [plate]);
        G.call("h2d.Object", "addChildAt", [box, plate, 0]);
        var props = G.call("h2d.Flow", "getProperties", [flow, box]);
        HlxRuntime.setField(props, "isAbsolute", true);
        HlxRuntime.setField(props, "horizontalAlign", align("Middle"));
        HlxRuntime.setField(props, "verticalAlign", align("Bottom"));
        HlxRuntime.setField(props, "offsetY", -3);
    }

    /** A block of items under its own caption; `fallback` is the English caption for a font without Cyrillic. Returns the new count of added icons. */
    public static function block(sheet:Dynamic, icons:Dynamic, anyButton:Dynamic, title:String, fallback:String, color:Int,
            entries:Array<LootCalc.LootEntry>, level:Int, added:Int, maxItems:Int, minRarity:String = "", dimmed:LootCalc.LootEntry->Bool = null):Int {
        if (entries.length == 0) return added;
        try {
            var ready = prepare(sheet, anyButton);
            if (ready) {
                var caption = outlined(icons, canDraw(title) ? title : fallback, color, 18.0);
                HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [icons, caption]), "lineBreak", true);
            }
            var first = true;
            for (entry in entries) {
                if (added >= maxItems) break;
                var button:Dynamic = null;
                try button = makeButton(entry.item, icons, level, minRarity) catch (_:Dynamic) {}
                if (button == null) continue;
                if (first) {
                    first = false;
                    try HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [icons, button]), "lineBreak", true) catch (_:Dynamic) {}
                }
                added++;
                if (dimmed != null && dimmed(entry)) try HlxRuntime.setField(button, "alpha", 0.5) catch (_:Dynamic) {}
                try { if (ready) tag(button, entry.chance < 0 ? "?" : percent(entry.chance), color, 12.0); } catch (_:Dynamic) {}
            }
        } catch (_:Dynamic) {}
        return added;
    }

    static inline var SCROLL_BAR = 16;
    /** Icon grids already moved off the scroll bar, with the padding the mod set. */
    static var padded:Array<{grid:Dynamic, value:Int}> = [];

    /** The Codex panel's scroll bar is drawn over the right edge of the icon grid: keep the icons left of it. */
    public static function keepClearOfScrollBar(icons:Dynamic):Void {
        try {
            var current = Std.int(G.num(G.field(icons, "paddingRight")));
            for (p in padded) if (p.grid == icons) {
                if (current == p.value) return; // still ours
                padded.remove(p); // the game restyled the grid: pad it again
                break;
            }
            if (padded.length > 20) padded.shift();
            padded.push({grid: icons, value: current + SCROLL_BAR});
            G.call("h2d.Flow", "set_paddingRight", [icons, current + SCROLL_BAR]);
        } catch (_:Dynamic) {}
    }

    public static function apply(sheet:Dynamic, normal:Array<LootCalc.LootEntry>, heroic:Array<LootCalc.LootEntry>, world:Array<LootCalc.LootEntry>, maxItems:Int):Void {
        var icons = G.field(sheet, "dropsIcons");
        if (icons == null) return;

        // buttons the game already built (items the Codex knows about), by item id
        var buttons = new Map<String, Dynamic>();
        var anyButton:Dynamic = null;
        for (child in G.children(icons)) {
            if (G.typeName(child) != "ui.win.codex.CodexButton") continue;
            anyButton = child;
            var id = G.str(G.field(G.field(G.field(child, "data"), "data"), "id"));
            if (id != "") buttons.set(id, child);
        }

        var added = 0;
        keepClearOfScrollBar(icons);

        // ---- normal loot: reuse the game's buttons, add the missing ones
        for (entry in normal) {
            var id = G.str(G.field(entry.item, "id"));
            var button = buttons.get(id);
            if (button == null) {
                if (added >= maxItems) continue;
                try button = makeButton(entry.item, icons, 0) catch (_:Dynamic) button = null;
                if (button == null) continue;
                buttons.set(id, button);
                added++;
            }
            try { if (prepare(sheet, button)) tag(button, percent(entry.chance), 0xFFFFFF, 12.0); } catch (_:Dynamic) {}
        }

        // ---- heroic mode loot and world loot (equipment): their own blocks under a caption
        added = block(sheet, icons, anyButton, SettingsText.heroicCaption(), "Heroic mode", 0xFFB347, heroic, maxLevel(), added, maxItems);
        added = block(sheet, icons, anyButton, SettingsText.worldCaption(), "Equipment (world loot)", 0x9FD7FF, world, 0, added, maxItems);

        // ---- the Codex hides the loot until the monster's rank is high enough; that is only cosmetic, so show it
        try {
            G.call("h2d.Object", "set_visible", [G.field(sheet, "dropsPanel"), true]);
            var lock = G.field(sheet, "unlockDropsText");
            if (lock != null) G.call("h2d.Object", "set_visible", [lock, false]);
        } catch (_:Dynamic) {}
        try G.call("h2d.Flow", "reflow", [icons]) catch (_:Dynamic) {}
    }
}
