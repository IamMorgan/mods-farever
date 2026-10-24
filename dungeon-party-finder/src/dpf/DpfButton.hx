package dpf;

import dpf.GameAccess as G;

/**
 * The "DPF" button on the game's screen: a small plate in the look of the game's windows. A click opens the list of dungeons.
 * While the settings say it is unpinned, a press on the button picks it up (hold the left mouse button and move) instead;
 * a press that does not move still counts as a click. A dot on its corner tells what the finder is doing: orange and
 * pulsing while searching, green once a group is formed.
 *
 * It is attached the way the other mods' panels are (a child of the game's UI root, above the HUD and below the windows)
 * and moved by polling the mouse every frame, the two ways that are proven to work in this game's UI.
 */
class DpfButton {
    public static inline var W = 74.0;
    public static inline var H = 36.0;
    static inline var CLICK_SLOP = 4.0;

    public var x = 12.0;
    public var y = 320.0;
    /** Set once when a drag ends; the mod saves the position and clears it. */
    public var dragEnded = false;
    public var onClick:Void -> Void;

    var ui:UiKit;
    var root:Dynamic;
    var hover:Dynamic;
    var dotSearching:Dynamic;
    var dotParty:Dynamic;
    var builtScale = -1.0;
    var unpinned = false;
    var dragging = false;
    var moved = false;
    var startMouseX = 0.0;
    var startMouseY = 0.0;
    var startX = 0.0;
    var startY = 0.0;

    public function new(ui:UiKit) this.ui = ui;

    public function hide():Void {
        finishDrag(false);
        ui.remove(root);
        root = null;
        builtScale = -1;
    }

    /** `status`: 0 nothing, 1 searching, 2 in a group. Called every frame while the hero is in the world. */
    public function update(visible:Bool, scale:Float, unpinned:Bool, status:Int, now:Float):Void {
        this.unpinned = unpinned;
        if (!visible) { if (root != null) hide(); return; }
        var gameUi = G.current("ui.BaseUI", "current");
        if (gameUi == null || G.field(gameUi, "gameRoot") == null) return;
        if (root == null || G.field(root, "allocated") != true || builtScale != scale) {
            if (root != null) hide();
            build(gameUi, scale);
            builtScale = scale;
        }
        if (root == null) return;
        if (dragging) pollDrag(gameUi);
        clamp(gameUi, scale);
        G.call("h2d.Object", "setPosition", root, [x, y]);
        ui.visible(dotSearching, status == 1);
        ui.visible(dotParty, status == 2);
        if (status == 1) G.set(dotSearching, "alpha", 0.6 + 0.4 * Math.sin(now * 6));
    }

    function clamp(gameUi:Dynamic, scale:Float):Void {
        var scene = G.field(gameUi, "s2d");
        if (scene == null) return;
        var sw = G.number(G.field(scene, "width"), 1920), sh = G.number(G.field(scene, "height"), 1080);
        x = Math.max(0, Math.min(x, sw - W * scale));
        y = Math.max(0, Math.min(y, sh - H * scale));
    }

    /** Lets the button sit anywhere in ui.root (a Flow) without being laid out by it. */
    function detachFromFlow(parent:Dynamic, child:Dynamic):Void {
        var properties = G.call("h2d.Flow", "getProperties", parent, [child]);
        G.call("h2d.FlowProperties", "set_isAbsolute", properties, [true]);
        G.set(properties, "horizontalAlign", null);
        G.set(properties, "verticalAlign", null);
        G.set(properties, "offsetX", 0);
        G.set(properties, "offsetY", 0);
    }

    function build(gameUi:Dynamic, scale:Float):Void {
        var gameRoot = G.field(gameUi, "gameRoot");
        var uiRoot = G.field(gameUi, "root"); // an h2d.Flow
        var scene = G.field(gameUi, "s2d");
        if (gameRoot == null || uiRoot == null || scene == null) return;
        try {
            ui.prepare(scene);
            root = G.create("h2d.Object", [null]);
            var index = G.integer(G.call("h2d.Object", "getChildIndex", uiRoot, [gameRoot]));
            G.call("h2d.Flow", "addChildAt", uiRoot, [root, index]);
            detachFromFlow(uiRoot, root);
            G.call("h2d.Object", "setScale", root, [scale]);
            G.call("h2d.Object", "setPosition", root, [x, y]);

            var g = ui.shapes(root);
            ui.plate(g, 2, 3.5, W, H, 7, 0x000000, 0.35);
            ui.framed(g, 0, 0, W, H, 7, Style.BODY, Style.LINE, 2);
            ui.plate(g, 3, 3, W - 6, H / 2 - 2, 5, Style.HEADER, 0.95);
            ui.rect(g, 4, H - 7, W - 8, 2, Style.BAND, 0.9);
            for (px in [7.0, W - 7]) {
                ui.circle(g, px, H / 2, 2.6, Style.RIVET, 1, 8);
                ui.circle(g, px - 0.6, H / 2 - 0.6, 1.2, Style.RIVET_LIGHT, 1, 6);
            }
            ui.centered(root, "DPF", Style.BUTTON_TEXT, W / 2 + 1, 6.5, 22);
            ui.centered(root, "DPF", Style.TITLE, W / 2, 5.5, 22);

            hover = ui.shapes(root);
            ui.plate(hover, 1.5, 1.5, W - 3, H - 3, 6, 0xFFFFFF, 0.28);
            ui.visible(hover, false);

            dotSearching = ui.shapes(root);
            ui.circle(dotSearching, W - 3, 3, 6.5, Style.LINE, 1, 12);
            ui.circle(dotSearching, W - 3, 3, 4.8, 0xF29A2E, 1, 12);
            dotParty = ui.shapes(root);
            ui.circle(dotParty, W - 3, 3, 6.5, Style.LINE, 1, 12);
            ui.circle(dotParty, W - 3, 3, 4.8, 0x5DBB4B, 1, 12);
            ui.visible(dotSearching, false);
            ui.visible(dotParty, false);

            var hit = ui.area(root, 0, 0, W, H);
            G.call("h2d.Interactive", "set_cursor", hit, [G.current("hxd.Cursor", "Button")]);
            G.set(hit, "onOver", (_:Dynamic) -> ui.visible(hover, true));
            G.set(hit, "onOut", (_:Dynamic) -> ui.visible(hover, false));
            G.set(hit, "onPush", (_:Dynamic) -> if (unpinned) beginDrag());
            G.set(hit, "onClick", (_:Dynamic) -> if (!unpinned && onClick != null) onClick());
        } catch (error:Dynamic) {
            trace("[DPF] button build failed: " + Std.string(error));
            if (root != null) ui.remove(root);
            root = null;
        }
    }

    // ---- moving it ----

    /** The mouse in the coordinates of the game's UI root (which never moves). */
    function localMouse(gameUi:Dynamic):Null<{x:Float, y:Float}> {
        try {
            var uiRoot = G.field(gameUi, "root"), scene = G.field(gameUi, "s2d");
            if (uiRoot == null || scene == null) return null;
            var point = G.allocRaw("h2d.col.PointImpl");
            G.set(point, "x", G.number(G.call("h2d.Scene", "get_mouseX", scene)));
            G.set(point, "y", G.number(G.call("h2d.Scene", "get_mouseY", scene)));
            var local = G.call("h2d.Object", "globalToLocal", uiRoot, [point]);
            return {x: G.number(G.field(local, "x")), y: G.number(G.field(local, "y"))};
        } catch (_:Dynamic) {
            return null;
        }
    }

    function beginDrag():Void {
        var gameUi = G.current("ui.BaseUI", "current");
        if (gameUi == null) return;
        var m = localMouse(gameUi);
        if (m == null) return;
        startMouseX = m.x;
        startMouseY = m.y;
        startX = x;
        startY = y;
        moved = false;
        dragging = true;
    }

    function pollDrag(gameUi:Dynamic):Void {
        try {
            if (!unpinned || G.staticCall("hxd.Key", "isDown", [0]) != true) { finishDrag(true); return; }
            var m = localMouse(gameUi);
            if (m == null) return;
            var dx = m.x - startMouseX, dy = m.y - startMouseY;
            if (!moved && Math.abs(dx) + Math.abs(dy) < CLICK_SLOP) return;
            moved = true;
            x = startX + dx;
            y = startY + dy;
        } catch (_:Dynamic) finishDrag(false);
    }

    function finishDrag(release:Bool):Void {
        if (!dragging) return;
        dragging = false;
        if (!release) return;
        if (moved) dragEnded = true;
        else if (onClick != null) onClick();
    }
}
