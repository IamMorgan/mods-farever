package dpf;

import dpf.DungeonList.DungeonInfo;
import dpf.GameAccess as G;

/**
 * The list of dungeons (name and level), in the look of the game's dialogs. A click on a row picks the dungeon; the
 * mouse wheel and the arrows scroll when the list is longer than the screen.
 */
class DungeonListWindow {
    static inline var WIDTH = 460.0;
    static inline var HEADER = 52.0;
    static inline var ROW_H = 50.0;
    static inline var ROW_GAP = 6.0;
    static inline var PAD = 22.0;
    static inline var MAX_ROWS = 10;

    public var russian = false;

    var ui:UiKit;
    var scene:Dynamic;
    var root:Dynamic;
    var wheel:Dynamic;
    var entries:Array<DungeonInfo> = [];
    var heroLevel = 0;
    var active = "";
    var onPick:DungeonInfo -> Void;
    var onClose:Void -> Void;
    var first = 0;
    var perPage = MAX_ROWS;
    var open = false;

    public function new(ui:UiKit) {
        this.ui = ui;
        wheel = (e:Dynamic) -> {
            var delta = G.number(G.field(e, "wheelDelta"));
            if (delta != 0) scrollBy(delta > 0 ? 1 : -1);
        };
    }

    public function isOpen():Bool return open;

    public function hide():Void {
        open = false;
        ui.remove(root);
        root = null;
    }

    /** `active` is the id of the dungeon that is being searched, shown marked. */
    public function show(scene:Dynamic, entries:Array<DungeonInfo>, heroLevel:Int, active:String, onPick:DungeonInfo -> Void):Void {
        hide();
        if (scene == null) return;
        this.scene = scene;
        this.entries = entries;
        this.heroLevel = heroLevel;
        this.active = active;
        this.onPick = onPick;
        first = 0;
        open = true;
        try rebuild() catch (error:Dynamic) { trace("[DPF] list failed: " + Std.string(error)); hide(); }
    }

    /** Every frame while open: the window goes away with the game's UI. */
    public function update():Void {
        if (open && (root == null || G.field(root, "allocated") != true)) hide();
    }

    function scrollBy(rows:Int):Void {
        var max = Std.int(Math.max(0, entries.length - perPage));
        var target = Std.int(Math.max(0, Math.min(max, first + rows)));
        if (target == first) return;
        first = target;
        try rebuild() catch (_:Dynamic) {}
    }

    function rebuild():Void {
        ui.remove(root);
        ui.prepare(scene);
        var sceneW = G.number(G.field(scene, "width"), 1920), sceneH = G.number(G.field(scene, "height"), 1080);
        var chrome = HEADER + 40 + 44;
        perPage = Std.int(Math.max(3, Math.min(MAX_ROWS, Math.floor((sceneH - 40 - chrome) / (ROW_H + ROW_GAP)))));
        var count = entries.length;
        first = Std.int(Math.max(0, Math.min(first, Math.max(0, count - perPage))));
        var shown = Std.int(Math.max(0, Math.min(perPage, count - first)));
        var body = count == 0 ? 40.0 : shown * (ROW_H + ROW_GAP) - ROW_GAP;
        var footer = count > perPage ? 44.0 : 14.0;
        var height = HEADER + 40 + body + footer + 14;
        var scale = Math.min(1.0, Math.min((sceneH - 20) / height, (sceneW - 20) / WIDTH));

        root = G.create("h2d.Object", [scene]); // last child of the scene: drawn on top of everything
        G.call("h2d.Object", "setScale", root, [scale]);
        G.call("h2d.Object", "setPosition", root, [Math.round((sceneW - WIDTH * scale) / 2), Math.round((sceneH - height * scale) / 2)]);

        var g = ui.shapes(root);
        Style.frame(ui, g, WIDTH, height, HEADER);
        var blocker = ui.area(root, 0, 0, WIDTH, height);
        G.set(blocker, "onWheel", wheel);
        ui.centered(root, Locale.listTitle(russian), Style.TITLE, WIDTH / 2, 14, 24);
        closeButton(WIDTH - 30, HEADER / 2 + 1);
        ui.centered(root, Locale.listHint(russian), Style.DIM, WIDTH / 2, HEADER + 11, 17);

        var top = HEADER + 40;
        if (count == 0) ui.centered(root, Locale.listEmpty(russian), Style.DIM, WIDTH / 2, top + 8, 20);
        for (i in 0...shown) {
            var entry = entries[first + i];
            var y = top + i * (ROW_H + ROW_GAP);
            row(entry, PAD, y, WIDTH - PAD * 2, ROW_H);
        }
        if (count > perPage) {
            var y = top + body + 8;
            arrow(WIDTH / 2 - 62, y, true);
            arrow(WIDTH / 2 + 34, y, false);
            ui.centered(root, Locale.page(russian, first + 1, first + shown, count), Style.DIM, WIDTH / 2, y + 6, 17);
        }
    }

    function closeButton(cx:Float, cy:Float):Void {
        var g = ui.shapes(root);
        Style.cross(ui, g, cx, cy, 8, Style.CLOSE);
        var hover = ui.shapes(root);
        Style.cross(ui, hover, cx, cy, 8, Style.CLOSE_HOVER);
        ui.visible(hover, false);
        var hit = ui.area(root, cx - 16, cy - 16, 32, 32);
        ui.handCursor(hit);
        G.set(hit, "onOver", (_:Dynamic) -> ui.visible(hover, true));
        G.set(hit, "onOut", (_:Dynamic) -> ui.visible(hover, false));
        G.set(hit, "onClick", (_:Dynamic) -> close());
    }

    function close():Void {
        hide();
        if (onClose != null) onClose();
    }

    public function whenClosed(handler:Void -> Void):Void onClose = handler;

    function arrow(x:Float, y:Float, up:Bool):Void {
        var g = ui.shapes(root);
        var cx = x + 14, cy = y + 14;
        ui.framed(g, x, y, 28, 28, 5, Style.BUTTON, Style.LINE, 1.5);
        ui.poly(g, up ? [cx - 7, cy + 4, cx + 7, cy + 4, cx, cy - 5] : [cx - 7, cy - 4, cx + 7, cy - 4, cx, cy + 5], Style.BUTTON_TEXT);
        var hit = ui.area(root, x, y, 28, 28);
        ui.handCursor(hit);
        G.set(hit, "onWheel", wheel);
        G.set(hit, "onClick", (_:Dynamic) -> scrollBy(up ? -1 : 1));
    }

    function row(entry:DungeonInfo, x:Float, y:Float, w:Float, h:Float):Void {
        var g = ui.shapes(root);
        var chosen = entry.id == active;
        ui.framed(g, x, y, w, h, 7, chosen ? Style.ROW_HOVER : Style.ROW, chosen ? Style.STRIPE : Style.CARD_LINE, chosen ? 2.5 : 1.5);
        var hover = ui.shapes(root);
        ui.framed(hover, x, y, w, h, 7, Style.ROW_HOVER, Style.LINE, 2);
        ui.visible(hover, false);
        var capable = entry.level <= heroLevel;
        ui.text(root, entry.name, capable ? Style.DARK : Style.DIM, x + 16, y + 12, 23, w - 120);
        // the level pill
        var pillW = 78.0, pillH = 28.0, px = x + w - pillW - 12, py = y + (h - pillH) / 2;
        var pill = ui.shapes(root);
        ui.framed(pill, px, py, pillW, pillH, 6, capable ? 0xC9D6A6 : 0xD9BDB5, capable ? 0x8FA06A : Style.CARD_LINE, 1.5);
        ui.centered(root, Locale.level(russian, entry.level), capable ? Style.DARK : Style.DIM, px + pillW / 2, py + 4, 19);
        var hit = ui.area(root, x, y, w, h);
        ui.handCursor(hit);
        G.set(hit, "onWheel", wheel);
        G.set(hit, "onOver", (_:Dynamic) -> ui.visible(hover, true));
        G.set(hit, "onOut", (_:Dynamic) -> ui.visible(hover, false));
        G.set(hit, "onClick", (_:Dynamic) -> { var pick = onPick; if (pick != null) pick(entry); });
    }
}
