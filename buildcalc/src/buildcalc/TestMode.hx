package buildcalc;

/**
 * Test mode: the assistant drives the calculator in the running game through files, without touching the game.
 *
 * A command is written to hlx/config/buildcalc/test/command.json ({"id": "...", "cmd": "...", ...}); the mod takes it
 * (the file is removed), runs it the same way the window's buttons do and writes the answer to result.json
 * ({"id", "ok", "cmd", ...}); every step is also in hlx/buildcalc-debug.txt (lines "test:").
 * Nothing is sent to the server: no item is worn, no talent or rune is changed in the game.
 *
 * Commands:
 *  - status: hero, window, calculator tab, running calculation, saved last results.
 *  - calculate {priorities:[4 ints 0..3], ranged, ideal, crit, fresh, search, talents:{id:rank}, runes:{skill:[runes]},
 *    skills:[ids], infusions:{slot:id}}: a calculation as the "Calculate" button does it. fresh: the last result is not a start; search:false:
 *    the start build only valued (no search); talents/runes/skills: the worn build as if the hero had them (a
 *    recommendation "followed" without changing the game); infusions: set on the start build (with search:false and
 *    fresh:false: a variant of the last result valued as it is). The answer comes when the calculation is done.
 *  - followLast {priorities, ranged, ideal}: calculate again with the talents, runes and skills of the last result of
 *    this questionnaire as the worn ones (the player followed every talent/rune recommendation).
 *  - saveTemplate {slot:0..2}: saves the result shown to a template (as the "Save" button).
 *  - template {slot:0..2}: opens a template in the window (as its button).
 *  - tooltip {slot} / hideTooltip: the game's tooltip of an item cell of the calculator, as when the mouse is on it.
 *  - screenshot {file}: the game's 2D scene (all its windows) saved as a PNG in the test folder.
 */
class TestMode {
    public static inline var DIR = "hlx/config/buildcalc/test";
    static inline var COMMAND = DIR + "/command.json";
    static inline var RESULT = DIR + "/result.json";

    static var nextCheck = 0.0;
    /** The command waiting for its calculation to end (null: none). */
    static var waiting:Dynamic = null;
    static var app:Dynamic = null;
    static var shownTip:Dynamic = null;

    /** Each frame (GameApp.update): looks for a command twice a second. */
    public static function tick(gameApp:Dynamic):Void {
        #if release
        return;
        #end
        app = gameApp;
        var now = haxe.Timer.stamp();
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        if (waiting != null) return;
        if (!sys.FileSystem.exists(COMMAND)) return;
        var cmd:Dynamic = null;
        try {
            var text = sys.io.File.getContent(COMMAND);
            sys.FileSystem.deleteFile(COMMAND);
            cmd = haxe.Json.parse(text);
        } catch (e:Dynamic) {
            answer({id: "?", ok: false, error: "the command file could not be read: " + Std.string(e)});
            return;
        }
        var id = Std.string(Reflect.field(cmd, "id"));
        var name = Std.string(Reflect.field(cmd, "cmd"));
        DebugLog.line("test: command " + id + " " + haxe.Json.stringify(cmd));
        try run(cmd, id, name) catch (e:Dynamic) {
            DebugLog.error("test: " + name, e);
            answer({id: id, cmd: name, ok: false, error: Std.string(e)});
        }
    }

    static function run(cmd:Dynamic, id:String, name:String):Void {
        switch (name) {
            case "status":
                var hero = myHero();
                answer({id: id, cmd: name, ok: true, hero: hero != null, heroLevel: hero == null ? 0 : G.num(G.field(hero, "_level")),
                    window: BuildTab.windowOpen(), calculatorTab: BuildTab.calculatorShown(), calculating: BuildTab.calculating(),
                    settings: State.settings, lasts: [for (l in State.lasts) {settings: l.settings, savedAt: l.savedAt, model: l.model}],
                    model: Optimizer.MODEL_VERSION});
            case "calculate", "followLast":
                var hero = myHero();
                if (hero == null) { answer({id: id, cmd: name, ok: false, error: "no hero in the world"}); return; }
                if (BuildTab.calculating()) { answer({id: id, cmd: name, ok: false, error: "a calculation is running"}); return; }
                var s = settingsOf(cmd);
                var opts:Optimizer.TestOptions = {fresh: Reflect.field(cmd, "fresh") == true, search: Reflect.field(cmd, "search") != false,
                    talents: null, runes: null, skills: null};
                if (name == "followLast") {
                    var l = State.lastFor(s);
                    if (l == null) { answer({id: id, cmd: name, ok: false, error: "no last result for this questionnaire"}); return; }
                    if (l.talents != null) opts.talents = [for (t in l.talents) t.id => t.rank];
                    if (l.skills != null) {
                        opts.skills = [for (k in l.skills) k.id];
                        opts.runes = [for (k in l.skills) k.id => k.runes];
                    }
                } else {
                    var t:Dynamic = Reflect.field(cmd, "talents");
                    if (t != null) opts.talents = [for (k in Reflect.fields(t)) k => Std.int(Reflect.field(t, k))];
                    var r:Dynamic = Reflect.field(cmd, "runes");
                    if (r != null) opts.runes = [for (k in Reflect.fields(r)) k => [for (x in (Reflect.field(r, k) : Array<Dynamic>)) Std.string(x)]];
                    var k:Dynamic = Reflect.field(cmd, "skills");
                    if (k != null) opts.skills = [for (x in (k : Array<Dynamic>)) Std.string(x)];
                }
                var inf:Dynamic = Reflect.field(cmd, "infusions");
                if (inf != null) opts.infusions = [for (k in Reflect.fields(inf)) Std.parseInt(k) => Std.string(Reflect.field(inf, k))];
                State.settings = s;
                State.save();
                if (!BuildTab.startCalc(hero, s, opts)) { answer({id: id, cmd: name, ok: false, error: "the calculation did not start (see the log)"}); return; }
                waiting = {id: id, cmd: name};
            case "features":
                // switches of the simulation's newer parts: {off:["summonAttacks","rankPassives","subUltimate","stepTick","newTarget"]} ([] = all on)
                buildcalc.sim.Sim.off = new Map();
                var list:Dynamic = Reflect.field(cmd, "off");
                if (list != null) for (x in (list : Array<Dynamic>)) buildcalc.sim.Sim.off.set(Std.string(x), true);
                answer({id: id, cmd: name, ok: true, off: [for (k in buildcalc.sim.Sim.off.keys()) k]});
            case "saveTemplate":
                var slot = Std.int(Reflect.field(cmd, "slot"));
                BuildTab.saveToTemplate(slot);
                answer({id: id, cmd: name, ok: true, template: State.templates[slot]});
            case "seedTemplate":
                // the template becomes the last result of its questionnaire (the model of now): calculate with fresh:false,
                // search:false values it as it is, with search it searches from it
                var tp = State.templates[Std.int(Reflect.field(cmd, "slot"))];
                if (tp == null || tp.build == null) { answer({id: id, cmd: name, ok: false, error: "no such template"}); return; }
                State.setLast(tp.settings, tp.build, tp.talents, tp.skills, Optimizer.MODEL_VERSION);
                answer({id: id, cmd: name, ok: true, settings: tp.settings});
            case "lastTalents":
                // the talents of the last result of the questionnaire are replaced (to value its items with other talents)
                var ls = State.lastFor(settingsOf(cmd));
                var tt:Dynamic = Reflect.field(cmd, "talents");
                if (ls == null || tt == null) { answer({id: id, cmd: name, ok: false, error: "no last result or no talents"}); return; }
                ls.talents = [for (k in Reflect.fields(tt)) {id: k, rank: Std.int(Reflect.field(tt, k))}];
                State.save();
                answer({id: id, cmd: name, ok: true, talents: ls.talents});
            case "statuses":
                // the statuses the hero has right now (id x stacks): what an enchant (Devote, Zealot) gave in a fight
                var hh = myHero();
                var ids:Array<String> = [];
                if (hh != null) {
                    var list = G.field(G.field(hh, "statuses"), "array");
                    for (i in 0...G.len(list)) {
                        var st = G.at(list, i);
                        if (st != null) ids.push(G.str(G.field(G.field(st, "inf"), "id")) + "x" + G.str(G.field(st, "stacks")));
                    }
                }
                answer({id: id, cmd: name, ok: true, statuses: ids});
            case "result":
                // the "Result" button: the last result of this session shown again
                BuildTab.showResult();
                answer({id: id, cmd: name, ok: true, shown: Views.result != null});
            case "template":
                var slot = Std.int(Reflect.field(cmd, "slot"));
                BuildTab.openTemplate(slot);
                answer({id: id, cmd: name, ok: true, template: State.templates[slot]});
            case "tooltip":
                // the tooltip of an item cell, shown as when the mouse is on it (ui.UIElement.showTip)
                var slot = Std.int(Reflect.field(cmd, "slot"));
                var cell = Views.cells.get(slot);
                if (cell == null) { answer({id: id, cmd: name, ok: false, error: "no cell for slot " + slot + " (is the calculator tab open?)"}); return; }
                if (shownTip != null) try G.call("ui.UIElement", "hideTip", [shownTip]) catch (_:Dynamic) {}
                G.call("ui.UIElement", "showTip", [cell]);
                shownTip = cell;
                answer({id: id, cmd: name, ok: true, slot: slot});
            case "hideTooltip":
                if (shownTip != null) try G.call("ui.UIElement", "hideTip", [shownTip]) catch (_:Dynamic) {}
                shownTip = null;
                answer({id: id, cmd: name, ok: true});
            case "screenshot":
                var file = Reflect.field(cmd, "file") != null ? Std.string(Reflect.field(cmd, "file")) : "screen.png";
                var path = DIR + "/" + file;
                screenshot(path);
                answer({id: id, cmd: name, ok: true, file: path, calculatorTab: BuildTab.calculatorShown()});
            default:
                answer({id: id, cmd: name, ok: false, error: "unknown command"});
        }
    }

    /** The calculation of a test command ended (BuildTab.tick). */
    public static function finished(result:Optimizer.BuildResult, took:Int):Void {
        if (waiting == null) return;
        var w = waiting;
        waiting = null;
        if (result == null) { answer({id: w.id, cmd: w.cmd, ok: false, error: "no result (see the log)"}); return; }
        answer({id: w.id, cmd: w.cmd, ok: true, ms: took, builds: result.builds, fights: result.fights, replayed: result.replayed, checked: result.checked, settings: State.settings, chosen: describe(result.build, result.eval),
            worn: describe(result.worn, result.now), changedSlots: result.changed});
    }

    /** The calculation of a test command failed. */
    public static function failed(error:String):Void {
        if (waiting == null) return;
        var w = waiting;
        waiting = null;
        answer({id: w.id, cmd: w.cmd, ok: false, error: error});
    }

    static function describe(b:Model.Build, e:Model.Eval):Dynamic {
        var items = [];
        for (s in Items.SLOTS) {
            var c = b.items.get(s);
            if (c == null) continue;
            items.push({slot: s, id: c.id, source: c.source, upgrade: c.upgrade,
                infusion: b.infusion.exists(s) ? b.infusion.get(s) : (c.real ? c.infusion : ""), bonus: b.bonus.get(s),
                augs: b.augs.exists(s) ? [for (a in b.augs.get(s)) a.id] : []});
        }
        return {axes: e == null ? null : e.axes, dps: e == null ? 0 : e.dps, selfHeal: e == null ? 0 : e.selfHeal, allyHeal: e == null ? 0 : e.allyHeal,
            items: items, talents: [for (id => r in b.talents) if (r > 0) {id: id, rank: r}],
            skills: [for (id in b.skills) {id: id, runes: b.runes.exists(id) ? b.runes.get(id) : []}], arsenal: b.arsenal,
            weaponSkills: e == null ? null : [for (s => ids in e.weaponSkills) {slot: s, skills: ids}],
            perSkill: e == null ? null : [for (id => o in e.perSkill) {id: id, dmg: o.dmg, selfHeal: o.selfHeal, allyHeal: o.allyHeal}]};
    }

    static function settingsOf(cmd:Dynamic):State.Settings {
        var s = State.copy(State.settings);
        var p:Dynamic = Reflect.field(cmd, "priorities");
        if (Std.isOfType(p, Array) && (p : Array<Dynamic>).length == 4) s.priorities = [for (v in (p : Array<Dynamic>)) Std.int(v)];
        if (Reflect.hasField(cmd, "ranged")) s.ranged = Reflect.field(cmd, "ranged") == true;
        if (Reflect.hasField(cmd, "ideal")) s.ideal = Reflect.field(cmd, "ideal") == true;
        if (Reflect.hasField(cmd, "crit")) s.crit = Reflect.field(cmd, "crit") == true;
        if (Reflect.hasField(cmd, "critBoost")) Optimizer.CRIT_BOOST = Reflect.field(cmd, "critBoost");
        return s;
    }

    static function myHero():Dynamic {
        try return G.callStatic("GameApp", "getMyHero", []) catch (_:Dynamic) return null;
    }

    /** The 2D scene drawn into a texture (h2d.Scene.captureBitmap) and saved as a PNG (hxd.Pixels.toPNG). */
    static function screenshot(path:String):Void {
        var s2d = G.field(app, "s2d");
        if (s2d == null) throw "no 2D scene";
        var bmp = G.call("h2d.Scene", "captureBitmap", [s2d, null]);
        var tile = G.field(bmp, "tile");
        var tex = G.call("h2d.Tile", "getTexture", [tile]);
        var pixels = G.call("h3d.mat.Texture", "capturePixels", [tex, null, null, null]);
        var png = G.call("hxd.Pixels", "toPNG", [pixels, null]);
        G.callStatic("sys.io.File", "saveBytes", [path, png]);
        try G.call("h3d.mat.Texture", "dispose", [tex]) catch (_:Dynamic) {}
        DebugLog.line("test: screenshot " + path);
    }

    static function answer(o:Dynamic):Void {
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            Reflect.setField(o, "at", Date.now().toString());
            var text = haxe.Json.stringify(o, null, "  ");
            sys.io.File.saveContent(RESULT, text);
            DebugLog.line("test: answer " + (Reflect.field(o, "ok") == true ? "ok" : "FAILED " + Reflect.field(o, "error")) + " (" + Reflect.field(o, "id") + ")");
        } catch (e:Dynamic) DebugLog.error("test: answer", e);
        DebugLog.flush();
    }
}
