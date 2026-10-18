package buildcalc;

/**
 * The "Calculator" tab of the hero profile window (ui.win.CharacterUI).
 *
 * The window's tabs are TitleWindow.tabs entries {key, name, ...}; the window casts the key to
 * ui.win.CharacterTab, so a key of another type would crash it. The enum value Apperance is never used
 * by the game (the appearance view is a separate flag), so it is the key of this tab: the window then
 * builds an empty content, and the mod fills titleWindowContent with its own panel.
 */
class BuildTab {
    static var key:Dynamic;
    /** What was built, reported to the log once a frame later (after the game's layout pass). */
    static var built:Array<{name:String, obj:Dynamic}> = [];

    static inline var COLOR_TITLE = 0x5A3E2B;
    static inline var COLOR_HEAD = 0x7A4E2E;
    static inline var COLOR_TEXT = 0x4A3A30;
    static inline var COLOR_NOTE = 0x8A7A6E;

    static function tabKey():Dynamic {
        if (key == null) key = HlxRuntime.constructEnum(G.type("ui.win.CharacterTab"), "Apperance", []);
        return key;
    }

    public static function isOurs(window:Dynamic):Bool {
        var current = G.field(window, "currentTab");
        return current != null && key != null && current == key;
    }

    /** After CharacterUI.initTabs: add the tab after the game's own ones. */
    public static function addTab(window:Dynamic):Void {
        var tabs = G.field(window, "tabs");
        var n = G.len(tabs);
        DebugLog.line("addTab: window=" + G.typeName(window) + " tabs=" + n + " current=" + G.str(G.field(window, "currentTab")));
        if (n == 0) return;
        for (i in 0...n) if (G.field(G.at(tabs, i), "key") == tabKey()) { DebugLog.line("addTab: already there"); return; }
        var tab:Dynamic = Reflect.copy(G.at(tabs, 0));
        if (tab == null) { DebugLog.line("addTab: copy of the first tab failed"); return; }
        HlxRuntime.setField(tab, "key", tabKey());
        HlxRuntime.setField(tab, "name", Texts.tabName());
        try HlxRuntime.setField(tab, "getNoReason", null) catch (e:Dynamic) DebugLog.error("addTab: clear getNoReason", e);
        G.call("hl.types.ArrayObj", "push", [tabs, tab]);
        DebugLog.line("addTab: done, tabs=" + G.len(tabs) + " name=" + Texts.tabName());
    }

    /** Width available for the panel: the content box once laid out, else the window, else a safe default. */
    static function panelWidth(window:Dynamic, content:Dynamic):Int {
        // the room of the tab's content inside the window (measured after the first layout: fit); before that the
        // window's width less a guess of its edges
        if (contentRoom > 0) return contentRoom;
        var w = G.num(G.field(window, "maxWidth"));
        if (w < 200) w = G.num(G.field(window, "calculatedWidth"));
        if (w < 200) w = 1200;
        return Std.int(w) - 80;
    }

    /** Width of the tab's content inside the profile window (window width less the content's edges), once measured. */
    static var contentRoom = 0;
    /** Width of the profile window with the game's own tabs. */
    static var windowWidth = 0.0;

    static var window:Dynamic;
    /** Height of the profile window with the game's own tabs (the panel must not make it taller). */
    static var windowHeight = 0.0;
    static var content:Dynamic;
    static var root:Dynamic;
    /** A one-line message under the controls (saved, opened, not ready, ...). */
    static var status = "";
    static var resetArmedUntil = 0.0;
    /** The template whose reset button waits for the confirming second click (-1 = none). */
    static var resetArmed = -1;

    /** After CharacterUI.init: draw the calculator when its tab is selected. */
    public static function build(w:Dynamic):Void {
        var ours = isOurs(w);
        DebugLog.line("build: window init, tab=" + G.str(G.field(w, "currentTab")) + " ours=" + ours);
        if (!ours) return;
        var c = G.field(w, "titleWindowContent");
        if (c == null) { DebugLog.line("build: no titleWindowContent"); return; }
        window = w;
        content = c;
        firstDraw = true;
        root = null;
        State.load();
        // the height of the window as the game's own tabs have it: the panel is fitted into it
        var h = G.num(G.field(w, "calculatedHeight"));
        if (h > 200 && (windowHeight <= 0 || h < windowHeight)) windowHeight = h;
        var ww = G.num(G.field(w, "maxWidth"));
        if (ww < 200) ww = G.num(G.field(w, "calculatedWidth"));
        if (ww > 200 && (windowWidth <= 0 || ww < windowWidth)) windowWidth = ww;
        // a calculation still running (the tab was left and opened again): its progress stays shown
        status = job != null ? Texts.calculating(Math.round(job.progress * 100)) : "";
        DebugLog.line("build: content " + Ui.describe(c) + "; window " + Ui.describe(w));
        draw();
    }

    /** Draws (or redraws after a click) the whole panel. */
    static function draw():Void {
        if (content == null) return;
        if (root != null) try G.call("h2d.Object", "remove", [root]) catch (e:Dynamic) DebugLog.error("draw: remove old panel", e);
        var headFont = Ui.heading(window), bodyFont = Ui.body(window);
        var margin = 6; // keep off the tab's left and right edges
        var width = panelWidth(window, content) - 2 * margin;
        var gap = 16;
        // left: the questionnaire; right: talents + equipment on top, skills + attributes under them
        var leftW = 300, rightW = width - gap - leftW;
        var equipW = 150, talentW = rightW - gap - equipW;
        var skillsW = 300, statsW = rightW - gap - skillsW;
        DebugLog.line("draw: width=" + width + " left=" + leftW + " talents=" + talentW + " equipment=" + equipW + " skills=" + skillsW
            + " stats=" + statsW + " settings=" + haxe.Json.stringify(State.settings) + " active=" + State.active);
        built = [];

        root = Ui.flow(content, true, 6, width + 2 * margin);
        G.call("h2d.Flow", "set_paddingBottom", [root, 8]);
        G.call("h2d.Flow", "set_paddingLeft", [root, margin]);
        G.call("h2d.Flow", "set_paddingRight", [root, margin]);
        built.push({name: "root", obj: root});
        var columns = Ui.flow(root, false, gap);
        built.push({name: "columns", obj: columns});

        var left = Ui.flow(columns, true, 3, leftW);
        built.push({name: "left", obj: left});
        drawQuestionnaire(left, headFont, bodyFont, leftW);

        var hero = G.call("ui.BaseElement", "get_myHero", [window]);
        var right = Ui.flow(columns, true, 8, rightW);
        built.push({name: "right", obj: right});

        var top = Ui.flow(right, false, gap, rightW);
        var talents = Ui.flow(top, true, 4, talentW);
        built.push({name: "talents", obj: talents});
        Ui.text(talents, headFont, Texts.talents(), COLOR_HEAD, 16, talentW);
        Ui.text(talents, bodyFont, Views.result != null || Views.saved != null ? Texts.chosenNote() : Texts.current(), COLOR_NOTE, 13, talentW);
        DebugLog.guard("draw: talent tree", () -> Views.talentTree(talents, hero, bodyFont, talentW));
        var equip = Ui.flow(top, true, 4, equipW);
        built.push({name: "equipment", obj: equip});
        Ui.text(equip, headFont, Texts.equipment(), COLOR_HEAD, 16, equipW);
        DebugLog.guard("draw: equipment", () -> Views.equipment(equip, hero, bodyFont, equipW));

        var bottom = Ui.flow(right, false, gap, rightW);
        var skillsCol = Ui.flow(bottom, true, 3, skillsW);
        built.push({name: "skills", obj: skillsCol});
        Ui.text(skillsCol, headFont, Texts.skillsTitle(), COLOR_HEAD, 16, skillsW);
        DebugLog.guard("draw: skills", () -> Views.skills(skillsCol, hero, bodyFont, skillsW));
        var statsCol = Ui.flow(bottom, true, 3, statsW);
        built.push({name: "stats", obj: statsCol});
        Ui.text(statsCol, headFont, Views.result != null ? Texts.newStats() : Texts.nowStats(), COLOR_HEAD, 16, statsW);
        DebugLog.guard("draw: totals", () -> Views.totals(statsCol, hero, bodyFont, statsW));
        DebugLog.guard("draw: attributes", () -> Views.attributes(statsCol, hero, bodyFont, headFont, statsW));
        DebugLog.line("draw: done");
        pendingReport = firstDraw;
        pendingFit = true;
        firstDraw = false;
    }

    static var pendingFit = false;

    /**
     * After the game's layout: the panel taller than the room the window has with its own tabs is scaled down to it,
     * so the profile window keeps its size.
     */
    static function fit():Void {
        if (!pendingFit || root == null || content == null) return;
        pendingFit = false;
        try {
            G.call("h2d.Object", "setScale", [root, 1.0]);
            try G.call("h2d.Flow", "reflow", [root]) catch (_:Dynamic) {}
            var h = G.num(G.field(root, "calculatedHeight"));
            var cpos = G.call("h2d.Object", "localToGlobal", [content, null]);
            var wpos = G.call("h2d.Object", "localToGlobal", [window, null]);
            var offset = G.num(G.field(cpos, "y")) - G.num(G.field(wpos, "y"));
            // the width: the content starts `left` px from the window's edge and has as much on the right; the panel
            // takes exactly the room between (drawn again once when it was built for another width)
            var left = G.num(G.field(cpos, "x")) - G.num(G.field(wpos, "x"));
            if (windowWidth > 200 && left >= 0 && left < windowWidth / 4) {
                var room = Std.int(Math.floor(windowWidth - 2 * left));
                DebugLog.line("fit: window " + Math.round(windowWidth) + " x " + Math.round(windowHeight) + " (now " + G.str(G.field(window, "calculatedWidth"))
                    + " x " + G.str(G.field(window, "calculatedHeight")) + "), content edge " + Math.round(left) + " px: panel width " + room);
                if (room > 600 && room != contentRoom) {
                    contentRoom = room;
                    draw();
                    return;
                }
            }
            var room = windowHeight - offset - 8;
            if (h > 0 && room > 200 && h > room) {
                var k = room / h;
                G.call("h2d.Object", "setScale", [root, k]);
                DebugLog.line("fit: panel " + Math.round(h) + " px, room " + Math.round(room) + " px (window " + Math.round(windowHeight) + ", top " + Math.round(offset) + "): scale " + Math.round(k * 1000) / 1000);
            } else DebugLog.line("fit: panel " + Math.round(h) + " px fits the room " + Math.round(room) + " px");
        } catch (e:Dynamic) DebugLog.error("fit", e);
    }

    /** One option group: buttons in a row, the chosen one pressed; `disabled` ones greyed out and inert. */
    static function options(parent:Dynamic, font:Dynamic, labels:Array<String>, chosen:Int, onChoose:Int->Void, width:Int, ?disabled:Array<Bool>):Void {
        var row = Ui.flow(parent, false, 4);
        var each = Std.int((width - 4 * (labels.length - 1)) / labels.length);
        for (i in 0...labels.length) {
            var index = i;
            // while the calculation runs nothing can be changed (the chosen option stays shown)
            var off = (disabled != null && disabled[i] && i != chosen) || (job != null && i != chosen);
            if (job != null && i == chosen) { Ui.lockedButton(row, font, labels[i], 13, each); continue; }
            if (off) Ui.disabledButton(row, font, labels[i], 13, each);
            else Ui.button(row, font, labels[i], 13, i == chosen, () -> onChoose(index), each);
        }
    }

    static function drawQuestionnaire(left:Dynamic, headFont:Dynamic, bodyFont:Dynamic, width:Int):Void {
        var s = State.settings;
        Ui.text(left, headFont, Texts.priorities(), COLOR_HEAD, 16, width);
        var axes = Texts.axes();
        var levels = Texts.levels();
        // buttons from high to none
        var order = [3, 2, 1, 0];
        for (a in 0...axes.length) {
            var axis = a;
            Ui.text(left, bodyFont, axes[a], COLOR_TEXT, 13, width);
            // one High in all; at most two Medium (an axis keeps its own choice)
            var highElsewhere = false, mediumElsewhere = 0;
            for (b in 0...axes.length) if (b != a) {
                if (s.priorities[b] == 3) highElsewhere = true;
                if (s.priorities[b] == 2) mediumElsewhere++;
            }
            var disabled = [highElsewhere, mediumElsewhere >= 2, false, false];
            options(left, bodyFont, [for (v in order) levels[v]], order.indexOf(s.priorities[a]), i -> {
                State.settings.priorities[axis] = order[i];
                DebugLog.line("click: " + axes[axis] + " = " + levels[order[i]]);
                State.save();
                draw();
            }, width, disabled);
        }
        Ui.text(left, headFont, Texts.combat(), COLOR_HEAD, 16, width);
        options(left, bodyFont, [Texts.melee(), Texts.ranged()], s.ranged ? 1 : 0, i -> {
            State.settings.ranged = i == 1;
            DebugLog.line("click: combat = " + (i == 1 ? "ranged" : "melee"));
            State.save();
            draw();
        }, width);

        if (job != null) Ui.disabledButton(left, headFont, Texts.calculatingButton(), 17, width);
        else Ui.button(left, headFont, Texts.calculate(), 17, true, () -> {
            DebugLog.line("click: calculate with " + haxe.Json.stringify(State.settings));
            var hero = G.call("ui.BaseElement", "get_myHero", [window]);
            try {
                job = new Optimizer(hero, State.settings);
                jobStart = haxe.Timer.stamp();
                status = Texts.calculating(0);
            } catch (e:Dynamic) {
                DebugLog.error("calculate", e);
                job = null;
                status = Texts.failed();
            }
            draw();
        }, width);


        Ui.text(left, headFont, Texts.templates(), COLOR_HEAD, 16, width);
        // a column per template: the template button, its own reset button under it
        var row = Ui.flow(left, false, 4);
        var each = Std.int((width - 4 * (State.TEMPLATES - 1)) / State.TEMPLATES);
        for (t in 0...State.TEMPLATES) {
            var slot = t;
            var col = Ui.flow(row, true, 4);
            if (job != null) {
                Ui.disabledButton(col, bodyFont, Texts.template(t) + (State.templates[t] == null ? "" : " •"), 13, each);
                Ui.disabledButton(col, bodyFont, Texts.resetOne(), 12, each);
                continue;
            }
            Ui.button(col, bodyFont, Texts.template(t) + (State.templates[t] == null ? "" : " •"), 13, State.active == t, () -> {
                DebugLog.line("click: template " + (slot + 1) + (State.templates[slot] == null ? " (empty)" : ""));
                State.openTemplate(slot);
                Views.result = null;
                Views.saved = State.templates[slot];
                status = State.templates[slot] == null ? Texts.emptyTemplate(slot) : Texts.opened(slot);
                draw();
            }, each);
            var armed = resetArmed == t && haxe.Timer.stamp() < resetArmedUntil;
            Ui.button(col, bodyFont, armed ? Texts.resetConfirm() : Texts.resetOne(), 12, false, () -> {
                if (resetArmed == slot && haxe.Timer.stamp() < resetArmedUntil) {
                    DebugLog.line("click: reset template " + (slot + 1) + " (confirmed)");
                    State.resetTemplate(slot);
                    resetArmed = -1;
                    status = Texts.clearedOne(slot);
                } else {
                    DebugLog.line("click: reset template " + (slot + 1) + " (asks to confirm)");
                    resetArmed = slot;
                    resetArmedUntil = haxe.Timer.stamp() + 4;
                }
                draw();
            }, each);
        }
        if (job != null) Ui.disabledButton(left, bodyFont, Texts.save(), 14, width);
        else Ui.button(left, bodyFont, Texts.save(), 14, false, () -> {
            var slot = State.active >= 0 ? State.active : 0;
            DebugLog.line("click: save to template " + (slot + 1));
            var r = Views.result;
            if (r == null) State.saveTemplate(slot);
            else {
                var b = r.build;
                var sigils = [];
                var augs = b.augs.get(3);
                if (augs != null) for (a in augs) for (id in a.skills) {
                    var d = SkillData.get(id);
                    if (d != null && d.maxPoints > 0) sigils.push(id);
                }
                State.saveTemplate(slot, [for (s => c in b.items) if (c != null) Views.templateEntry(b, s, c)], [for (id => rank in b.talents) {id: id, rank: rank}],
                    sigils, [for (id in b.skills) {id: id, runes: b.runes.exists(id) ? b.runes.get(id) : []}],
                    [for (id => n in r.infusions) {id: id, count: n}]);
            }
            status = Texts.savedTo(slot);
            draw();
        }, width);
        statusText = status != "" ? Ui.text(left, bodyFont, status, COLOR_NOTE, 14, width) : null;
        DebugLog.guard("draw: infusions", () -> Views.infusions(left, G.call("ui.BaseElement", "get_myHero", [window]), bodyFont, headFont, width));
    }

    static var pendingReport = false;

    /** The calculation in progress (null: none); it runs a few milliseconds each frame. */
    static var job:Optimizer = null;
    static var jobStart = 0.0;
    static var statusText:Dynamic = null;
    static var lastProgress = -1;

    /** Each frame: a little of the calculation; the window is drawn again when it is done. */
    public static function tick():Void {
        if (job == null) return;
        var finished = false;
        try finished = job.run(6) catch (e:Dynamic) {
            DebugLog.error("calculate", e);
            job = null;
            status = Texts.failed();
            draw();
            return;
        }
        if (!finished) {
            var p = Math.round(job.progress * 100);
            if (p != lastProgress && statusText != null) {
                lastProgress = p;
                try G.call("h2d.Text", "set_text", [statusText, Texts.calculating(p)]) catch (_:Dynamic) {}
            }
            return;
        }
        var took = Math.round((haxe.Timer.stamp() - jobStart) * 1000);
        DebugLog.line("calculate: done in " + took + " ms");
        Views.result = job.result;
        Views.saved = null;
        job = null;
        lastProgress = -1;
        var r = Views.result;
        status = r == null || r.pool == 0 ? Texts.noItems() : Texts.considered(r.pool) + " "
            + (r.changed == 0 ? Texts.alreadyBest() : Texts.changedSlots(r.changed)) + " " + Texts.calcTime(took, 0);
        DebugLog.flush();
        // drawn when the calculator tab is open (else when it is opened again: build)
        if (content != null && window != null && isOurs(window)) draw();
    }
    /** Layout sizes are logged once per opening of the tab, not after every click. */
    static var firstDraw = true;

    /** One frame after building (after the game's layout): log the sizes, to check the layout from the log. */
    public static function report():Void {
        fit();
        if (!pendingReport) return;
        pendingReport = false;
        for (b in built) DebugLog.line("layout: " + b.name + " " + Ui.describe(b.obj));
    }
}
