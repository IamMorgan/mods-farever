package dpf;

import dpf.GameAccess as G;
import dpf.NativeUi as N;

/**
 * Lets the player move the game's dungeon window by its title strip (the game's own window is fixed in its place on the
 * screen). A transparent hit area over the strip, short of the close button, picks the window up; while the mouse button is
 * held the window follows the mouse. The window is moved the way its parent's layout does it, by the offset of the window in
 * the parent's flow (also kept in the window's style, which the game applies again whenever a control is hovered): setting the
 * window's position directly is undone by the layout and breaks the clipping of the dungeon's picture.
 */
class WindowDrag {
    static inline var STRIP = 46.0;
    static inline var CLOSE_WIDTH = 90.0;

    var bound:Dynamic;
    var hit:Dynamic;
    var hitWidth = 0.0;
    var dragging = false;
    var startMouseX = 0.0;
    var startMouseY = 0.0;
    var startOffsetX = 0.0;
    var startOffsetY = 0.0;
    /** Where the player left the window (an offset from its usual place); the next window gets it too. */
    var moved = false;
    var offsetX = 0.0;
    var offsetY = 0.0;

    public function new() {}

    /** Every frame the game updates the dungeon window `screen`. */
    public function update(screen:Dynamic):Void {
        // The window is not in the scene yet during its first frames.
        if (G.field(screen, "parent") == null) return;
        if (bound != screen || (hit != null && G.field(hit, "parent") == null)) bind(screen);
        if (dragging) poll(screen);
        else if (moved) apply(screen, offsetX, offsetY);
        // The strip never reaches the close button, whatever the window's width is by now.
        var width = Math.max(40, G.number(G.field(screen, "calculatedWidth")) - CLOSE_WIDTH);
        if (width != hitWidth) { hitWidth = width; G.set(hit, "width", width); }
    }

    function bind(screen:Dynamic):Void {
        bound = screen;
        dragging = false;
        hitWidth = Math.max(40, G.number(G.field(screen, "calculatedWidth")) - CLOSE_WIDTH);
        hit = G.create("h2d.Interactive", [hitWidth, STRIP, screen, null]);
        N.absolute(screen, hit);
        G.call("h2d.Object", "setPosition", hit, [0, 0]);
        G.set(hit, "onPush", (_:Dynamic) -> begin(screen));
        // The mouse button is read from the release events: the key state of the button is not reliable here.
        G.set(hit, "onRelease", (_:Dynamic) -> dragging = false);
        G.set(hit, "onReleaseOutside", (_:Dynamic) -> dragging = false);
    }

    function properties(screen:Dynamic):Dynamic {
        var parent = G.field(screen, "parent");
        return parent != null && G.isA(parent, "h2d.Flow") ? G.call("h2d.Flow", "getProperties", parent, [screen]) : null;
    }

    /** Puts the window's offset in its parent's layout (and in its style) at (x, y), when it is not there yet. */
    function apply(screen:Dynamic, x:Float, y:Float):Void {
        var p = properties(screen);
        if (p == null) return;
        if (G.number(G.field(p, "offsetX")) == x && G.number(G.field(p, "offsetY")) == y) return;
        G.set(p, "offsetX", x);
        G.set(p, "offsetY", y);
        N.style(screen, "offset-x", x);
        N.style(screen, "offset-y", y);
        G.set(G.field(screen, "parent"), "needReflow", true);
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
            var p = properties(screen);
            if (m == null || p == null) return;
            startMouseX = m.x;
            startMouseY = m.y;
            startOffsetX = G.number(G.field(p, "offsetX"));
            startOffsetY = G.number(G.field(p, "offsetY"));
            dragging = true;
        } catch (error:Dynamic) trace("[DPF] window drag failed: " + Std.string(error));
    }

    function poll(screen:Dynamic):Void {
        try {
            var m = mouse(screen);
            if (m == null) return;
            // A plain click on the strip does not move anything.
            if (!moved && Math.abs(m.x - startMouseX) + Math.abs(m.y - startMouseY) < 4) return;
            moved = true;
            offsetX = startOffsetX + m.x - startMouseX;
            offsetY = startOffsetY + m.y - startMouseY;
            apply(screen, offsetX, offsetY);
        } catch (error:Dynamic) { dragging = false; trace("[DPF] window drag failed: " + Std.string(error)); }
    }
}
