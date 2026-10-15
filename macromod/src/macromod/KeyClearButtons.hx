package macromod;

import macromod.KeyRowScanner.RowDecorator;

/**
 * A small red X to the right of a key button. The key button moves 20 px to the left (a layout offset, so
 * the row itself is not resized) and the X, 15 x 15 px, sits where the key button used to end.
 */
class KeyClearButtons implements RowDecorator {
    public static inline var SIZE = 15.0;
    public static inline var SHIFT = 20;

    var onClear:(key:String, button:Dynamic) -> Void;
    var flowType:hl.Bytes;
    var alignType:hl.Bytes;
    var getProperties:hlx.runtime.ResolvedMember;
    var reflow:hlx.runtime.ResolvedMember;

    public function new(onClear:(key:String, button:Dynamic) -> Void) this.onClear = onClear;

    static function field(object:Dynamic, name:String):Dynamic {
        if (object == null) return null;
        try return HlxRuntime.resolveField(object, name) catch (_:Dynamic) return null;
    }

    public function isAlive(added:Dynamic):Bool return field(added, "allocated") == true;

    function prepare():Bool {
        if (flowType == null) flowType = HlxRuntime.resolveType("h2d.Flow");
        if (alignType == null) alignType = HlxRuntime.resolveType("h2d.FlowAlign");
        if (flowType == null || alignType == null) return false;
        if (getProperties == null) getProperties = HlxRuntime.resolveMember(flowType, "getProperties");
        if (reflow == null) reflow = HlxRuntime.resolveMember(flowType, "reflow");
        return getProperties != null;
    }

    static function polygon(g:Dynamic, color:Int, points:Array<Float>):Void {
        HlxRuntime.callResolved(HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Graphics"), "beginFill"), [g, color, 1.0]);
        var move = HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Graphics"), "moveTo");
        var line = HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Graphics"), "lineTo");
        HlxRuntime.callResolved(move, [g, points[0], points[1]]);
        var i = 2;
        while (i < points.length) { HlxRuntime.callResolved(line, [g, points[i], points[i + 1]]); i += 2; }
        HlxRuntime.callResolved(line, [g, points[0], points[1]]);
        HlxRuntime.callResolved(HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Graphics"), "endFill"), [g]);
    }

    /** The red square with a light X. Drawn with h2d.Graphics; if that isn't possible, the
        click area's own background colour and a text "X" stand in for it. */
    static function drawCross(added:Dynamic, click:Dynamic):Void {
        try {
            var g = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Graphics"), 1, [added]);
            polygon(g, 0xDA594F, [0.0, 0.0, SIZE, 0.0, SIZE, SIZE, 0.0, SIZE]);
            polygon(g, 0xF7E4DA, [3.0, 4.5, 4.5, 3.0, 12.0, 10.5, 10.5, 12.0]); // one diagonal
            polygon(g, 0xF7E4DA, [10.5, 3.0, 12.0, 4.5, 4.5, 12.0, 3.0, 10.5]); // the other
            return;
        } catch (_:Dynamic) {}
        HlxRuntime.setField(click, "backgroundColor", 0xFFDA594F);
        try {
            var font = GameAccess.staticCall("hxd.res.DefaultFont", "get", []);
            var text = GameAccess.create("h2d.Text", [font, added]);
            GameAccess.call("h2d.Text", "set_text", text, ["X"]);
            GameAccess.call("h2d.Text", "set_textColor", text, [0xF7E4DA]);
            var w = GameAccess.number(GameAccess.call("h2d.Text", "get_textWidth", text), 6);
            GameAccess.call("h2d.Object", "setPosition", text, [(SIZE - w) / 2, 1.0]);
        } catch (_:Dynamic) {}
    }

    public function decorate(key:String, button:Dynamic):Dynamic {
        var added:Dynamic = null;
        try {
            if (!prepare()) return null;
            var flow = field(button, "parent");
            if (flow == null) return null;
            var right = HlxRuntime.constructEnum(alignType, "Right", []);
            var middle = HlxRuntime.constructEnum(alignType, "Middle", []);

            // 1. The key button moves left. If this fails nothing has been added yet.
            var buttonProperties = HlxRuntime.callResolved(getProperties, [flow, button]);
            if (buttonProperties == null) return null;
            HlxRuntime.setField(buttonProperties, "offsetX", -SHIFT);

            // 2. The X: a flow child that is excluded from the layout and pinned to the right edge.
            added = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Object"), 1, [flow]);
            var addedProperties = HlxRuntime.callResolved(getProperties, [flow, added]);
            HlxRuntime.setField(addedProperties, "isAbsolute", true);
            HlxRuntime.setField(addedProperties, "horizontalAlign", right);
            HlxRuntime.setField(addedProperties, "verticalAlign", middle);

            var click = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("h2d.Interactive"), 4, [SIZE, SIZE, added, null]);
            HlxRuntime.setField(click, "onClick", (_:Dynamic) -> onClear(key, button));
            try HlxRuntime.callResolved(HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Interactive"), "set_cursor"),
                [click, GameAccess.current("hxd.Cursor", "Button")]) catch (_:Dynamic) {}
            drawCross(added, click);
            if (reflow != null) HlxRuntime.callResolved(reflow, [flow]);
            return added;
        } catch (_:Dynamic) {
            // Never leave a half-built X behind.
            try if (added != null) HlxRuntime.callResolved(HlxRuntime.resolveMember(HlxRuntime.resolveType("h2d.Object"), "remove"), [added]) catch (_:Dynamic) {}
            return null;
        }
    }
}
