package codexloot;

/**
 * The two tabs under the Codex window: "Codex" (the game's own Codex) and "Chests" (ChestSheet).
 *
 * The tab bar is a child of the game's 2D scene, placed under the lower left corner of the window (the way the game's
 * own bottom tabs hang under their windows): the Codex window clips everything outside its frame, so the bar cannot
 * be a child of the window. It follows the window every frame and goes away with it.
 *
 * A new Codex window always starts on the "Codex" tab. Switching rebuilds the window (BaseWindow.rebuild runs
 * CodexWindow.init again); in "Chests" mode the content of init is replaced by the chest sheet.
 */
class CodexTabs {
    static inline var TAB_W = 150;
    static inline var TAB_H = 40;
    static inline var GAP = 4;
    static inline var SELECTED = 0xCFB8AA;
    static inline var NORMAL = 0xB1978D;
    static inline var HOVER = 0xBEA79D;
    static inline var TEXT_SELECTED = 0x4B433E;
    static inline var TEXT_NORMAL = 0xFEFEFE;
    /** The height of the Codex window in the game's style sheet (codex-window), used until the window has measured itself. */
    static inline var WINDOW_H = 750.0;

    /** The Codex window the tabs belong to. */
    static var window:Dynamic;
    static var chestMode = false;
    static var app:Dynamic;
    static var bar:Dynamic;
    static var tabs:Array<{chests:Bool, box:Dynamic, graphics:Dynamic, label:Dynamic, hover:Bool}> = [];
    static var barRussian:Null<Bool>;
    /** The last error of the tab bar or the chest page (shown by the test mode). */
    public static var lastError = "";
    /** Frames left until the bar is made again with the window's own font (the fonts of a new window are set a frame later). */
    static var barRetry = 0;

    /** For the test mode: the state of the tab bar. */
    public static function debug():Dynamic {
        return {error: lastError, bar: bar != null, tabs: tabs.length, appKnown: app != null, x: bar == null ? 0 : G.num(G.field(bar, "x")), y: bar == null ? 0 : G.num(G.field(bar, "y")),
            scale: bar == null ? 0 : G.num(G.field(bar, "scaleX")), visible: bar == null ? false : G.field(bar, "visible"), parent: bar == null ? "" : G.typeName(G.field(bar, "parent"))};
    }

    public static function inChestMode():Bool return chestMode && window != null;

    public static function currentWindow():Dynamic return window;

    // ---- the window's init ----

    /** Before CodexWindow.init: a new window starts on the Codex tab; in chest mode the cheapest page is built (the sheet replaces it). */
    public static function beforeInit(w:Dynamic):Void {
        if (w != window) {
            window = w;
            chestMode = false;
            ChestSheet.release();
            destroyBar();
        }
        // the fourth page of the game's enum builds nothing of its own (the chest sheet comes in its place) but has the banner and the back button of a page
        if (chestMode) resetPage(w, "Dungeons");
    }

    /** After CodexWindow.init: the chest sheet in chest mode, and the tab bar. */
    public static function afterInit(w:Dynamic):Void {
        if (w != window) return;
        if (chestMode) try ChestSheet.build(w) catch (e:Dynamic) lastError = "chest page: " + Std.string(e);
        else ChestSheet.release();
        try attach(w) catch (e:Dynamic) lastError = "tab bar: " + Std.string(e);
    }

    /** The Codex home page: the region buttons. */
    static function resetPage(w:Dynamic, panel:String = "Regions"):Void {
        try {
            // the game compares the page with the enum's own constants: the constant itself is needed, not a new value
            HlxRuntime.setField(w, "panel", HlxRuntime.resolveStaticField(HlxRuntime.resolveType("ui.win.codex.CodexPanel"), panel));
            HlxRuntime.setField(w, "currentNode", HlxRuntime.resolveStaticField(HlxRuntime.resolveType("data.CodexData"), "rootNode"));
        } catch (_:Dynamic) {}
    }

    /** Switches the window to the Codex (chests = false) or the Chests tab. */
    public static function switchTo(chests:Bool):Void {
        if (window == null || chestMode == chests) return;
        chestMode = chests;
        if (!chests) resetPage(window);
        // rebuild() runs the window's init again, which builds the page of the new tab
        G.call("ui.win.BaseWindow", "rebuild", [window]);
        try updateBar() catch (_:Dynamic) {}
    }

    // ---- the tab bar ----

    static function drawTab(t:{chests:Bool, box:Dynamic, graphics:Dynamic, label:Dynamic, hover:Bool}):Void {
        var on = t.chests == chestMode;
        var color = on ? SELECTED : (t.hover ? HOVER : NORMAL);
        var g = t.graphics;
        G.call("h2d.Graphics", "clear", [g]);
        G.call("h2d.Graphics", "beginFill", [g, color, 1.0]);
        // a tab with rounded lower corners, as the game's bottom tabs
        G.call("h2d.Graphics", "drawRect", [g, 0.0, 0.0, TAB_W * 1.0, TAB_H - 5.0]);
        G.call("h2d.Graphics", "drawRect", [g, 1.0, TAB_H - 5.0, TAB_W - 2.0, 1.0]);
        G.call("h2d.Graphics", "drawRect", [g, 2.0, TAB_H - 4.0, TAB_W - 4.0, 1.0]);
        G.call("h2d.Graphics", "drawRect", [g, 3.0, TAB_H - 3.0, TAB_W - 6.0, 1.0]);
        G.call("h2d.Graphics", "drawRect", [g, 5.0, TAB_H - 2.0, TAB_W - 10.0, 1.0]);
        G.call("h2d.Graphics", "drawRect", [g, 7.0, TAB_H - 1.0, TAB_W - 14.0, 1.0]);
        G.call("h2d.Graphics", "endFill", [g]);
        try G.call("h2d.Text", "set_textColor", [t.label, on ? TEXT_SELECTED : TEXT_NORMAL]) catch (_:Dynamic) {}
        HlxRuntime.setField(t.label, "alpha", on ? 1.0 : 0.85);
    }

    static function addTab(chests:Bool, label:String, x:Int):Void {
        var box = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Interactive"), 4, [TAB_W * 1.0, TAB_H * 1.0, bar, null]);
        G.call("h2d.Object", "setPosition", [box, x * 1.0, 0.0]);
        var g = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Graphics"), 1, [box]);
        var text = LootUi.canDraw(label) ? label : (chests ? "Chests" : "Codex");
        var s = LootUi.scaleFor(18.0);
        var t = LootUi.newText(box, text, TEXT_NORMAL, s);
        var w = G.num(G.call("h2d.Text", "get_textWidth", [t])) * s;
        var h = G.num(G.call("h2d.Text", "get_textHeight", [t])) * s;
        G.call("h2d.Object", "setPosition", [t, Math.max(2.0, (TAB_W - w) / 2), Math.max(0.0, (TAB_H - 4 - h) / 2)]);
        var tab = {chests: chests, box: box, graphics: g, label: t, hover: false};
        HlxRuntime.setField(box, "onOver", (_:Dynamic) -> { tab.hover = true; drawTab(tab); });
        HlxRuntime.setField(box, "onOut", (_:Dynamic) -> { tab.hover = false; drawTab(tab); });
        HlxRuntime.setField(box, "onClick", (_:Dynamic) -> { try switchTo(chests) catch (_:Dynamic) {} });
        try G.call("h2d.Interactive", "set_cursor", [box, HlxRuntime.constructEnum(HlxRuntime.resolveType("hxd.Cursor"), "Button", [])]) catch (_:Dynamic) {}
        tabs.push(tab);
        drawTab(tab);
    }

    static function createBar(w:Dynamic):Void {
        var scene = G.field(app, "s2d");
        if (scene == null || !LootUi.prepare(w, null)) return;
        bar = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Object"), 1, [scene]);
        tabs = [];
        addTab(false, SettingsText.tabCodex(), 0);
        addTab(true, SettingsText.tabChests(), TAB_W + GAP);
        barRussian = SettingsText.russian;
        barRetry = LootUi.canDraw("Кодекс") ? 0 : 5;
    }

    static function attach(w:Dynamic):Void {
        if (app == null) return;
        if (bar != null && barRussian != SettingsText.russian) destroyBar(); // the client's language changed
        if (bar == null) createBar(w);
        if (bar == null) return;
        for (t in tabs) drawTab(t);
        updateBar();
    }

    static function destroyBar():Void {
        if (bar != null) try G.call("h2d.Object", "remove", [bar]) catch (_:Dynamic) {}
        bar = null;
        tabs = [];
    }

    /** Puts the bar under the lower left corner of the window, scaled as the window is (from the window's own position on the scene). */
    static function updateBar():Void {
        if (bar == null || window == null) return;
        var scale = G.num(G.field(window, "matA"));
        if (scale <= 0) return; // not placed on the scene yet
        var height = G.num(G.field(window, "calculatedHeight"));
        if (height <= 0) height = WINDOW_H;
        G.call("h2d.Object", "setScale", [bar, scale]);
        G.call("h2d.Object", "setPosition", [bar, G.num(G.field(window, "absX")) + 25 * scale, G.num(G.field(window, "absY")) + height * G.num(G.field(window, "matD"))]);
        HlxRuntime.setField(bar, "visible", G.field(window, "visible") != false);
        var alpha = G.num(G.field(window, "alpha"));
        HlxRuntime.setField(bar, "alpha", alpha > 0 ? alpha : 1.0);
    }

    /** Every frame (GameApp.update): the bar follows the window and goes away when the window is gone. */
    public static function tick(gameApp:Dynamic):Void {
        app = gameApp;
        ChestSheet.tick();
        if (bar == null) return;
        if (barRetry > 0 && --barRetry == 0 && window != null) {
            var w = window;
            destroyBar();
            try attach(w) catch (_:Dynamic) {}
            return;
        }
        try {
            if (window == null || G.field(window, "removed") == true || G.field(window, "parent") == null) {
                destroyBar();
                window = null;
                chestMode = false;
                ChestSheet.release();
                return;
            }
            updateBar();
        } catch (_:Dynamic) {}
    }
}
