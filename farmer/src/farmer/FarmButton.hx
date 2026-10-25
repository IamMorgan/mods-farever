package farmer;

import farmer.GameAccess as G;
import farmer.NativeUi as N;

/**
 * The "Farm" button on the game's screen: one of the game's own buttons (the kind the Esc menu has and the DPF button is),
 * made as a domkit "button" node. A click opens the window of the farm settings. A dot on its corner tells what the bot
 * is doing: orange and pulsing while it works, green once it is done and waits.
 * While the settings say it is unpinned, a press on the button picks it up (hold the left mouse button and move) instead; a press
 * that does not move still counts as a click.
 *
 * It is a child of the game's UI root, above the HUD and below the windows (as the DPF button is), and is moved by polling the
 * mouse every frame.
 */
class FarmButton {
    public static inline var W = 74.0;
    public static inline var H = 36.0;
    static inline var CLICK_SLOP = 4.0;

    public var x = 12.0;
    public var y = 364.0;
    /** Set once when a drag ends; the mod saves the position and clears it. */
    public var dragEnded = false;
    public var onClick:Void -> Void;

    var root:Dynamic;
    var hit:Dynamic;
    var dotWorking:Dynamic;
    var dotDone:Dynamic;
    var builtScale = -1.0;
    var builtLabel = "";
    var builtUnpinned = false;
    var unpinned = false;
    var dragging = false;
    var moved = false;
    var startMouseX = 0.0;
    var startMouseY = 0.0;
    var startX = 0.0;
    var startY = 0.0;

    public function new() {}

    public function hide():Void {
        finishDrag(false);
        if (root != null) try G.call("h2d.Object", "remove", root, []) catch (_:Dynamic) {}
        root = null;
        hit = null;
        builtScale = -1;
    }

    /** `status`: 0 nothing, 1 working, 2 done. Called every frame while the hero is in the world. */
    public function update(visible:Bool, scale:Float, label:String, status:Int, unpinned:Bool, now:Float):Void {
        this.unpinned = unpinned;
        if (!visible) { if (root != null) hide(); return; }
        var gameUi = G.current("ui.BaseUI", "current");
        if (gameUi == null || G.field(gameUi, "gameRoot") == null) return;
        if (root == null || G.field(root, "parent") == null || builtScale != scale || builtLabel != label || builtUnpinned != unpinned) {
            if (root != null) hide();
            build(gameUi, scale, label);
            builtScale = scale;
            builtLabel = label;
            builtUnpinned = unpinned;
        }
        if (root == null) return;
        if (dragging) pollDrag(gameUi);
        clamp(gameUi, scale);
        G.call("h2d.Object", "setPosition", root, [x, y]);
        N.show(dotWorking, status == 1);
        N.show(dotDone, status == 2);
        if (status == 1) G.set(dotWorking, "alpha", 0.6 + 0.4 * Math.sin(now * 6));
    }

    function clamp(gameUi:Dynamic, scale:Float):Void {
        var scene = G.field(gameUi, "s2d");
        if (scene == null) return;
        var sw = G.number(G.field(scene, "width"), 1920), sh = G.number(G.field(scene, "height"), 1080);
        x = Math.max(0, Math.min(x, sw - W * scale));
        y = Math.max(0, Math.min(y, sh - H * scale));
    }

    function build(gameUi:Dynamic, scale:Float, label:String):Void {
        var gameRoot = G.field(gameUi, "gameRoot");
        var uiRoot = G.field(gameUi, "root"); // an h2d.Flow
        if (gameRoot == null || uiRoot == null) return;
        try {
            var button = N.button(G.field(uiRoot, "dom"), label, "farmerButton", () -> if (!unpinned && onClick != null) onClick());
            root = button;
            // Below the windows, above the HUD.
            var index = G.integer(G.call("h2d.Object", "getChildIndex", uiRoot, [gameRoot]));
            G.call("h2d.Flow", "addChildAt", uiRoot, [button, index]);
            N.absolute(uiRoot, button);
            N.size(button, Std.int(W), Std.int(H));
            G.call("h2d.Object", "setScale", button, [scale]);
            G.call("h2d.Object", "setPosition", button, [x, y]);
            dotWorking = dot(button, 0xF29A2E);
            dotDone = dot(button, 0x5DBB4B);
            N.show(dotWorking, false);
            N.show(dotDone, false);

            if (unpinned) {
                // A press picks the button up; a press that does not move is still a click (see finishDrag).
                hit = G.create("h2d.Interactive", [W, H, button, null]);
                N.absolute(button, hit);
                G.call("h2d.Object", "setPosition", hit, [0, 0]);
                G.call("h2d.Interactive", "set_cursor", hit, [G.current("hxd.Cursor", "Button")]);
                G.set(hit, "onPush", (_:Dynamic) -> beginDrag());
            }
        } catch (error:Dynamic) {
            Log.t("err", "button build failed: " + Std.string(error));
            hide();
        }
    }

    /** A round marker on the button's top right corner. */
    function dot(button:Dynamic, color:Int):Dynamic {
        var g = G.create("h2d.Graphics", [button]);
        N.absolute(button, g);
        G.call("h2d.Graphics", "beginFill", g, [0x000000, 1.0]);
        G.call("h2d.Graphics", "drawCircle", g, [W - 3, 3, 6.5, 14]);
        G.call("h2d.Graphics", "endFill", g);
        G.call("h2d.Graphics", "beginFill", g, [color, 1.0]);
        G.call("h2d.Graphics", "drawCircle", g, [W - 3, 3, 4.8, 14]);
        G.call("h2d.Graphics", "endFill", g);
        return g;
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
