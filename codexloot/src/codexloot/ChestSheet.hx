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
        for (e in entries) {
            var on = chest != null && e.chest == chest;
            try G.call("ui.UIElement", "set_selected", [e.button, on]) catch (_:Dynamic) {}
        }
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
        setText(G.field(s, "description"), ChestData.describe(chest, loot).join("<br/>"));
        show(G.field(s, "dropsPanel"), true);
        show(G.field(s, "unlockDropsText"), false);
        fillDrops(s, drops, loot, searchText(s));
        relayout(s);
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
        var made:Array<{button:Dynamic, item:Dynamic, chance:Float}> = [];
        for (e in loot.entries) {
            try {
                var button = LootUi.makeButton(e.item, drops, loot.level, loot.minRarity);
                if (any == null) any = button;
                made.push({button: button, item: e.item, chance: e.chance});
            } catch (_:Dynamic) {}
        }
        if (any != null && LootUi.prepare(s, any))
            for (m in made) try LootUi.tag(m.button, LootUi.percent(m.chance), 0xFFFFFF, 12.0) catch (_:Dynamic) {}
        // while searching, the items that match are the ones to look at
        if (text != "")
            for (m in made) try { if (!ChestNames.matches(m.item, text)) HlxRuntime.setField(m.button, "alpha", 0.3); } catch (_:Dynamic) {}
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
        selectedId = "";
        computed = new Map();
    }
}
