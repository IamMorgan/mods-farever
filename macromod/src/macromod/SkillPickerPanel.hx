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
    /** Panel texts in the client's language; set by the mod. */
    public var russian = false;

    static inline var CELL = 56.0;
    static inline var GAP = 6.0;
    static inline var PAD = 10.0;
    static inline var LINE = UiKit.LINE;
    static inline var CELL_BG = 0xFF2E2626;
    static inline var CELL_HOVER = 0xFF6B5634;
    static inline var CANCEL_BG = 0xFF6A2A26;

    var root:Dynamic;
    var caption:Dynamic;
    var onPick:HotbarSkill -> Void;
    var open = false;

    var ui:UiKit;

    public function new(ui:UiKit) this.ui = ui;

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

    function setCaption(value:String):Void {
        if (caption != null) try G.call("h2d.Text", "set_text", caption, [value]) catch (_:Dynamic) {}
    }

    function cell(parent:Dynamic, x:Float, y:Float, entry:HotbarSkill):Void {
        var area = ui.box(parent, x, y, CELL, CELL, CELL_BG);
        if (!ui.drawIcon(entry.skill, area, CELL)) ui.text(area, entry.name, 0xFFF3D6, 3, 3, CELL - 6);
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
            ui.prepare(scene);

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
            var outside = ui.box(root, 0, 0, sceneW, sceneH, 0x40000000);
            G.set(outside, "onClick", (_:Dynamic) -> hide());

            var px = Math.max(4, Math.min(x - CELL, sceneW - width - 4));
            var py = y + 16;
            if (py + height > sceneH - 4) py = Math.max(4, y - height - 16);
            var panel = ui.box(root, px, py, width, height, 0xF0151212); // also keeps clicks on the panel from closing it

            ui.text(panel, title, 0xFFF3D6, PAD, PAD);
            var rowY = PAD + LINE + GAP;
            if (rows.length == 0) {
                ui.text(panel, SettingsText.noSkills(russian), 0xE0D8CD, PAD, rowY, width - PAD * 2);
                rowY += LINE;
            }
            for (r in rows) {
                var cx = PAD;
                for (entry in r) { cell(panel, cx, rowY, entry); cx += CELL + GAP; }
                rowY += CELL + GAP;
            }
            caption = ui.text(panel, "", 0xFFE7A8, PAD, rowY, width - PAD * 2);
            var cancel = ui.box(panel, width - PAD - 80, height - PAD - LINE - 4, 80, LINE + 4, CANCEL_BG);
            ui.text(cancel, SettingsText.cancel(russian), 0xFFF3D6, 8, 2);
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
