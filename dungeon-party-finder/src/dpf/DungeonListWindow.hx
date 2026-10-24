package dpf;

import dpf.DungeonList.DungeonInfo;
import dpf.GameAccess as G;
import dpf.NativeUi as N;

/**
 * The list of dungeons, in a window of the game itself (the same "options" window frame, header, close button and buttons as
 * the Dungeon Button mod's list). It shows all of them; ten rows are visible and the rest is reached with the mouse wheel or the
 * scroll bar. A click on a row picks the dungeon.
 */
class DungeonListWindow {
    static inline var WIDTH = 480;
    static inline var HEADER = 48;
    static inline var SIDE = 12;
    static inline var ROW = 34;
    static inline var GAP = 4;
    static inline var VISIBLE = 10;
    /** Room kept at the right of the rows for the flow's own scroll bar (it shows itself when the rows do not fit). */
    static inline var BAR = 22;


    var window:Dynamic;
    var onPick:DungeonInfo -> Void;
    var onClose:Void -> Void;

    public function new() {}

    public function whenClosed(handler:Void -> Void):Void onClose = handler;

    public function isOpen():Bool {
        return window != null && G.field(window, "parent") != null && G.field(window, "removed") != true;
    }

    public function hide():Void {
        var old = window;
        window = null;
        if (old == null) return;
        if (G.field(old, "parent") != null) DungeonScreens.close(old);
    }

    /** Every frame while the hero is in the world: notices a window the game closed by itself (Esc). */
    public function update():Void {
        if (window != null && !isOpen()) {
            window = null;
            if (onClose != null) onClose();
        }
    }

    public function show(entries:Array<DungeonInfo>, onPick:DungeonInfo -> Void):Void {
        hide();
        this.onPick = onPick;
        var gui = DungeonScreens.gui();
        if (gui == null) return;
        try build(gui, entries) catch (error:Dynamic) {
            trace("[DPF] list failed: " + Std.string(error));
            hide();
        }
    }

    function flagBit(name:String):Int return 1 << Type.enumIndex(G.current("ui.win.WindowFlags", name));

    function build(gui:Dynamic, entries:Array<DungeonInfo>):Void {
        var rows = Std.int(Math.max(1, Math.min(VISIBLE, entries.length)));
        var bodyH = rows * ROW + (rows - 1) * GAP;
        var height = HEADER + SIDE + bodyH + SIDE + 4;
        var inner = WIDTH - SIDE * 2;

        var win = G.create("ui.win.TitleWindow", ["Options", null]);
        window = win;
        var flags = flagBit("PreventCloseOther") | flagBit("FreeCursor") | flagBit("AutoRegisterLayer") | flagBit("BlockInputs") | flagBit("BlockSkills");
        G.call("ui.win.BaseWindow", "set_windowFlags", win, [flags]);
        var root = G.field(gui, "root");
        G.call("h2d.Flow", "addChildAt", root, [win, G.integer(G.call("h2d.Object", "get_numChildren", root))]);
        G.call("ui.BaseUI", "displayWindow", gui, [win, null]);
        N.absolute(root, win);

        var dom = G.field(win, "dom");
        var content = G.field(dom, "contentRoot");
        G.set(dom, "component", G.staticCall("domkit.Component", "get", ["options-window", null]));
        if (content == null) throw "The window's content is unavailable";
        N.size(win, WIDTH, height);
        N.padding(win, 0);
        for (child in N.children(win)) {
            if (G.field(child, "bgMask") == null) continue;
            N.absolute(win, child);
            N.padding(child, 0);
            N.size(child, WIDTH, height);
            N.position(child, 0, 0);
        }

        var header = G.field(win, "header");
        N.absolute(win, header);
        N.padding(header, 0);
        N.size(header, WIDTH - 2, HEADER);
        N.position(header, 0, 0);
        G.call("ui.win.TitleWindow", "setHeader", win, [null, Locale.listTitle()]);
        var title = G.field(header, "headerTitle");
        var left = G.current("h2d.Align", "Left");
        G.call("h2d.Text", "set_textAlign", title, [left]);
        N.style(title, "text-align", left);
        N.absolute(header, title);
        G.call("ui.comp.FmtText", "updateScale", title, []);
        N.position(title,
            (WIDTH - G.number(G.call("h2d.Text", "get_textWidth", title)) * G.number(G.field(title, "scaleX"), 1)) / 2,
            (HEADER - G.number(G.call("h2d.Text", "get_textHeight", title)) * G.number(G.field(title, "scaleY"), 1)) / 2);
        var closeBtn = G.field(header, "closeBtn");
        N.show(closeBtn, true);
        N.absolute(header, closeBtn);
        N.size(closeBtn, 32, 32);
        N.position(closeBtn, WIDTH - 44, 8);
        G.call("ui.UIElement", "set_onClick", closeBtn, [() -> hide()]);

        N.absolute(win, content);
        N.padding(content, 0);
        N.size(content, inner, height - HEADER - SIDE);
        N.position(content, SIDE, HEADER);

        // The rows live in a vertical flow that scrolls: ten show, the wheel and the bar reach the rest.
        var list = G.field(N.node("flow", dom, [], "dpfDungeonList", "vertical"), "obj");
        N.absolute(content, list);
        N.padding(list, 0);
        N.size(list, inner, bodyH);
        N.position(list, 0, 0);
        G.call("h2d.Flow", "set_verticalSpacing", list, [GAP]);
        N.style(list, "vspacing", GAP);
        var top = G.current("h2d.FlowAlign", "Top");
        G.call("h2d.Flow", "set_verticalAlign", list, [top]);
        N.style(list, "content-valign", top);
        var scroll = G.current("h2d.FlowOverflow", "Scroll");
        G.call("h2d.Flow", "set_overflow", list, [scroll]);
        N.style(list, "overflow", scroll);
        var listDom = G.field(list, "dom");
        // The flow's own scroll bar comes out as wide as the game's stylesheet says, which is nothing: give it a width.
        var scrollBar = G.field(list, "scrollBar");
        var cursor = G.field(list, "scrollBarCursor");
        if (scrollBar != null) {
            N.size(scrollBar, BAR - 12);
            G.call("h2d.Flow", "set_backgroundTile", scrollBar, [G.staticCall("h2d.Tile", "fromColor", [0x5B4334, 1, 1, 0.35, null])]);
        }
        if (cursor != null) {
            N.size(cursor, BAR - 12);
            G.call("h2d.Flow", "set_backgroundTile", cursor, [G.staticCall("h2d.Tile", "fromColor", [0x8A5F46, 1, 1, 1.0, null])]);
        }

        var rowWidth = inner - (entries.length > VISIBLE ? BAR : 0);
        for (i in 0...entries.length) {
            var entry = entries[i];
            var text = Locale.level(entry.level) + "  |  " + entry.name;
            var row = N.button(listDom, text, "dpfDungeon" + i, () -> pick(entry));
            N.inFlow(list, row);
            N.size(row, rowWidth, ROW);
        }
        if (entries.length == 0) {
            var empty = N.label(listDom, Locale.listEmpty(), "dpfDungeonEmpty");
            N.inFlow(list, empty);
        }

        // Centered on the screen.
        var scene = G.field(gui, "s2d");
        var scale = Math.max(0.01, G.number(G.field(root, "scaleX"), 1));
        var sceneW = G.number(G.field(scene, "width"), 1920) / scale, sceneH = G.number(G.field(scene, "height"), 1080) / scale;
        N.position(win, Math.max(0, (sceneW - WIDTH) / 2), Math.max(0, (sceneH - height) / 2));
    }

    function pick(entry:DungeonInfo):Void {
        // The window stays until the dungeon window is ready (DpfMod.pick closes it then).
        if (onPick != null) onPick(entry);
    }
}
