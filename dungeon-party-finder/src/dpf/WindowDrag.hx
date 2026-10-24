package dpf;

import dpf.GameAccess as G;
import dpf.NativeUi as N;

/**
 * Lets the player move the game's dungeon window by its title strip (the game's own window is fixed in the middle of the
 * screen). A transparent hit area over the strip, short of the close button, picks the window up; while the mouse button is
 * held the window follows the mouse. The window is taken out of its parent's layout on the first move so the parent does not
 * put it back.
 */
class WindowDrag {
    static inline var STRIP = 46.0;
    static inline var CLOSE_WIDTH = 64.0;

    var bound:Dynamic;
    var hit:Dynamic;
    var dragging = false;
    var startMouseX = 0.0;
    var startMouseY = 0.0;
    var startX = 0.0;
    var startY = 0.0;

    public function new() {}

    /** Every frame the game updates the dungeon window `screen`. */
    public function update(screen:Dynamic):Void {
        // The window is not in the scene yet during its first frames.
        if (G.field(screen, "parent") == null) return;
        if (bound != screen || (hit != null && G.field(hit, "parent") == null)) bind(screen);
        if (dragging) poll(screen);
    }

    function bind(screen:Dynamic):Void {
        bound = screen;
        hit = null;
        dragging = false;
        var width = G.number(G.call("h2d.Flow", "get_outerWidth", screen));
        hit = G.create("h2d.Interactive", [Math.max(40, width - CLOSE_WIDTH), STRIP, screen, null]);
        N.absolute(screen, hit);
        G.call("h2d.Object", "setPosition", hit, [0, 0]);
        G.set(hit, "onPush", (_:Dynamic) -> begin(screen));
    }

    function mouse(screen:Dynamic):Null<{x:Float, y:Float}> {
        var parent = G.field(screen, "parent");
        var scene = G.call("h2d.Object", "getScene", screen);
        if (parent == null || scene == null) return null;
        var point = G.allocRaw("h2d.col.PointImpl");
        G.set(point, "x", G.number(G.call("h2d.Scene", "get_mouseX", scene)));
        G.set(point, "y", G.number(G.call("h2d.Scene", "get_mouseY", scene)));
        var local = G.call("h2d.Object", "globalToLocal", parent, [point]);
        return {x: G.number(G.field(local, "x")), y: G.number(G.field(local, "y"))};
    }

    function begin(screen:Dynamic):Void {
        try {
            var m = mouse(screen);
            if (m == null) return;
            startMouseX = m.x;
            startMouseY = m.y;
            startX = G.number(G.field(screen, "x"));
            startY = G.number(G.field(screen, "y"));
            var parent = G.field(screen, "parent");
            if (G.isA(parent, "h2d.Flow")) {
                var p = G.call("h2d.Flow", "getProperties", parent, [screen]);
                G.call("h2d.FlowProperties", "set_isAbsolute", p, [true]);
            }
            G.call("h2d.Object", "setPosition", screen, [startX, startY]);
            dragging = true;
        } catch (error:Dynamic) trace("[DPF] window drag failed: " + Std.string(error));
    }

    function poll(screen:Dynamic):Void {
        try {
            if (G.staticCall("hxd.Key", "isDown", [0]) != true) { dragging = false; return; }
            var m = mouse(screen);
            if (m == null) return;
            G.call("h2d.Object", "setPosition", screen, [startX + m.x - startMouseX, startY + m.y - startMouseY]);
        } catch (error:Dynamic) { dragging = false; trace("[DPF] window drag failed: " + Std.string(error)); }
    }
}
