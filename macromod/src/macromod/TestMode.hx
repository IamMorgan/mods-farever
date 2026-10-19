package macromod;

import macromod.GameAccess as G;
import macromod.SkillIO.Readiness;

/**
 * Test mode: the assistant drives the rotations in the running game through files. It is on only while the
 * folder hlx/config/macromod/test exists (the archive does not contain it), so the shipped mod never looks
 * for commands.
 *
 * A command is written to hlx/config/macromod/test/command.json ({"id": "...", "cmd": "...", ...}); the mod takes
 * it (the file is removed), runs it and writes the answer to result.json ({"id", "ok", "cmd", ...}).
 *
 * Commands:
 *  - status: the rotation window, the rotations (cells, key, running), the hero, the combat state.
 *  - skills: the skills on the bars, each with the state the rotation sees (missing / ready / waiting) and its cooldown.
 *  - open / close: the rotation window. add {slots: [kinds], repeat, hold, hotkey}: a new rotation on top of the list (as "New" does).
 *  - setkey {index, code, modifier}: the activation key of rotation `index` (from 0) through the window's own rule (a taken key is refused).
 *  - remove {index} / clearall: delete a rotation / all of them. start {index} / stop {index}: start / stop a rotation as its hotkey does.
 *  - log {clear}: what the rotations requested so far (time in seconds since the first request, rotation, cell, skill).
 *  - screenshot {file}: the game's 2D scene saved as a PNG in the test folder.
 */
class TestMode {
    public static inline var DIR = "hlx/config/macromod/test";
    static inline var COMMAND = DIR + "/command.json";
    static inline var RESULT = DIR + "/result.json";

    static var nextCheck = 0.0;
    static var app:Dynamic;
    static var hooked = false;
    static var log:Array<Dynamic> = [];
    static var t0 = -1.0;

    /** Each frame (GameApp.update): looks for a command twice a second, while the test folder exists. */
    public static function tick(gameApp:Dynamic):Void {
        app = gameApp;
        var now = haxe.Timer.stamp();
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        if (!sys.FileSystem.exists(DIR)) return;
        if (!hooked) {
            hooked = true;
            MacroMod.rotationSeq.onUse = (rotation, cell, skill) -> {
                var at = haxe.Timer.stamp();
                if (t0 < 0) t0 = at;
                log.push({t: Math.round((at - t0) * 1000) / 1000, rotation: rotation, cell: cell, skill: skill});
            };
        }
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
        try run(cmd, id, name, now) catch (e:Dynamic) answer({id: id, cmd: name, ok: false, error: Std.string(e)});
    }

    static function status():Dynamic {
        var hero = GameSkills.localHero();
        return {
            window: MacroMod.rotationWindow.isOpen(), capturing: MacroMod.rotationWindow.isCapturing(), russian: MacroMod.russian,
            heroKnown: hero != null, inCombat: hero != null && G.field(hero, "isInCombat") == true,
            rotations: [for (i in 0...MacroMod.rotations.length) {
                var r = MacroMod.rotations[i];
                {index: i, key: r.hotkey, hold: r.hold, repeat: r.repeat, slots: r.slots, running: MacroMod.rotationSeq.isRunning(i)};
            }]
        };
    }

    static function skillList():Dynamic {
        var hero = GameSkills.localHero();
        var out:Array<Dynamic> = [];
        for (e in MacroMod.skills.hotbar) {
            var cooldown = -1.0;
            try cooldown = G.number(G.call("st.skill.Skill", "getCooldownLeft", e.skill), -1) catch (_:Dynamic) {}
            out.push({kind: e.kind, name: e.name, input: e.input, weapon: e.weapon, cooldownLeft: cooldown,
                state: stateName(MacroMod.skills.skillState(hero, e.kind))});
        }
        return out;
    }

    static function stateName(state:Int):String
        return state == Readiness.READY ? "ready" : state == Readiness.WAITING ? "waiting" : "missing";

    static function run(cmd:Dynamic, id:String, name:String, now:Float):Void {
        var index:Int = Reflect.field(cmd, "index") != null ? Std.int(Reflect.field(cmd, "index")) : 0;
        var reply = (extra:Dynamic) -> {
            Reflect.setField(extra, "id", id);
            Reflect.setField(extra, "cmd", name);
            Reflect.setField(extra, "ok", true);
            Reflect.setField(extra, "status", status());
            answer(extra);
        };
        switch (name) {
            case "status":
                reply({});
            case "skills":
                reply({skills: skillList()});
            case "open":
                MacroMod.rotationWindow.hide();
                var shown = MacroMod.showRotations();
                reply({shown: shown});
            case "close":
                MacroMod.closeRotations();
                reply({});
            case "add":
                MacroMod.rotations.unshift(Rotations.normalize(cmd));
                afterChange();
                reply({});
            case "setkey":
                var code:Int = Std.int(Reflect.field(cmd, "code"));
                var modifier:Dynamic = Reflect.field(cmd, "modifier");
                var binding:Dynamic = Std.isOfType(modifier, Int) ? {code: code, modifier: modifier} : code;
                var before = MacroMod.rotations[index].hotkey;
                MacroMod.rotationWindow.setKey(index, binding);
                reply({accepted: Rotations.signature(MacroMod.rotations[index].hotkey) == Rotations.signature(binding), before: before});
            case "remove":
                if (index < MacroMod.rotations.length) MacroMod.rotations.splice(index, 1);
                afterChange();
                reply({});
            case "clearall":
                MacroMod.rotations.splice(0, MacroMod.rotations.length);
                afterChange();
                reply({});
            case "start":
                MacroMod.rotationSeq.startNow(index, now);
                reply({});
            case "stop":
                MacroMod.rotationSeq.stopNow(index);
                reply({});
            case "log":
                var copy = log.copy();
                if (Reflect.field(cmd, "clear") == true) { log = []; t0 = -1; }
                reply({log: copy});
            case "screenshot":
                var file = Reflect.field(cmd, "file") != null ? Std.string(Reflect.field(cmd, "file")) : "screen.png";
                screenshot(DIR + "/" + file);
                reply({file: DIR + "/" + file});
            default:
                answer({id: id, cmd: name, ok: false, error: "unknown command"});
        }
    }

    /** The list was changed from outside the window: save it, restart the sequencer, redraw an open window. */
    static function afterChange():Void {
        Rotations.save(MacroMod.rotations);
        MacroMod.rotationSeq.set(MacroMod.rotations);
        if (MacroMod.rotationWindow.isOpen()) MacroMod.showRotations();
    }

    static function screenshot(path:String):Void {
        var s2d = G.field(app, "s2d");
        if (s2d == null) throw "no 2D scene";
        var bmp = G.call("h2d.Scene", "captureBitmap", s2d, [null]);
        var tile = G.field(bmp, "tile");
        var tex = G.call("h2d.Tile", "getTexture", tile, []);
        var pixels = G.call("h3d.mat.Texture", "capturePixels", tex, [null, null, null]);
        var png = G.call("hxd.Pixels", "toPNG", pixels, [null]);
        G.staticCall("sys.io.File", "saveBytes", [path, png]);
        try G.call("h3d.mat.Texture", "dispose", tex, []) catch (_:Dynamic) {}
    }

    static function answer(o:Dynamic):Void {
        try {
            Reflect.setField(o, "at", Date.now().toString());
            sys.io.File.saveContent(RESULT, haxe.Json.stringify(o, null, "  "));
        } catch (_:Dynamic) {}
    }
}
