package dpf;

import dpf.GameAccess as G;
import dpf.PartyFlow.Card;
import dpf.Session.Mode;
import dpf.Session.SessionView;

/**
 * The dungeon window of the finder, drawn like the game's own dungeon dialog: the dungeon's picture and description, the
 * three difficulty buttons, the required level, the hero's card and one big button. Before a search the button is
 * "Search"; while searching it is "Cancel" with a turning circle and "Searching..." above it; once a party has formed it is
 * "Start" (leader) or "Ready" (the others) and the party's cards are shown. It shows what `Session.view()` says.
 */
class SearchWindow {
    static inline var W = 600.0;
    static inline var HEADER = 50.0;
    static inline var PICTURE = 225.0;
    static inline var BAND_TOP = HEADER + PICTURE + 4;
    static inline var BAND_H = 136.0;
    static inline var CARD_W = 388.0;
    static inline var CARD_H = 58.0;
    static inline var CARD_GAP = 8.0;
    static inline var BUTTON_W = 200.0;
    static inline var BUTTON_H = 50.0;
    static inline var DIFF_W = 86.0;
    static inline var DIFF_H = 46.0;
    static var ICONS = ["Dungeon_Default", "Dungeon_LevelMax", "Dungeon_Heroic"];

    public var russian = false;

    var ui:UiKit;
    var scene:Dynamic;
    var root:Dynamic;
    var session:Session;
    var signature = "";
    var spinner:Dynamic;
    var lastNow = 0.0;
    var nextView = 0.0;
    var open = false;
    var picture:Dynamic;
    var icons:Array<Dynamic> = [];
    var onClose:Void -> Void;

    public function new(ui:UiKit) this.ui = ui;

    public function isOpen():Bool return open;

    public function current():Session return open ? session : null;

    public function hide():Void {
        open = false;
        ui.remove(root);
        root = null;
        spinner = null;
        signature = "";
    }

    public function whenClosed(handler:Void -> Void):Void onClose = handler;

    public function show(scene:Dynamic, session:Session):Void {
        hide();
        if (scene == null || session == null) return;
        this.scene = scene;
        this.session = session;
        session.russian = russian;
        session.refresh();
        picture = GameDungeons.picture(session.dungeon.image);
        icons = [for (id in ICONS) GameDungeons.icon(id)];
        open = true;
        try rebuild(session.view()) catch (error:Dynamic) { trace("[DPF] window failed: " + Std.string(error)); hide(); }
    }

    /** Every frame while open. */
    public function update(now:Float):Void {
        if (!open) return;
        if (root == null || G.field(root, "allocated") != true) { hide(); return; }
        var dt = lastNow == 0 ? 0 : Math.min(0.1, now - lastNow);
        lastNow = now;
        if (now >= nextView || signature == "") {
            nextView = now + 0.2;
            try {
                var view = session.view();
                if (view.signature != signature) rebuild(view);
            } catch (error:Dynamic) trace("[DPF] window rebuild failed: " + Std.string(error));
        }
        if (spinner != null) try G.set(spinner, "rotation", (now * 4.2) % (Math.PI * 2)) catch (_:Dynamic) {}
    }

    function close():Void {
        hide();
        if (onClose != null) onClose();
    }

    // ---- drawing ----

    function rebuild(view:SessionView):Void {
        signature = view.signature;
        ui.remove(root);
        spinner = null;
        ui.prepare(scene);
        var sceneW = G.number(G.field(scene, "width"), 1920), sceneH = G.number(G.field(scene, "height"), 1080);
        var dungeon = session.dungeon;

        // ---- measure the lower part first: the window is as tall as its content ----
        var cardsTop = BAND_TOP + BAND_H + 190.0;
        var y = cardsTop + view.cards.length * (CARD_H + CARD_GAP) - CARD_GAP + 16;
        var hasStatus = view.status != "";
        if (hasStatus) y += view.info != "" ? 50 : 30;
        var messageLines:Array<String> = view.message == "" ? [] : ui.wrap(scene, view.message, 17, W - 80);
        if (messageLines.length > 0) y += messageLines.length * 22 + 8;
        var buttonTop = y + 6;
        var height = buttonTop + BUTTON_H + 30;
        var scale = Math.min(1.0, Math.min((sceneH - 16) / height, (sceneW - 16) / W));

        root = G.create("h2d.Object", [scene]);
        G.call("h2d.Object", "setScale", root, [scale]);
        G.call("h2d.Object", "setPosition", root, [Math.round((sceneW - W * scale) / 2), Math.round((sceneH - height * scale) / 2)]);

        var g = ui.shapes(root);
        Style.frame(ui, g, W, height, HEADER);
        ui.area(root, 0, 0, W, height); // swallows the clicks that would fall through to the game
        ui.centered(root, dungeon.name, Style.TITLE, W / 2, 13, 25, W - 120);
        closeButton(W - 30, HEADER / 2 + 1);

        // ---- the picture, with the orange line under it ----
        if (!ui.fitTile(root, picture, 2, HEADER, W - 4, PICTURE, true)) ui.rect(ui.shapes(root), 2, HEADER, W - 4, PICTURE, 0x2B2A33);
        ui.rect(ui.shapes(root), 2, HEADER + PICTURE, W - 4, 4, Style.STRIPE);

        // ---- the description ----
        ui.rect(ui.shapes(root), 2, BAND_TOP, W - 4, BAND_H, Style.BAND);
        var size = 19.0;
        var lines = ui.wrap(root, dungeon.desc, size, W - 90);
        if (lines.length > 5) { size = 16; lines = ui.wrap(root, dungeon.desc, size, W - 90); }
        if (lines.length > 6) { lines = lines.slice(0, 6); lines[5] = lines[5] + "..."; }
        var lineH = size * 1.32;
        var textTop = BAND_TOP + (BAND_H - lines.length * lineH) / 2;
        for (i in 0...lines.length) ui.centered(root, lines[i], Style.DARK, W / 2, textTop + i * lineH, size);

        // ---- difficulty ----
        var top = BAND_TOP + BAND_H;
        ui.centered(root, Locale.chooseDifficulty(russian), Style.DARK, W / 2, top + 24, 21);
        var diffTop = top + 56;
        var left = (W - DIFF_W * Difficulties.COUNT) / 2;
        for (i in 0...Difficulties.COUNT) difficultyButton(i, left + i * DIFF_W, diffTop, view.mode == Mode.Idle);
        ui.centered(root, requiredText(), Style.DARK, W / 2, diffTop + DIFF_H + 14, 21);
        ui.centered(root, Locale.matching(russian, session.difficulty, session.bracketLabel()), Style.DIM, W / 2, diffTop + DIFF_H + 42, 16);
        ui.rect(ui.shapes(root), 60, diffTop + DIFF_H + 74, W - 120, 1.5, Style.RIVET, 0.8);
        ui.circle(ui.shapes(root), 54, diffTop + DIFF_H + 74.7, 3.5, Style.RIVET);
        ui.circle(ui.shapes(root), W - 54, diffTop + DIFF_H + 74.7, 3.5, Style.RIVET);

        // ---- cards ----
        var party = view.mode == Mode.Party;
        for (i in 0...view.cards.length) card(view.cards[i], (W - CARD_W) / 2, cardsTop + i * (CARD_H + CARD_GAP), party);

        // ---- status line, message, button ----
        var sy = cardsTop + view.cards.length * (CARD_H + CARD_GAP) - CARD_GAP + 16;
        if (hasStatus) {
            var t = ui.centered(root, view.status, Style.DARK, W / 2, sy + 4, 22);
            if (view.spinner) {
                var cx = W / 2 - ui.textWidth(t, 22) / 2 - 22;
                spinner = ui.group(root, cx, sy + 16);
                Style.spinner(ui, ui.shapes(spinner), 9, 2.6);
            }
            sy += 30;
            if (view.info != "") { ui.centered(root, view.info, Style.DIM, W / 2, sy, 17); sy += 20; }
        }
        for (i in 0...messageLines.length) ui.centered(root, messageLines[i], Style.ERROR, W / 2, sy + 4 + i * 22, 17);
        button(view, (W - BUTTON_W) / 2, buttonTop);
    }

    function requiredText():String {
        var maxLevel = 25;
        try maxLevel = G.integer(G.field(G.current("Const", "Hero"), "MaxLevel"), 25) catch (_:Dynamic) {}
        return session.difficulty == 0
            ? Locale.recommendedLevel(russian, session.dungeon.level)
            : Locale.requiredLevel(russian, maxLevel);
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

    function difficultyButton(index:Int, x:Float, y:Float, changeable:Bool):Void {
        var usable = session.usable[index] == true;
        var selected = session.difficulty == index;
        var g = ui.shapes(root);
        ui.framed(g, x, y, DIFF_W, DIFF_H, 3, selected ? Style.DIFF_ON : Style.DIFF, selected ? Style.DIFF_RING : Style.DIFF_LINE, selected ? 2.5 : 1.5, usable ? 1 : 0.55);
        var shown = ui.fitTile(root, icons[index], x + (DIFF_W - 34) / 2, y + (DIFF_H - 34) / 2, 34, 34);
        if (!shown) ui.centered(root, index == 0 ? "I" : (index == 1 ? "II" : "III"), Style.BUTTON_TEXT, x + DIFF_W / 2, y + 11, 22);
        if (!usable) ui.rect(ui.shapes(root), x + 2, y + 2, DIFF_W - 4, DIFF_H - 4, 0x2A201C, 0.35);
        var hit = ui.area(root, x, y, DIFF_W, DIFF_H);
        if (usable && changeable) {
            ui.handCursor(hit);
            G.set(hit, "onClick", (_:Dynamic) -> {
                session.selectDifficulty(index);
                signature = ""; // redraw at once
            });
        }
    }

    function card(card:Card, x:Float, y:Float, party:Bool):Void {
        var g = ui.shapes(root);
        ui.framed(g, x, y, CARD_W, CARD_H, 5, Style.CARD, Style.CARD_LINE, 1.5);
        var name = card.name == "" ? "?" : card.name;
        ui.text(root, name, Style.DARK, x + 19, y + 5, 23, CARD_W - 130);
        ui.text(root, name, Style.DARK, x + 19.6, y + 5, 23, CARD_W - 130); // a touch bolder
        ui.text(root, card.detail, Style.DIM, x + 19, y + 32, 19, CARD_W - 130);
        var right = x + CARD_W - 14;
        if (party && card.ready) {
            Style.check(ui, ui.shapes(root), right - 24, y + 19, 18, Style.OK);
            right -= 40;
        }
        if (party && card.leader) Style.crown(ui, ui.shapes(root), right - 26, y + 19, 26);
    }

    function button(view:SessionView, x:Float, y:Float):Void {
        var enabled = view.button.enabled;
        var base = ui.shapes(root);
        var fill = !enabled ? Style.BUTTON_OFF : (view.button.lit ? Style.BUTTON_ON : Style.BUTTON);
        ui.framed(base, x, y, BUTTON_W, BUTTON_H, 6, fill, Style.LINE, 2);
        var hover = ui.shapes(root);
        ui.framed(hover, x, y, BUTTON_W, BUTTON_H, 6, Style.BUTTON_HOVER, Style.LINE, 2);
        ui.visible(hover, false);
        var label = view.button.label;
        var size = 24.0;
        var probe = ui.text(root, label, 0, -5000, -5000, size);
        while (size > 14 && ui.textWidth(probe, size) > BUTTON_W - 20) { size -= 1; ui.setText(probe, label); }
        ui.remove(probe);
        var ty = y + (BUTTON_H - size * 1.2) / 2;
        ui.centered(root, label, enabled ? Style.BUTTON_SHADOW : Style.DIM, x + BUTTON_W / 2 + 1, ty + 1.5, size);
        ui.centered(root, label, enabled ? Style.BUTTON_TEXT : Style.BUTTON_SHADOW, x + BUTTON_W / 2, ty, size);
        var hit = ui.area(root, x, y, BUTTON_W, BUTTON_H);
        if (enabled) {
            ui.handCursor(hit);
            G.set(hit, "onOver", (_:Dynamic) -> ui.visible(hover, true));
            G.set(hit, "onOut", (_:Dynamic) -> ui.visible(hover, false));
            G.set(hit, "onClick", (_:Dynamic) -> {
                session.press(haxe.Timer.stamp());
                signature = "";
            });
        }
    }
}
