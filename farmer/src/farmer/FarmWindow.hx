package farmer;

import farmer.Catalog.Res;
import farmer.FarmPlan.Quality;
import farmer.GameAccess as G;
import farmer.NativeUi as N;

/**
 * The farm window, in the game's own "options" window frame (as the DPF dungeon list is):
 *  - two scrolling grids of 8 columns, "Gathering" (what ore and plants give) and "Hunting" (what monsters drop). An icon is the
 *    game's own item button with its tooltip; a click picks it (gold frame) and shows the amount still to get under it, which
 *    can be typed;
 *  - the check boxes: recycle gear (with the four qualities) and empty the bag;
 *  - the level to reach, and the Farm / Stop button.
 */
class FarmWindow {
    static inline var COLUMNS = 8;
    static inline var HEADER = 48;
    static inline var SIDE = 14;
    static inline var BAR = 22;
    static inline var GRID_ROWS = 5;
    static inline var GAP = 14;
    static inline var ICON = 56; // the item button's own size

    public var onStart:Void -> Void;
    public var onStop:Void -> Void;
    public var onChanged:Void -> Void;

    var window:Dynamic;
    var plan:FarmPlan;
    var cellW = 60;
    var cellH = 88;
    var cells:Array<Cell> = [];
    var statusLabel:Dynamic;
    var actionButton:Dynamic;
    var recycleBox:Dynamic;
    var clearBox:Dynamic;
    var gearBox:Dynamic;
    var qualityBoxes:Array<Dynamic> = [];
    var levelInput:Dynamic;
    var levelLast = "";
    var running = false;
    var font:Dynamic;

    public function new() {}

    public function isOpen():Bool {
        return window != null && G.field(window, "parent") != null && G.field(window, "removed") != true;
    }

    public function hide():Void {
        var old = window;
        window = null;
        cells = [];
        if (old == null) return;
        if (G.field(old, "parent") != null) {
            var gui = G.field(Probe.app, "gui");
            try G.call("ui.BaseUI", "closeWindow", gui, [old, null]) catch (_:Dynamic) {}
        }
    }

    /** Called every frame: notices a window the game closed (Esc) and reads the typed amounts. */
    public function update(running:Bool, status:String):Void {
        if (window != null && !isOpen()) { window = null; cells = []; }
        if (window == null) return;
        this.running = running;
        N.setText(statusLabel, status);
        N.setButtonText(actionButton, Locale.f(running ? "stop" : "start"));
        var changed = false;
        for (c in cells) {
            var picked = plan.isPicked(c.hunting, c.res.id);
            if (picked != c.shown) { c.shown = picked; N.show(c.frame, picked); N.show(c.box, picked); changed = true; }
            if (!picked) continue;
            var text = G.s(G.field(c.input, "text"));
            if (text != c.lastText) {
                // the player typed: only digits stay, the amount follows the text
                var clean = digits(text);
                if (clean != text) G.call("h2d.TextInput", "set_text", c.input, [clean]);
                c.lastText = clean;
                var typed = Std.parseInt(clean);
                plan.setCount(c.hunting, c.res.id, typed == null ? 0 : typed);
                changed = true;
            } else if (!focusedOn(c.input)) {
                // the bot's counter went down (or the field lost its focus): show the real amount
                var shown = Std.string(plan.count(c.hunting, c.res.id));
                if (text != shown) { G.call("h2d.TextInput", "set_text", c.input, [shown]); c.lastText = shown; }
            }
        }
        var levelField = G.field(levelInput, "input");
        var levelText = G.s(G.field(levelField, "text"));
        if (levelText != levelLast) {
            var clean = digits(levelText);
            if (clean != levelText) G.call("h2d.TextInput", "set_text", levelField, [clean]);
            levelLast = clean;
            var level = Std.parseInt(clean);
            plan.targetLevel = level == null ? 0 : level;
            changed = true;
        }
        if (changed && onChanged != null) onChanged();
    }

    /** Only the digits of the text (the fields take numbers only). */
    static function digits(text:String):String {
        var out = new StringBuf();
        for (i in 0...text.length) {
            var code = text.charCodeAt(i);
            if (code >= 48 && code <= 57) out.addChar(code);
        }
        var s = out.toString();
        return s.length > 5 ? s.substr(0, 5) : s;
    }

    function focusedOn(input:Dynamic):Bool {
        try return G.call("h2d.TextInput", "hasFocus", input) == true catch (_:Dynamic) return false;
    }

    function flagBit(name:String):Int return 1 << Type.enumIndex(G.current("ui.win.WindowFlags", name));

    public function show(plan:FarmPlan, running:Bool):Void {
        hide();
        this.plan = plan;
        this.running = running;
        var gui = G.field(Probe.app, "gui");
        if (gui == null) return;
        if (!Catalog.build()) { Log.t("err", "the item data is not loaded yet"); return; }
        try build(gui) catch (error:Dynamic) {
            Log.t("err", "window failed: " + Std.string(error));
            hide();
        }
    }

    function place(obj:Dynamic, parent:Dynamic, x:Float, y:Float, w:Int = -1, h:Int = -1):Void {
        N.absolute(parent, obj);
        if (w >= 0) N.size(obj, w, h);
        N.position(obj, x, y);
    }

    function build(gui:Dynamic):Void {
        var root = G.field(gui, "root");
        var scene = G.field(gui, "s2d");
        var scale = Math.max(0.01, G.number(G.field(root, "scaleX"), 1));
        var sceneW = G.number(G.field(scene, "width"), 1920) / scale, sceneH = G.number(G.field(scene, "height"), 1080) / scale;
        cellW = Std.int(Math.max(ICON + 2, Math.min(60, (sceneW - 2 * SIDE - GAP - 2 * BAR - 24) / 2 / COLUMNS)));
        cellH = ICON + 4 + 30 + 8; // icon, its amount box under it, a gap: the next row never reaches the box
        var gridW = COLUMNS * cellW + BAR;
        var width = 2 * gridW + GAP + 2 * SIDE;
        var rows = Std.int(Math.max(3, Math.min(GRID_ROWS, Math.floor((sceneH - 420) / cellH))));
        var gridH = rows * cellH;
        var optionsH = 150;
        var height = HEADER + SIDE + 26 + gridH + 12 + optionsH + SIDE;

        var win = G.create("ui.win.TitleWindow", ["Options", null]);
        window = win;
        var flags = flagBit("PreventCloseOther") | flagBit("FreeCursor") | flagBit("AutoRegisterLayer") | flagBit("BlockInputs") | flagBit("BlockSkills");
        G.call("ui.win.BaseWindow", "set_windowFlags", win, [flags]);
        G.call("h2d.Flow", "addChildAt", root, [win, G.integer(G.call("h2d.Object", "get_numChildren", root))]);
        G.call("ui.BaseUI", "displayWindow", gui, [win, null]);
        N.absolute(root, win);

        var dom = G.field(win, "dom");
        var content = G.field(dom, "contentRoot");
        G.set(dom, "component", G.staticCall("domkit.Component", "get", ["options-window", null]));
        if (content == null) throw "The window's content is unavailable";
        N.size(win, width, height);
        N.padding(win, 0);
        for (child in N.children(win)) {
            if (G.field(child, "bgMask") == null) continue;
            N.absolute(win, child);
            N.padding(child, 0);
            N.size(child, width, height);
            N.position(child, 0, 0);
        }

        var header = G.field(win, "header");
        N.absolute(win, header);
        N.padding(header, 0);
        N.size(header, width - 2, HEADER);
        N.position(header, 0, 0);
        G.call("ui.win.TitleWindow", "setHeader", win, [null, Locale.f("title")]);
        var title = G.field(header, "headerTitle");
        var left = G.current("h2d.Align", "Left");
        G.call("h2d.Text", "set_textAlign", title, [left]);
        N.style(title, "text-align", left);
        N.absolute(header, title);
        G.call("ui.comp.FmtText", "updateScale", title, []);
        N.position(title,
            (width - G.number(G.call("h2d.Text", "get_textWidth", title)) * G.number(G.field(title, "scaleX"), 1)) / 2,
            (HEADER - G.number(G.call("h2d.Text", "get_textHeight", title)) * G.number(G.field(title, "scaleY"), 1)) / 2);
        font = G.field(title, "font");
        var closeBtn = G.field(header, "closeBtn");
        N.show(closeBtn, true);
        N.absolute(header, closeBtn);
        N.size(closeBtn, 32, 32);
        N.position(closeBtn, width - 44, 8);
        G.call("ui.UIElement", "set_onClick", closeBtn, [() -> hide()]);

        N.absolute(win, content);
        N.padding(content, 0);
        N.size(content, width - 2 * SIDE, height - HEADER - SIDE);
        N.position(content, SIDE, HEADER);
        var contentDom = G.field(content, "dom");
        var windowDom = dom;

        // ---- the two grids ----
        for (g in 0...2) {
            var x = g * (gridW + GAP);
            var caption = N.label(windowDom, Locale.f(g == 0 ? "gather" : "hunt"), "farmerCaption" + g);
            place(caption, content, x + 4, 0);
            buildGrid(windowDom, content, g == 1, g == 0 ? Catalog.gather : Catalog.hunt, x, 26, gridW, gridH);
        }

        // ---- options ----
        var oy = 26 + gridH + 12;
        recycleBox = checkBox(windowDom, content, Locale.f("recycle"), "farmerRecycle", 0, oy, plan.recycle, (v) -> { plan.recycle = v; changed(); });
        qualityBoxes = [];
        var qx = 330;
        for (i in 0...4) {
            var box = checkBox(windowDom, content, Locale.f(Quality.NAMES[i]), "farmerQuality" + i, qx, oy, plan.recycleQualities[i], (v) -> { plan.recycleQualities[i] = v; changed(); });
            qualityBoxes.push(box);
            qx += 150;
        }
        clearBox = checkBox(windowDom, content, Locale.f("clear"), "farmerClear", 0, oy + 34, plan.clearBag, (v) -> { plan.clearBag = v; changed(); });
        gearBox = checkBox(windowDom, content, Locale.f("bestGear"), "farmerBestGear", 330, oy + 34, plan.replaceGear, (v) -> { plan.replaceGear = v; changed(); });
        var levelCaption = N.label(windowDom, Locale.f("leveling") + ":  " + Locale.f("level"), "farmerLevelText");
        place(levelCaption, content, 0, oy + 72);
        levelInput = N.node("input-box", windowDom, [], "farmerLevel");
        levelInput = G.field(levelInput, "obj");
        place(levelInput, content, 330, oy + 66, 90, 34);
        var fieldInput = G.field(levelInput, "input");
        levelLast = plan.targetLevel > 0 ? Std.string(plan.targetLevel) : "";
        G.call("h2d.TextInput", "set_text", fieldInput, [levelLast]);

        actionButton = N.button(windowDom, Locale.f(running ? "stop" : "start"), "farmerAction", () -> { if (running) { if (onStop != null) onStop(); } else if (onStart != null) onStart(); });
        place(actionButton, content, width - 2 * SIDE - 170, oy + 60, 170, 44);
        statusLabel = N.label(windowDom, "", "farmerStatus");
        place(statusLabel, content, 0, oy + 110);

        N.position(win, Math.max(0, (sceneW - width) / 2), Math.max(0, (sceneH - height) / 2));
    }

    function changed():Void if (onChanged != null) onChanged();

    function checkBox(dom:Dynamic, content:Dynamic, text:String, id:String, x:Float, y:Float, value:Bool, onChange:Bool -> Void):Dynamic {
        var box = G.field(N.node("check-box", dom, [N.escape(text)], id), "obj");
        place(box, content, x, y);
        // (the game's setter, not the bare field: it toggles the "selected" class that draws the tick; the field alone left a saved box looking empty)
        G.call("ui.UIElement", "set_selected", box, [value]);
        G.set(box, "onValueChange", onChange);
        return box;
    }

    function buildGrid(dom:Dynamic, content:Dynamic, hunting:Bool, list:Array<Res>, x:Float, y:Float, w:Int, h:Int):Void {
        var grid = G.field(N.node("flow", dom, [], "farmerGrid" + (hunting ? "H" : "G"), "horizontal"), "obj");
        place(grid, content, x, y, w, h);
        N.padding(grid, 0);
        G.call("h2d.Flow", "set_multiline", grid, [true]);
        N.style(grid, "multiline", true);
        var top = G.current("h2d.FlowAlign", "Top");
        G.call("h2d.Flow", "set_verticalAlign", grid, [top]);
        N.style(grid, "content-valign", top);
        var scroll = G.current("h2d.FlowOverflow", "Scroll");
        G.call("h2d.Flow", "set_overflow", grid, [scroll]);
        N.style(grid, "overflow", scroll);
        var scrollBar = G.field(grid, "scrollBar");
        var cursor = G.field(grid, "scrollBarCursor");
        if (scrollBar != null) {
            N.size(scrollBar, BAR - 12);
            G.call("h2d.Flow", "set_backgroundTile", scrollBar, [G.staticCall("h2d.Tile", "fromColor", [0x5B4334, 1, 1, 0.35, null])]);
        }
        if (cursor != null) {
            N.size(cursor, BAR - 12);
            G.call("h2d.Flow", "set_backgroundTile", cursor, [G.staticCall("h2d.Tile", "fromColor", [0x8A5F46, 1, 1, 1.0, null])]);
        }
        var gridDom = G.field(grid, "dom");
        var index = 0;
        for (res in list) {
            try buildCell(gridDom, grid, hunting, res, index++) catch (error:Dynamic) Log.t("err", "cell " + res.id + ": " + Std.string(error));
        }
    }

    function buildCell(gridDom:Dynamic, grid:Dynamic, hunting:Bool, res:Res, index:Int):Void {
        var cell = G.field(N.node("flow", gridDom, [], "farmerCell" + (hunting ? "H" : "G") + index, "vertical"), "obj");
        N.inFlow(grid, cell);
        N.padding(cell, 0);
        N.size(cell, cellW, cellH);
        var button = makeItemButton(res.item, cell);
        N.show(G.field(button, "progressTexts"), false);
        var c = new Cell(res, hunting);
        c.button = button;
        // gold frame around the icon
        var frame = G.create("h2d.Graphics", [cell]);
        N.absolute(cell, frame);
        var bw = ICON;
        G.call("h2d.Graphics", "beginFill", frame, [0xFFC93C, 1.0]);
        G.call("h2d.Graphics", "drawRect", frame, [0, 0, bw, 3]);
        G.call("h2d.Graphics", "drawRect", frame, [0, bw - 3, bw, 3]);
        G.call("h2d.Graphics", "drawRect", frame, [0, 0, 3, bw]);
        G.call("h2d.Graphics", "drawRect", frame, [bw - 3, 0, 3, bw]);
        G.call("h2d.Graphics", "endFill", frame);
        N.show(frame, plan.isPicked(hunting, res.id));
        c.frame = frame;
        // amount still to get: the game's own input box (dark field, its own font, focus by a click), under the icon
        var box = G.field(N.node("input-box", G.field(cell, "dom"), [], "farmerAmount" + (hunting ? "H" : "G") + index), "obj");
        N.absolute(cell, box);
        N.size(box, Std.int(Math.max(cellW - 2, ICON - 2)), 30);
        N.position(box, 1, ICON + 4);
        var input = G.field(box, "input");
        G.call("h2d.TextInput", "set_text", input, [Std.string(plan.count(hunting, res.id))]);
        N.show(box, plan.isPicked(hunting, res.id));
        c.box = box;
        c.input = input;
        c.shown = plan.isPicked(hunting, res.id);
        c.lastText = Std.string(plan.count(hunting, res.id));
        cells.push(c);
        var toggle = function() {
            plan.toggle(hunting, res.id);
            changed();
        };
        G.set(button, "onButtonClicked", (_:Dynamic) -> toggle());
        for (target in [button, G.field(button, "button")]) {
            if (target != null) try G.call("ui.UIElement", "set_onClick", target, [toggle]) catch (_:Dynamic) {}
        }
    }

    /** The game's own item button with its tooltip (what the Codex shows for an item). */
    function makeItemButton(item:Dynamic, parent:Dynamic):Dynamic {
        var node = G.create("data.CodexNode", []);
        G.set(node, "name", G.s(G.field(item, "id")));
        G.set(node, "data", item);
        G.set(node, "_icon", G.field(item, "gfx"));
        G.set(node, "clickable", true);
        G.set(node, "forcedRevealed", true);
        try G.set(node, "progressThresholds", G.staticCall("st.player.Progress", "getItemProgressThreshold", [item])) catch (_:Dynamic) {}
        G.set(node, "getTooltip", function():Dynamic return G.staticCall("ui.Tooltip", "fromItem", [item, null]));
        var button = G.create("ui.win.codex.CodexButton", [node, parent]);
        var dom = G.field(button, "dom");
        try G.call("domkit.Properties", "addClass", dom, ["small"]) catch (_:Dynamic) {}
        return button;
    }
}

private class Cell {
    public var res:Res;
    public var hunting:Bool;
    public var button:Dynamic;
    public var frame:Dynamic;
    public var input:Dynamic;
    public var box:Dynamic;
    public var shown = false;
    public var lastText = "";

    public function new(res:Res, hunting:Bool) {
        this.res = res;
        this.hunting = hunting;
    }
}
