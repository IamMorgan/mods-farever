package macromod;

import macromod.GameAccess as G;
import macromod.HotbarSkills.HotbarSkill;
import macromod.Rotations.RotationData;

/** What the window needs from the mod: the skills on the bars, a skill by its kind, and the macros' keys. */
typedef RotationHost = {
    var entries:() -> Array<HotbarSkill>;
    var skillOf:(kind:String) -> Dynamic;
    var nameOf:(kind:String) -> String;
    var macroKeys:() -> Array<Dynamic>;
}

/**
 * The rotation window, drawn by the mod itself on the game's 2D scene (Better Mod Settings has no
 * control for a list like this). Opened by the "Rotations" button of the mod's settings. Every rotation
 * is a row of ten cells (a click picks a skill from the skill picker) with "Repeat", the activation key
 * and the press type under them. "New" adds a rotation at the top of the list.
 *
 * The list shows as many rows as fit on the screen; the mouse wheel and the arrow buttons scroll it by
 * one row. The window changes the list it was given and calls `onChange` after every change.
 */
class RotationWindow {
    /** Texts in the client's language; set by the mod. */
    public var russian = false;

    static inline var CELL = 48.0;
    static inline var PLUS_W = 20.0;
    static inline var PAD = 14.0;
    static inline var GAP = 8.0;
    static inline var LINE = UiKit.LINE;
    static inline var BTN_H = 26.0;
    static inline var ROW_H = CELL + GAP + BTN_H + 16.0;
    static inline var WIDTH = 780.0;
    static inline var MAX_ROWS = 6;
    static inline var ESC_GUARD = 0.4; // seconds after Esc cancelled a key choice in which Esc does not close the window

    static inline var PANEL_BG = 0xF0151212;
    static inline var CELL_BG = 0xFF2E2626;
    static inline var HOVER_BG = 0xFF6B5634;
    static inline var BUTTON_BG = 0xFF3F362E;
    static inline var NEW_BG = 0xFF2F5A34;
    static inline var DANGER_BG = 0xFF6A2A26;
    static inline var LISTEN_BG = 0xFF8A6A1E;
    static inline var LINE_COLOR = 0xFF3A322C;
    static inline var TEXT = 0xFFF3D6;
    static inline var DIM = 0xFFB5A58F;
    static inline var GOLD = 0xFFE7A8;
    static inline var ERROR = 0xFFFF8A80;

    var ui:UiKit;
    var picker:SkillPickerPanel;
    var keys:GameKeys;
    var host:RotationHost;
    var list:Array<RotationData> = [];
    var onChange:() -> Void;
    var scene:Dynamic;
    var root:Dynamic;
    var panel:Dynamic;
    var caption:Dynamic;
    var sceneW = 1920.0;
    var sceneH = 1080.0;
    var open = false;
    var dirty = false;
    var first = 0;      // the first rotation shown
    var perPage = 3;
    var capturing = -1; // rotation whose key is being chosen
    var held:Map<Int, Bool> = null;
    var message = "";
    var escGuardUntil = 0.0;
    var wheelHandler:Dynamic;
    var lastButton:Dynamic; // the button drawn last (to move it)

    public function new(ui:UiKit, picker:SkillPickerPanel, keys:GameKeys) {
        this.ui = ui;
        this.picker = picker;
        this.keys = keys;
        wheelHandler = (e:Dynamic) -> {
            var delta = G.number(G.field(e, "wheelDelta"));
            if (delta != 0) scrollBy(delta > 0 ? 1 : -1);
        };
    }

    public function isOpen():Bool return open;

    /** True while the player is choosing an activation key: hotkeys must not start anything then. */
    public function isCapturing():Bool return open && capturing >= 0;

    public function hide():Void {
        open = false;
        capturing = -1;
        held = null;
        message = "";
        onChange = null;
        picker.hide();
        ui.remove(root);
        root = null;
        panel = null;
        caption = null;
    }

    public function show(scene:Dynamic, list:Array<RotationData>, host:RotationHost, onChange:() -> Void):Bool {
        hide();
        if (scene == null) return false;
        try {
            this.scene = scene;
            this.list = list;
            this.host = host;
            this.onChange = onChange;
            ui.prepare(scene);
            sceneW = G.number(G.field(scene, "width"), 1920);
            sceneH = G.number(G.field(scene, "height"), 1080);
            perPage = Std.int(Math.max(1, Math.min(MAX_ROWS, Math.floor((sceneH - 40 - header() - footer()) / ROW_H))));
            first = 0;
            root = G.create("h2d.Object", [scene]); // last child of the scene: drawn on top of everything
            // Blocks the clicks that would reach the settings window behind this one.
            var blocker = ui.box(root, 0, 0, sceneW, sceneH, 0x60000000);
            G.set(blocker, "onWheel", wheelHandler);
            open = true;
            rebuild();
            return true;
        } catch (_:Dynamic) {
            hide();
            return false;
        }
    }

    static function header():Float return PAD + LINE + GAP + BTN_H + GAP;
    static function footer():Float return GAP + LINE * 2 + 4 + LINE + PAD;

    function width():Float return Math.min(WIDTH, sceneW - 16);

    /** Every frame while open (before the skill picker's own update, which closes on Esc as well). */
    public function update(now:Float):Void {
        if (!open) return;
        if (root == null || G.field(root, "allocated") != true) { hide(); return; }
        if (capturing >= 0) {
            pollKey(now);
        } else if (!picker.isOpen() && now >= escGuardUntil) {
            try if (G.staticCall("hxd.Key", "isPressed", [27]) == true) { hide(); return; } catch (_:Dynamic) {}
        }
        if (dirty) rebuild();
    }

    // ---- choosing the activation key ----

    function pollKey(now:Float):Void {
        var down = keys.heldKeys();
        var pressed = -1;
        if (held != null) for (code in down) if (!held.exists(code)) { pressed = code; break; }
        held = [for (code in down) code => true];
        if (pressed < 0) return;
        var index = capturing;
        capturing = -1;
        held = null;
        dirty = true;
        if (pressed == 27) { escGuardUntil = now + ESC_GUARD; return; } // Esc cancels the choice
        var modifier = GameKeys.supportsModifier(pressed) ? keys.heldModifier() : -1;
        var binding:Dynamic = modifier >= 0 ? {code: pressed, modifier: modifier} : pressed;
        setKey(index, binding);
    }

    public function setKey(index:Int, binding:Dynamic):Void {
        if (index >= list.length) return;
        var owner = Rotations.owner(list, index, binding, host.macroKeys());
        if (owner != null) {
            message = SettingsText.rotationKeyTaken(owner.isMacro, owner.number, russian);
            return;
        }
        message = "";
        list[index].hotkey = binding;
        changed();
    }

    /** A key binding as text: "F6", "Ctrl+1", or "Not set". */
    function keyName(binding:Dynamic):String {
        var code = MacroDefs.keyCode(binding);
        if (code <= 0) return SettingsText.rotationKeyNotSet(russian);
        var name:Null<String> = null;
        try name = G.str(G.staticCall("hxd.Key", "getKeyName", [code])) catch (_:Dynamic) {}
        if (name == null || name == "") name = "Key " + code;
        var modifier:Dynamic = (binding == null || Std.isOfType(binding, Int)) ? null : Reflect.field(binding, "modifier");
        if (Std.isOfType(modifier, Int)) {
            var prefix = switch ((modifier : Int)) { case 0: "Ctrl+"; case 1: "Shift+"; case 2: "Alt+"; default: ""; };
            name = prefix + name;
        }
        return name;
    }

    // ---- changes ----

    function changed():Void {
        dirty = true;
        if (onChange != null) onChange();
    }

    function scrollBy(rows:Int):Void {
        var max = Std.int(Math.max(0, list.length - perPage));
        var target = Std.int(Math.max(0, Math.min(max, first + rows)));
        capturing = -1;
        held = null;
        if (target == first) return;
        first = target;
        dirty = true;
    }

    function addRotation():Void {
        list.unshift(Rotations.create());
        first = 0;
        message = "";
        changed();
    }

    function deleteRotation(index:Int):Void {
        if (index >= list.length) return;
        list.splice(index, 1);
        message = "";
        changed();
    }

    function pickSkill(index:Int, cell:Int):Void {
        var x = 100.0, y = 100.0;
        try {
            x = G.number(G.call("h2d.Scene", "get_mouseX", scene), x);
            y = G.number(G.call("h2d.Scene", "get_mouseY", scene), y);
        } catch (_:Dynamic) {}
        picker.show(scene, SettingsText.rotationPickerTitle(index + 1, cell + 1, russian), host.entries(), x, y, entry -> {
            if (index < list.length) {
                list[index].slots[cell] = entry.kind;
                changed();
            }
        });
    }

    // ---- drawing ----

    /** A box that scrolls the list with the wheel. */
    function box(parent:Dynamic, x:Float, y:Float, w:Float, h:Float, color:Int):Dynamic {
        var area = ui.box(parent, x, y, w, h, color);
        G.set(area, "onWheel", wheelHandler);
        return area;
    }

    /** A click: any click ends a key choice that is being made, then `action` runs. */
    function onClick(area:Dynamic, action:() -> Void):Void {
        G.set(area, "onClick", (_:Dynamic) -> {
            capturing = -1;
            held = null;
            message = "";
            action();
        });
        ui.handCursor(area);
    }

    function hover(area:Dynamic, normal:Int, lit:Int = HOVER_BG):Void {
        G.set(area, "onOver", (_:Dynamic) -> G.set(area, "backgroundColor", lit));
        G.set(area, "onOut", (_:Dynamic) -> G.set(area, "backgroundColor", normal));
    }

    /** A button as wide as its text needs; returns the width. */
    function button(parent:Dynamic, x:Float, y:Float, label:String, color:Int, minWidth:Float, action:() -> Void):Float {
        var area = box(parent, x, y, minWidth, BTN_H, color);
        lastButton = area;
        var t = ui.text(area, label, TEXT, 8, (BTN_H - LINE) / 2);
        var w = Math.max(minWidth, ui.textWidth(t, label) + 16);
        G.set(area, "width", w);
        hover(area, color);
        onClick(area, action);
        return w;
    }

    function rebuild():Void {
        dirty = false;
        ui.remove(panel);
        var count = list.length;
        first = Std.int(Math.max(0, Math.min(first, Math.max(0, count - perPage))));
        var shown = Std.int(Math.max(0, Math.min(perPage, count - first)));
        var bodyH = count == 0 ? LINE * 2 : shown * ROW_H;
        var w = width();
        var h = header() + bodyH + footer();
        panel = box(root, Math.max(0, (sceneW - w) / 2), Math.max(0, (sceneH - h) / 2), w, h, PANEL_BG);

        ui.text(panel, SettingsText.rotationsTitle(russian), TEXT, PAD, PAD);
        var closeLabel = SettingsText.rotationClose(russian);
        var closeW = button(panel, 0, PAD - 4, closeLabel, DANGER_BG, 70, hide);
        G.call("h2d.Object", "setPosition", lastButton, [w - PAD - closeW, PAD - 4]);

        var rowY = PAD + LINE + GAP;
        button(panel, PAD, rowY, SettingsText.rotationNew(russian), NEW_BG, 90, addRotation);
        if (count > perPage) {
            var right = w - PAD;
            button(panel, right - 28, rowY, "v", BUTTON_BG, 28, () -> scrollBy(1));
            button(panel, right - 28 - 4 - 28, rowY, "^", BUTTON_BG, 28, () -> scrollBy(-1));
            var info = SettingsText.rotationPage(first + 1, first + shown, count);
            var infoText = ui.text(panel, info, DIM, 0, rowY + (BTN_H - LINE) / 2);
            G.call("h2d.Object", "setPosition", infoText, [right - 28 - 4 - 28 - 10 - ui.textWidth(infoText, info), rowY + (BTN_H - LINE) / 2]);
        }

        if (count == 0) ui.text(panel, SettingsText.rotationEmpty(russian), DIM, PAD, header() + 2);
        for (i in first...first + shown) drawRotation(i, PAD, header() + (i - first) * ROW_H);

        var hint = SettingsText.rotationHint(russian);
        caption = ui.text(panel, hint, DIM, PAD, h - footer() + GAP, w - PAD * 2);
        ui.text(panel, message, ERROR, PAD, h - PAD - LINE, w - PAD * 2);
    }

    function drawRotation(index:Int, x0:Float, y0:Float):Void {
        var data = list[index];
        var w = width();
        for (cell in 0...Rotations.SLOTS) {
            var cx = x0 + cell * (CELL + PLUS_W);
            drawCell(index, cell, cx, y0);
            if (cell < Rotations.SLOTS - 1) {
                var plus = ui.text(panel, "+", DIM, 0, 0);
                var pw = ui.textWidth(plus, "+");
                G.call("h2d.Object", "setPosition", plus, [cx + CELL + (PLUS_W - pw) / 2, y0 + (CELL - LINE) / 2]);
            }
        }

        var y = y0 + CELL + GAP;
        var textY = y + (BTN_H - LINE) / 2;
        var x = x0;

        // Repeat
        var toggle = () -> { data.repeat = !data.repeat; changed(); };
        var checkbox = box(panel, x, y + 3, 20, 20, CELL_BG);
        if (data.repeat) ui.text(checkbox, "X", GOLD, 5, 1);
        onClick(checkbox, toggle);
        var repeatLabel = SettingsText.rotationRepeat(russian);
        var labelText = ui.text(panel, repeatLabel, TEXT, x + 26, textY);
        var labelW = ui.textWidth(labelText, repeatLabel);
        var labelArea = box(panel, x + 26, y, labelW, BTN_H, 0x00000000);
        onClick(labelArea, toggle);
        x += 26 + labelW + 22;

        // Activation key
        var keyLabel = SettingsText.rotationKey(russian);
        var keyText = ui.text(panel, keyLabel, TEXT, x, textY);
        x += ui.textWidth(keyText, keyLabel) + 8;
        var listening = capturing == index;
        var keyColor = listening ? LISTEN_BG : BUTTON_BG;
        var keyW = button(panel, x, y, listening ? SettingsText.rotationPressKey(russian) : keyName(data.hotkey), keyColor, 120, () -> {
            capturing = index;
            held = null;
            dirty = true;
        });
        x += keyW + 4;
        if (MacroDefs.keyCode(data.hotkey) > 0) {
            x += button(panel, x, y, "x", DANGER_BG, 26, () -> { data.hotkey = 0; changed(); }) + 4;
        }
        x += 14;

        // Press type: Toggle (press to start, press to stop) or Hold (held = running)
        x += button(panel, x, y, SettingsText.modes(russian)[data.hold ? 1 : 0], BUTTON_BG, 150, () -> { data.hold = !data.hold; changed(); }) + 14;

        button(panel, x, y, SettingsText.rotationDelete(russian), DANGER_BG, 80, () -> deleteRotation(index));

        box(panel, x0, y0 + ROW_H - 8, w - PAD * 2, 1, LINE_COLOR);
    }

    function drawCell(index:Int, cell:Int, cx:Float, cy:Float):Void {
        var data = list[index];
        var kind = data.slots[cell];
        var area = box(panel, cx, cy, CELL, CELL, CELL_BG);
        G.set(area, "enableRightButton", true);
        if (kind != "") {
            var skill:Dynamic = null;
            try skill = host.skillOf(kind) catch (_:Dynamic) {}
            if (skill == null || !ui.drawIcon(skill, area, CELL)) ui.text(area, host.nameOf(kind), DIM, 3, 3, CELL - 6);
            var clear = box(area, CELL - LINE, 0, LINE, LINE, DANGER_BG);
            ui.text(clear, "x", TEXT, 5, 0);
            onClick(clear, () -> { data.slots[cell] = ""; changed(); });
        }
        var name = kind == "" ? "" : host.nameOf(kind);
        G.set(area, "onOver", (_:Dynamic) -> { G.set(area, "backgroundColor", HOVER_BG); if (name != "") ui.setText(caption, name); });
        G.set(area, "onOut", (_:Dynamic) -> { G.set(area, "backgroundColor", CELL_BG); ui.setText(caption, SettingsText.rotationHint(russian)); });
        G.set(area, "onClick", (e:Dynamic) -> {
            capturing = -1;
            held = null;
            message = "";
            if (G.integer(G.field(e, "button"), 0) == 1) {
                if (kind != "") { data.slots[cell] = ""; changed(); }
            } else pickSkill(index, cell);
        });
        ui.handCursor(area);
    }
}
