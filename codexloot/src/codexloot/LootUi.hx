package codexloot;

/** Draws on the Codex window: the missing loot buttons, the drop chances and the monster tags. */
class LootUi {
    static function percent(p:Float):String {
        var v = p * 100;
        if (v >= 10) return Std.string(Math.round(v)) + "%";
        if (v >= 1) return Std.string(Math.round(v * 10) / 10) + "%";
        if (v >= 0.01) return Std.string(Math.round(v * 100) / 100) + "%";
        return "<0.01%";
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

    /** The tooltip of an item. With `level` > 0 the item is created at that level, as a drop of that level would be. */
    static function tooltip(item:Dynamic, level:Int):Dynamic {
        var real:Dynamic = null;
        if (level > 0) {
            try {
                var drop = {count: 1, flags: null, item: G.str(G.field(item, "id")), itemFlags: null, lootLevel: level, lootTableFlags: null, maxRarity: null, minRarity: null, rarity: null};
                real = G.callStatic("st.Item", "create", [G.str(G.field(item, "id")), drop]);
            } catch (_:Dynamic) { real = null; }
        }
        return G.callStatic("ui.Tooltip", "fromItem", [item, real]);
    }

    /** A Codex button for an item, built the way the game builds them (CodexData.createItemNode), without registering anything. `level` > 0: the tooltip shows the item at that level. */
    static function makeButton(item:Dynamic, parent:Dynamic, level:Int):Dynamic {
        var node = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("data.CodexNode"), 0, []);
        HlxRuntime.setField(node, "name", G.str(G.field(item, "id")));
        HlxRuntime.setField(node, "data", item);
        HlxRuntime.setField(node, "_icon", G.field(item, "gfx"));
        HlxRuntime.setField(node, "clickable", false);
        HlxRuntime.setField(node, "forcedRevealed", true);
        try HlxRuntime.setField(node, "progressThresholds", G.callStatic("st.player.Progress", "getItemProgressThreshold", [item])) catch (_:Dynamic) {}
        var tip = function():Dynamic return tooltip(item, level);
        HlxRuntime.setField(node, "getTooltip", tip);

        var button = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("ui.win.codex.CodexButton"), 2, [node, parent]);
        var dom = G.field(button, "dom");
        try G.call(G.typeName(dom), "addClass", [dom, "small"]) catch (_:Dynamic) {
            try G.call(G.typeName(dom), "addClass", [dom, "small", null]) catch (_:Dynamic) {}
        }
        return button;
    }

    static var font:Dynamic;
    static var fontSize:Float = 0;

    /** A font for our texts: a font the Codex window already uses if possible, the engine's default font otherwise. */
    public static function prepare(sheet:Dynamic, button:Dynamic):Bool {
        if (font != null) return true;
        var candidates:Array<Dynamic> = [G.field(sheet, "dropHeader"), G.field(sheet, "description"), G.field(button, "currentProgress")];
        try {
            for (name in Reflect.fields(sheet)) {
                var v = G.field(sheet, name);
                if (G.typeName(v).indexOf("Text") >= 0) candidates.push(v);
            }
        } catch (_:Dynamic) {}
        for (candidate in candidates) {
            var f = G.field(candidate, "font");
            if (f != null) {
                font = f;
                fontSize = G.num(G.field(f, "size"));
                return true;
            }
        }
        try {
            var f = G.callStatic("hxd.res.DefaultFont", "get", []);
            if (f != null) { font = f; fontSize = 0; return true; }
        } catch (_:Dynamic) {}
        return false;
    }

    /** Scale that gives the font a height of about `px` pixels. */
    static function scaleFor(px:Float):Float {
        var s = fontSize > 0 ? px / fontSize : 2.0;
        return Math.max(0.5, Math.min(4.0, s));
    }

    static function newText(parent:Dynamic, text:String, color:Int, scale:Float):Dynamic {
        var t = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Text"), 2, [font, parent]);
        G.call("h2d.Text", "set_text", [t, text]);
        try G.call("h2d.Text", "set_textColor", [t, color]) catch (_:Dynamic) {}
        if (scale != 1.0) G.call("h2d.Object", "setScale", [t, scale]);
        return t;
    }

    /** Text with a black outline (shifted black copies under the coloured text). */
    static function outlined(parent:Dynamic, text:String, color:Int, px:Float):Dynamic {
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

    static function isRussian(sheet:Dynamic):Bool {
        var t = G.str(G.field(G.field(sheet, "dropHeader"), "text"));
        for (i in 0...t.length) {
            var c = t.charCodeAt(i);
            if (c != null && c >= 0x400 && c <= 0x4FF) return true;
        }
        return false;
    }

    public static function apply(sheet:Dynamic, normal:Array<LootCalc.LootEntry>, heroic:Array<LootCalc.LootEntry>, maxItems:Int):Void {
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

        // ---- heroic mode loot: its own block under a caption
        if (heroic.length > 0) {
            try {
                var ready = prepare(sheet, anyButton);
                if (ready) {
                    var caption = outlined(icons, isRussian(sheet) ? "Героический режим" : "Heroic mode", 0xFFB347, 18.0);
                    HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [icons, caption]), "lineBreak", true);
                }
                var first = true;
                for (entry in heroic) {
                    if (added >= maxItems) break;
                    var button:Dynamic = null;
                    try button = makeButton(entry.item, icons, maxLevel()) catch (_:Dynamic) {}
                    if (button == null) continue;
                    if (first) {
                        first = false;
                        try HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [icons, button]), "lineBreak", true) catch (_:Dynamic) {}
                    }
                    added++;
                    try { if (ready) tag(button, percent(entry.chance), 0xFFB347, 12.0); } catch (_:Dynamic) {}
                }
            } catch (_:Dynamic) {}
        }

        // ---- the Codex hides the loot until the monster's rank is high enough; that is only cosmetic, so show it
        try {
            G.call("h2d.Object", "set_visible", [G.field(sheet, "dropsPanel"), true]);
            var lock = G.field(sheet, "unlockDropsText");
            if (lock != null) G.call("h2d.Object", "set_visible", [lock, false]);
        } catch (_:Dynamic) {}
        try G.call("h2d.Flow", "reflow", [icons]) catch (_:Dynamic) {}
    }
}
