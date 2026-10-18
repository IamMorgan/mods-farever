package codexloot;

/**
 * The "Chests" page of the Codex: a Codex monster sheet (ui.win.codex.CodexUnitSheet) filled with chests instead of
 * monsters, so it looks like the Monsters page: the chest list with the search on the left, in the middle what the chest
 * is, where to get it and its contents with the chance of each item (the way a monster's trophies are shown), on the
 * right the picture of the chest.
 *
 * The sheet is the game's own, built with an empty node (so it lists no monsters) and marked by that node; its list
 * (updateUnitNodes) and selection (setSelectedUnit) are taken over by this class.
 */
class ChestSheet {
    /** The node the chest sheet is built with; a sheet whose `codexData` is this node is ours. */
    static var marker:Dynamic;
    /** The sheet in use (null: none, or still being built). */
    static var sheet:Dynamic;
    static var entries:Array<{chest:Dynamic, button:Dynamic}> = [];
    static var selectedId = "";
    static var selectedChest:Dynamic;
    static var image:Dynamic;
    /** The Codex window the sheet is in. */
    static var owner:Dynamic;
    static var computed = new Map<String, ChestMath.ChestLootResult>();
    /** The frame drawn around the selected chest of the list. */
    static var frame:Dynamic;
    static inline var FRAME_COLOR = 0xFFDC15;
    static inline var FRAME_WIDTH = 3.0;

    /** For the test mode: the buttons of the list with their selected state and style classes. */
    public static function debugButtons():Array<Dynamic> {
        var out:Array<Dynamic> = [];
        for (e in entries) {
            var dom = G.field(e.button, "dom");
            var classes:Array<String> = [];
            try {
                var it = G.call("domkit.Properties", "getClasses", [dom]);
                var iter = HlxRuntime.resolveField(it, "iterator");
                var i = Reflect.callMethod(it, iter, []);
                while (i.hasNext()) classes.push(Std.string(i.next()));
            } catch (x:Dynamic) classes.push("?" + Std.string(x));
            out.push({id: ChestData.idOf(e.chest), selected: G.field(e.button, "selected"), hasSelectedClass: try G.call("domkit.Properties", "hasClass", [dom, "selected"]) catch (_:Dynamic) null, classes: classes});
        }
        return out;
    }

    /** For the test mode: the click of the mouse on the button of a chest. */
    public static function debugClick(id:String):Bool {
        for (e in entries) if (ChestData.idOf(e.chest) == id) {
            var f = G.field(e.button, "onButtonClicked");
            if (f == null) return false;
            Reflect.callMethod(null, f, [null]);
            return true;
        }
        return false;
    }

    /** For the test mode: the fonts of the description text. */
    public static function debugFonts():Dynamic {
        var d = G.field(sheet, "description");
        var f = G.field(d, "font");
        return {text: {name: G.str(G.field(f, "name")), size: G.num(G.field(f, "size")), scaleX: G.num(G.field(d, "scaleX")), lineHeight: G.num(G.field(f, "lineHeight")), letterSpacing: G.num(G.field(d, "letterSpacing"))},
            bold: boldFont == null ? null : {name: G.str(G.field(boldFont, "name")), size: G.num(G.field(boldFont, "size")), lineHeight: G.num(G.field(boldFont, "lineHeight"))}};
    }

    public static function owns(instance:Dynamic):Bool return marker != null && instance != null && G.field(instance, "codexData") == marker;

    public static function current():Dynamic return sheet;

    public static function selected():String return selectedId;

    public static function listed():Array<String> return [for (e in entries) ChestData.idOf(e.chest)];

    static function show(obj:Dynamic, visible:Bool):Void {
        if (obj == null) return;
        try G.call(G.typeName(obj), "set_visible", [obj, visible]) catch (_:Dynamic) {
            try HlxRuntime.setField(obj, "visible", visible) catch (_:Dynamic) {}
        }
    }

    /** Puts a frame around the selected chest's button (the game's list style has no selected look for these buttons). */
    static function highlight(button:Dynamic):Void {
        if (frame != null) try G.call("h2d.Object", "remove", [frame]) catch (_:Dynamic) {}
        frame = null;
        if (button == null) return;
        try {
            var w = G.num(G.field(button, "calculatedWidth"));
            var h = G.num(G.field(button, "calculatedHeight"));
            if (w <= 0) w = 78;
            if (h <= 0) h = 78;
            var g = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Graphics"), 1, [button]);
            G.call("h2d.Graphics", "beginFill", [g, FRAME_COLOR, 1.0]);
            var t = FRAME_WIDTH;
            G.call("h2d.Graphics", "drawRect", [g, 0.0, 0.0, w, t]);
            G.call("h2d.Graphics", "drawRect", [g, 0.0, h - t, w, t]);
            G.call("h2d.Graphics", "drawRect", [g, 0.0, t, t, h - 2 * t]);
            G.call("h2d.Graphics", "drawRect", [g, w - t, t, t, h - 2 * t]);
            G.call("h2d.Graphics", "endFill", [g]);
            var props = G.call("h2d.Flow", "getProperties", [button, g]);
            HlxRuntime.setField(props, "isAbsolute", true);
            frame = g;
        } catch (_:Dynamic) {}
    }

    static function setText(text:Dynamic, value:String):Void {
        if (text == null) return;
        try G.call("ui.comp.FmtText", "set_text", [text, value]) catch (_:Dynamic) {}
    }

    /** What the loot of a chest is for the hero now (cached while the sheet is open). */
    public static function lootOf(chest:Dynamic):ChestMath.ChestLootResult {
        var id = ChestData.idOf(chest);
        var r = computed.get(id);
        if (r == null) {
            r = ChestLoot.compute(chest, CodexLoot.hero);
            computed.set(id, r);
        }
        return r;
    }

    /** True when the chest's name, or any item it offers, contains `text` (in the client's language, English or Russian). */
    public static function chestMatches(chest:Dynamic, text:String):Bool {
        if (ChestNames.matches(chest, text)) return true;
        for (e in lootOf(chest).entries) if (ChestNames.matches(e.item, text)) return true;
        return false;
    }

    static function searchText(s:Dynamic):String {
        try return StringTools.trim(G.str(G.call("ui.comp.SearchInput", "get_text", [G.field(s, "search")]))) catch (_:Dynamic) return "";
    }

    /** Called by the window once its own content is built: puts the chest sheet in the place of the Codex content. */
    public static function build(window:Dynamic):Void {
        sheet = null;
        entries = [];
        image = null;
        computed = new Map();
        selectedId = "";
        // the Codex content the window built (its region buttons, or a sheet when a page was open) is not needed
        var old = G.field(window, "codexButtons");
        if (old != null) G.call("h2d.Object", "remove", [old]);
        for (child in G.children(window)) {
            var t = G.typeName(child);
            if (t == "ui.win.codex.CodexUnitSheet" || t == "ui.win.codex.CodexActivitySheet") G.call("h2d.Object", "remove", [child]);
        }
        owner = window;
        marker = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("data.CodexNode"), 0, []);
        var s = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("ui.win.codex.CodexUnitSheet"), 2, [marker, window]);
        style(s);
        setBanner();
        sheet = s;
        fixFrames = 6;
        refresh(s);
    }

    /** One-time changes of the monster sheet for the chests. */
    static function style(s:Dynamic):Void {
        show(G.field(s, "unitFilter"), false); // filters by monster type and discovery: nothing to filter here
        show(G.field(s, "unitView"), false); // the 3D monster view
        show(G.field(s, "progressPanel"), false); // kills / mastery
        show(G.field(s, "unlockDropsText"), false);
        setText(G.field(s, "unitName"), SettingsText.tabChests());
        setText(G.field(s, "unitType"), "");
        setText(G.field(s, "dropHeader"), SettingsText.chestsHeader());
        // the lore block has a fixed height; the description of a chest is longer than a monster's flavour text
        relaxLore(s);
        // the list scrolls under the right edge of the panel as the monster list does: keep the buttons clear of the scroll bar
        LootUi.keepClearOfScrollBar(G.field(s, "unitList"));
    }

    /** The lore block has a fixed height in the style sheet, which the game applies a frame after the sheet is made: undo it. */
    static function relaxLore(s:Dynamic):Void {
        var lore = G.field(s, "lorePanel");
        if (lore == null) return;
        try {
            HlxRuntime.setField(lore, "minHeight", null);
            HlxRuntime.setField(lore, "maxHeight", null);
            HlxRuntime.setField(lore, "paddingBottom", 16);
            HlxRuntime.setField(lore, "needReflow", true);
        } catch (_:Dynamic) {}
    }

    static var fixFrames = 0;

    /** Every frame: for a few frames after the sheet is made its style is applied again by the game, so the changes are repeated. */
    public static function tick():Void {
        var s = sheet;
        if (s == null || fixFrames <= 0) return;
        fixFrames--;
        // the fonts of the texts are known now: the icons' captions are made again with them
        if (fixFrames == 3 && selectedChest != null) select(selectedChest);
        relaxLore(s);
        relayout(s);
    }

    /** The list on the left (all chests, or those matching the search) and the selection. Called for every change of the search. */
    public static function refresh(s:Dynamic):Void {
        if (s != sheet) return;
        var list = G.field(s, "unitList");
        if (list == null) return;
        G.call("h2d.Flow", "removeChildren", [list]);
        entries = [];
        frame = null; // removed with the buttons
        var text = searchText(s);
        for (chest in ChestData.chests()) {
            try {
                if (text != "" && !chestMatches(chest, text)) continue;
                var button = LootUi.makeButton(chest, list, 0, "", true, false);
                show(G.field(button, "progressTexts"), false);
                HlxRuntime.setField(button, "onButtonClicked", (_:Dynamic) -> select(chest));
                entries.push({chest: chest, button: button});
            } catch (_:Dynamic) {}
        }
        var pick:Dynamic = null;
        for (e in entries) if (ChestData.idOf(e.chest) == selectedId) pick = e.chest;
        if (pick == null && entries.length > 0) pick = entries[0].chest;
        select(pick);
        try G.call("h2d.Flow", "reflow", [list]) catch (_:Dynamic) {}
    }

    public static function select(chest:Dynamic):Void {
        var s = sheet;
        if (s == null) return;
        var drops = G.field(s, "dropsIcons");
        if (drops != null) G.call("h2d.Flow", "removeChildren", [drops]);
        var chosen:Dynamic = null;
        for (e in entries) {
            var on = chest != null && e.chest == chest;
            try G.call("ui.UIElement", "set_selected", [e.button, on]) catch (_:Dynamic) {}
            if (on) chosen = e.button;
        }
        highlight(chosen);
        setImage(s, chest);
        if (chest == null) {
            selectedId = "";
            setText(G.field(s, "loreTitle"), "");
            setText(G.field(s, "unitType"), "");
            setText(G.field(s, "description"), searchText(s) == "" ? "" : SettingsText.chestsNothing());
            show(G.field(s, "dropsPanel"), false);
            relayout(s);
            return;
        }
        selectedId = ChestData.idOf(chest);
        selectedChest = chest;
        var loot = lootOf(chest);
        var name = ChestData.nameOf(chest);
        setText(G.field(s, "loreTitle"), ""); // the name is in the banner; a long name would wrap over the text below
        setText(G.field(s, "unitType"), name);
        var desc = G.field(s, "description");
        giveBoldFont(desc);
        setText(desc, ChestData.describe(chest, loot).join("<br/>"));
        show(G.field(s, "dropsPanel"), true);
        show(G.field(s, "unlockDropsText"), false);
        fillDrops(s, drops, loot, searchText(s));
        relayout(s);
    }

    static var boldFont:Dynamic;

    /** The bold font of the game that can draw Cyrillic, of the family and the size of the `like` font (a font the text uses). */
    static function findBoldFont(root:Dynamic, like:Dynamic):Dynamic {
        var family = G.str(G.field(like, "name")).split(" ")[0].toLowerCase();
        var wanted = G.num(G.field(like, "size")) + 2; // the bold glyphs come out smaller than the italic ones of the same nominal size
        var best:Dynamic = null;
        var bestScore = 1e9;
        var stack = [root];
        var seen = 0;
        while (stack.length > 0 && seen < 6000) {
            var node = stack.pop();
            seen++;
            if (node == null) continue;
            var f = G.field(node, "font");
            var name = f == null ? "" : G.str(G.field(f, "name")).toLowerCase();
            if (name.indexOf("bold") >= 0 && G.call("h2d.Font", "hasChar", [f, 0x0411]) == true) {
                var size = G.num(G.field(f, "size"));
                var score = Math.abs(size - wanted) + (size < wanted ? 0.5 : 0.0) + (name.indexOf(family) == 0 ? 0 : 100); // not smaller than the text
                if (score < bestScore) { best = f; bestScore = score; }
            }
            for (c in G.children(node)) stack.push(c);
        }
        return best;
    }

    /** The description's HTML text writes <b>..</b> with the font its loadFont returns for "bold": the game gives it none. */
    static function giveBoldFont(text:Dynamic):Void {
        if (text == null) return;
        try {
            var like = G.field(text, "font");
            if (like == null) return; // the text has no font yet: the page is selected again a few frames later
            var exact = boldFont != null && G.str(G.field(boldFont, "name")).toLowerCase().indexOf(G.str(G.field(like, "name")).split(" ")[0].toLowerCase()) == 0;
            if (!exact) {
                // the whole scene: the Codex window may not be on it yet, and the HUD and other windows use bold fonts too
                var top:Dynamic = HlxRuntime.resolveStaticField(HlxRuntime.resolveType("ui.BaseUI"), "current");
                top = G.field(top, "s2d");
                var found = top == null ? null : findBoldFont(top, like);
                if (found != null) boldFont = found;
            }
            var f = boldFont;
            if (f != null) HlxRuntime.setField(text, "loadFont", (name:String) -> name == "bold" ? f : null);
        } catch (_:Dynamic) {}
    }

    /** The title of the window's top banner: the Chests page (init gave it the name of the icon of the page). */
    static function setBanner():Void {
        if (owner == null) return;
        try G.call("ui.win.TitleWindow", "setBannerTexts", [owner, SettingsText.tabChests(), null]) catch (_:Dynamic) {}
        try G.call("ui.win.TitleWindow", "setHeader", [owner, "ChestCompletion", null]) catch (_:Dynamic) {}
    }

    /** The texts changed size: the panels of the sheet are laid out again. */
    static function relayout(s:Dynamic):Void {
        for (name in ["lorePanel", "leftPanel", "dataPanel", "dropsPanel"]) {
            var p = G.field(s, name);
            if (p != null) try G.call("h2d.Flow", "reflow", [p]) catch (_:Dynamic) {}
        }
        try G.call("h2d.Flow", "reflow", [s]) catch (_:Dynamic) {}
    }

    /** The contents: an icon with the chance for every item, like the trophies of a monster. */
    static function fillDrops(s:Dynamic, drops:Dynamic, loot:ChestMath.ChestLootResult, text:String):Void {
        if (drops == null) return;
        var any:Dynamic = null;
        var made:Array<{button:Dynamic, item:Dynamic, chance:Float, mine:Bool}> = [];
        for (e in loot.entries) {
            try {
                var button = LootUi.makeButton(e.item, drops, loot.level, loot.minRarity);
                if (any == null) any = button;
                made.push({button: button, item: e.item, chance: e.chance, mine: e.mine});
            } catch (_:Dynamic) {}
        }
        if (any != null && LootUi.prepare(s, any))
            for (m in made) try LootUi.tag(m.button, LootUi.percent(m.chance), 0xFFFFFF, 12.0) catch (_:Dynamic) {}
        // items of other classes are dimmed; while searching, the items that match are the ones to look at
        for (m in made) {
            var alpha = m.mine ? 1.0 : 0.5;
            if (text != "" && !ChestNames.matches(m.item, text)) alpha = 0.3;
            if (alpha < 1.0) try HlxRuntime.setField(m.button, "alpha", alpha) catch (_:Dynamic) {}
        }
        try G.call("h2d.Flow", "reflow", [drops]) catch (_:Dynamic) {}
    }

    /** The picture of the chest on the right (its item icon, enlarged). */
    static function setImage(s:Dynamic, chest:Dynamic):Void {
        if (image != null) try G.call("h2d.Object", "remove", [image]) catch (_:Dynamic) {}
        image = null;
        if (chest == null) return;
        var panel = G.field(s, "rightPanel");
        if (panel == null) return;
        try {
            var node = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("data.CodexNode"), 0, []);
            HlxRuntime.setField(node, "_icon", G.field(chest, "gfx"));
            var tile = G.call("data.CodexNode", "get_icon", [node]);
            if (tile == null) return;
            var bmp = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Bitmap"), 2, [tile, panel]);
            var h = G.num(G.field(tile, "height"));
            if (h > 0) G.call("h2d.Object", "setScale", [bmp, Math.min(2.6, 500.0 / h)]);
            var props = G.call("h2d.Flow", "getProperties", [panel, bmp]);
            HlxRuntime.setField(props, "isAbsolute", true);
            HlxRuntime.setField(props, "horizontalAlign", HlxRuntime.constructEnum(HlxRuntime.resolveType("h2d.FlowAlign"), "Middle", []));
            HlxRuntime.setField(props, "verticalAlign", HlxRuntime.constructEnum(HlxRuntime.resolveType("h2d.FlowAlign"), "Middle", []));
            image = bmp;
        } catch (_:Dynamic) {}
    }

    /** The window was closed or rebuilt without chests: let go of everything. */
    public static function release():Void {
        sheet = null;
        entries = [];
        image = null;
        frame = null;
        selectedId = "";
        computed = new Map();
    }
}
