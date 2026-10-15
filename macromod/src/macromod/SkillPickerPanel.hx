package macromod;

import macromod.GameAccess as G;
import macromod.HotbarSkills.HotbarSkill;

/**
 * The skill picker: the action-bar skills as clickable icons, drawn straight onto the 2D scene
 * on top of everything (Better Mod Settings has no control for this). Weapon skills on the first
 * row, class skills on the second; hovering an icon shows the skill's name. Clicking outside
 * the panel, "Cancel" or Esc closes it.
 *
 * Only plain h2d objects are used, and backgrounds are h2d.Interactive.backgroundColor: no
 * h2d.Graphics, whose drawing methods take optional (by-reference) arguments.
 */
class SkillPickerPanel {
    static inline var CELL = 56.0;
    static inline var GAP = 6.0;
    static inline var PAD = 10.0;
    static inline var LINE = 18.0; // height of one text line, in scene pixels
    static inline var CELL_BG = 0xFF2E2626;
    static inline var CELL_HOVER = 0xFF6B5634;
    static inline var CANCEL_BG = 0xFF6A2A26;

    var root:Dynamic;
    var caption:Dynamic;
    var font:Dynamic;
    var fontScale = 1.0;
    var onPick:HotbarSkill -> Void;
    var open = false;

    public function new() {}

    public function isOpen():Bool return open;

    public function hide():Void {
        open = false;
        onPick = null;
        if (root != null) try G.call("h2d.Object", "remove", root, []) catch (_:Dynamic) {}
        root = null;
        caption = null;
    }

    /** Called every frame while open: Esc closes the picker. */
    public function update():Void {
        if (!open) return;
        if (root != null && G.field(root, "allocated") != true) { hide(); return; }
        try if (G.staticCall("hxd.Key", "isPressed", [27]) == true) hide() catch (_:Dynamic) {}
    }

    /** A font from the game's own texts, preferring one that is showing non-Latin text (so it
        has the client language's letters); the engine's default font only as a last resort. */
    function findFont(root:Dynamic):Dynamic {
        var tree = new GameScene();
        var stack:Array<Dynamic> = [root];
        var visited = 0;
        var fallback:Dynamic = null;
        while (stack.length > 0 && visited++ < 30000) {
            var node = stack.pop();
            if (G.isA(node, "h2d.Text")) {
                var f = G.field(node, "font");
                if (f != null) {
                    var text = G.str(G.field(node, "text"));
                    if (text != null) for (i in 0...text.length) if (StringTools.fastCodeAt(text, i) >= 0x400) return f;
                    if (fallback == null) fallback = f;
                }
            }
            for (kid in tree.children(node)) stack.push(kid);
        }
        return fallback != null ? fallback : G.staticCall("hxd.res.DefaultFont", "get", []);
    }

    function text(parent:Dynamic, value:String, color:Int, x:Float, y:Float, ?maxWidth:Float):Dynamic {
        var t = G.create("h2d.Text", [font, parent]);
        G.call("h2d.Text", "set_textColor", t, [color]);
        if (maxWidth != null) G.call("h2d.Text", "set_maxWidth", t, [maxWidth / fontScale]);
        G.call("h2d.Text", "set_text", t, [value]);
        G.call("h2d.Object", "setScale", t, [fontScale]);
        G.call("h2d.Object", "setPosition", t, [x, y]);
        return t;
    }

    function box(parent:Dynamic, x:Float, y:Float, w:Float, h:Float, color:Int):Dynamic {
        var area = G.create("h2d.Interactive", [w, h, parent, null]);
        G.set(area, "backgroundColor", color);
        G.call("h2d.Object", "setPosition", area, [x, y]);
        return area;
    }

    function setCaption(value:String):Void {
        if (caption != null) try G.call("h2d.Text", "set_text", caption, [value]) catch (_:Dynamic) {}
    }

    /** The skill's own icon, as the action bar draws it (lib.ExtensionsUI.toTile(skill.getIcon())). */
    function drawIcon(skill:Dynamic, parent:Dynamic):Bool {
        try {
            var gfx = G.call("st.skill.BaseSkill", "getIcon", skill);
            if (gfx == null) return false;
            var tile = G.staticCall("lib.ExtensionsUI", "toTile", [gfx]);
            if (tile == null) return false;
            var w = G.number(G.field(tile, "width")), h = G.number(G.field(tile, "height"));
            if (w <= 0 || h <= 0) return false;
            var bitmap = G.create("h2d.Bitmap", [tile, parent]);
            var scale = (CELL - 6) / Math.max(w, h);
            G.call("h2d.Object", "setScale", bitmap, [scale]);
            G.call("h2d.Object", "setPosition", bitmap, [(CELL - w * scale) / 2, (CELL - h * scale) / 2]);
            return true;
        } catch (_:Dynamic) {
            return false;
        }
    }

    function cell(parent:Dynamic, x:Float, y:Float, entry:HotbarSkill):Void {
        var area = box(parent, x, y, CELL, CELL, CELL_BG);
        if (!drawIcon(entry.skill, area)) text(area, entry.name, 0xFFF3D6, 3, 3, CELL - 6);
        var name = entry.name;
        G.set(area, "onOver", (_:Dynamic) -> { G.set(area, "backgroundColor", CELL_HOVER); setCaption(name); });
        G.set(area, "onOut", (_:Dynamic) -> { G.set(area, "backgroundColor", CELL_BG); setCaption(""); });
        G.set(area, "onClick", (_:Dynamic) -> {
            var pick = onPick;
            hide();
            if (pick != null) pick(entry);
        });
        try G.call("h2d.Interactive", "set_cursor", area, [G.current("hxd.Cursor", "Button")]) catch (_:Dynamic) {}
    }

    /**
     * Opens the picker on `scene` (the game's h2d.Scene) next to (x, y), normally the mouse
     * position of the click on "Choose". Returns false if nothing could be shown.
     */
    public function show(scene:Dynamic, title:String, entries:Array<HotbarSkill>, x:Float, y:Float, onPick:HotbarSkill -> Void):Bool {
        hide();
        if (scene == null) return false;
        try {
            if (font == null) font = findFont(scene);
            var lineHeight = G.number(G.field(font, "lineHeight"), 16);
            fontScale = lineHeight > 0 ? Math.min(1.5, Math.max(0.5, LINE / lineHeight)) : 1;

            var weapons = [for (e in entries) if (e.weapon) e];
            var others = [for (e in entries) if (!e.weapon) e];
            var rows = [for (r in [weapons, others]) if (r.length > 0) r];
            var perRow = 1;
            for (r in rows) perRow = Std.int(Math.max(perRow, r.length));
            var width = Math.max(PAD * 2 + perRow * (CELL + GAP) - GAP, 340);
            var height = PAD + LINE + GAP + rows.length * (CELL + GAP) + LINE + GAP + LINE + PAD;
            if (rows.length == 0) height += LINE;

            root = G.create("h2d.Object", [scene]); // last child of the scene: drawn on top of everything
            var sceneW = G.number(G.field(scene, "width"), 1920), sceneH = G.number(G.field(scene, "height"), 1080);
            // Clicking anywhere outside the panel closes it.
            var outside = box(root, 0, 0, sceneW, sceneH, 0x40000000);
            G.set(outside, "onClick", (_:Dynamic) -> hide());

            var px = Math.max(4, Math.min(x - CELL, sceneW - width - 4));
            var py = y + 16;
            if (py + height > sceneH - 4) py = Math.max(4, y - height - 16);
            var panel = box(root, px, py, width, height, 0xF0151212); // also keeps clicks on the panel from closing it

            text(panel, title, 0xFFF3D6, PAD, PAD);
            var rowY = PAD + LINE + GAP;
            if (rows.length == 0) {
                text(panel, "No skills found on your action bars.", 0xE0D8CD, PAD, rowY, width - PAD * 2);
                rowY += LINE;
            }
            for (r in rows) {
                var cx = PAD;
                for (entry in r) { cell(panel, cx, rowY, entry); cx += CELL + GAP; }
                rowY += CELL + GAP;
            }
            caption = text(panel, "", 0xFFE7A8, PAD, rowY, width - PAD * 2);
            var cancel = box(panel, width - PAD - 80, height - PAD - LINE - 4, 80, LINE + 4, CANCEL_BG);
            text(cancel, "Cancel", 0xFFF3D6, 8, 2);
            G.set(cancel, "onClick", (_:Dynamic) -> hide());
            try G.call("h2d.Interactive", "set_cursor", cancel, [G.current("hxd.Cursor", "Button")]) catch (_:Dynamic) {}

            this.onPick = onPick;
            open = true;
            return true;
        } catch (_:Dynamic) {
            hide();
            return false;
        }
    }
}
