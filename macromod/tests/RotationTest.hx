import macromod.KeyIO;
import macromod.MacroDefs;
import macromod.RotationSequencer;
import macromod.Rotations;
import macromod.SkillIO;
import macromod.SkillIO.Readiness;

class KeysFake implements KeyIO {
    public var pressedCodes:Array<Int> = [];
    public var heldCodes:Array<Int> = [];
    public function new() {}
    public function beginFrame(hotkeys:Array<Dynamic>):Void {}
    public function isPressed(b:Dynamic):Bool return pressedCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function isDown(b:Dynamic):Bool return heldCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function send(code:Int, down:Bool):Void {}
}

/** A game with cooldowns: a skill is used when it is ready, then it is on cooldown for its length. */
class GameFake implements SkillIO {
    public var t = 0.0;
    public var cooldown:Map<String, Float> = new Map();
    public var readyAt:Map<String, Float> = new Map();
    public var missing:Array<String> = [];
    public var ignoring:Array<String> = []; // requests for these are dropped (no target, queue expired...)
    public var log:Array<String> = [];
    public var busyUntil = 0.0;
    public var castTime = 0.0;
    public function new() {}
    public function isBusy(macroIndex:Int):Bool return t < busyUntil;
    public function skillState(hero:Dynamic, id:String):Int {
        if (missing.indexOf(id) >= 0) return Readiness.MISSING;
        return t >= (readyAt.exists(id) ? readyAt.get(id) : 0) ? Readiness.READY : Readiness.WAITING;
    }
    public function useSkill(macroIndex:Int, hero:Dynamic, id:String):Bool {
        if (ignoring.indexOf(id) >= 0) { busyUntil = t + 0.1; return true; } // queued for a moment, then dropped
        if (skillState(hero, id) != Readiness.READY) return false;
        readyAt.set(id, t + (cooldown.exists(id) ? cooldown.get(id) : 1.0));
        busyUntil = t + castTime;
        log.push(Std.int(Math.round(t * 1000)) + " " + id);
        return true;
    }
}

class RotationTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function make(slots:Array<String>, repeat:Bool, hold:Bool = false) {
        var io = new KeysFake();
        var game = new GameFake();
        var seq = new RotationSequencer(io, game);
        var r = Rotations.create();
        r.hotkey = 117;
        r.repeat = repeat;
        r.hold = hold;
        for (i in 0...slots.length) r.slots[i] = slots[i];
        seq.set([r]);
        return {io: io, game: game, seq: seq};
    }

    /** Runs 16 ms frames up to `ms`; the hotkey is pressed on the frames in `press`, held on [holdFrom, holdTo). */
    static function run(c:{io:KeysFake, game:GameFake, seq:RotationSequencer}, ms:Int, ?press:Array<Int>, holdFrom:Int = -1, holdTo:Int = -1):Void {
        var frame = 0, t = 0;
        while (t <= ms) {
            c.game.t = t / 1000;
            c.io.pressedCodes = press != null && press.indexOf(frame) >= 0 ? [117] : [];
            c.io.heldCodes = c.io.pressedCodes.length > 0 || (frame >= holdFrom && frame < holdTo) ? [117] : [];
            c.seq.update(t / 1000);
            frame++; t += 16;
        }
    }

    static function ids(game:GameFake):String return [for (l in game.log) l.split(" ")[1]].join(",");
    static function at(game:GameFake, i:Int):Int return Std.parseInt(game.log[i].split(" ")[0]);

    static function main():Void {
        // 1. Skills go in turn; a skill on cooldown holds the next one back, even if that one is ready.
        var c = make(["a", "b", "c"], true);
        c.game.cooldown.set("a", 1.0); c.game.cooldown.set("b", 3.0); c.game.cooldown.set("c", 0.5);
        run(c, 9000, [1]);
        check("in turn: a b c a b c", ids(c.game).indexOf("a,b,c,a,b,c") == 0, c.game.log.join(","));
        check("first round without waiting", at(c.game, 2) < 300, c.game.log.join(","));
        check("second a waits for its cooldown", at(c.game, 3) >= 1000 && at(c.game, 3) < 1100, c.game.log.join(","));
        check("second b waits for its cooldown (c stays behind b)", at(c.game, 4) >= 3000 && at(c.game, 4) < 3200 && at(c.game, 5) > at(c.game, 4), c.game.log.join(","));

        // 2. Without "repeat" the rotation plays once and stops by itself.
        c = make(["a", "b"], false);
        run(c, 5000, [1]);
        check("once: a b then stop", ids(c.game) == "a,b" && !c.seq.isRunning(0), c.game.log.join(","));

        // 3. A skill still on cooldown at the end of the pass is waited for, then the rotation stops.
        c = make(["a", "b", "a"], false);
        c.game.cooldown.set("a", 2.0);
        run(c, 6000, [1]);
        check("once: the repeated skill waits for its cooldown", ids(c.game) == "a,b,a" && at(c.game, 2) >= 2000, c.game.log.join(","));

        // 4. Empty cells and skills the hero lacks are skipped.
        c = make(["", "a", "", "gone", "b", ""], false);
        c.game.missing = ["gone"];
        run(c, 2000, [1]);
        check("empty and missing cells skipped", ids(c.game) == "a,b", c.game.log.join(","));

        // 5. Toggle: the second press stops it; a second start begins at the first cell.
        c = make(["a", "b"], true);
        c.game.cooldown.set("a", 0.3); c.game.cooldown.set("b", 0.3);
        run(c, 800, [1, 40]);
        var n = c.game.log.length;
        check("toggle: second press stops", !c.seq.isRunning(0) && n >= 2, c.game.log.join(","));
        c.game.readyAt = new Map(); // the second run counts time from 0 again
        run(c, 800, [1]);
        check("toggle: restarts from the first cell", c.game.log.length > n && c.game.log[n].split(" ")[1] == "a", c.game.log.join(","));

        // 6. Hold: runs while held, stops on release, and does not restart while still held.
        c = make(["a"], true, true);
        c.game.cooldown.set("a", 0.2);
        run(c, 1500, [1], 1, 50);
        check("hold: runs while held", c.game.log.length >= 3, c.game.log.join(","));
        check("hold: stops on release", !c.seq.isRunning(0));
        c = make(["a", "b"], false, true);
        c.game.cooldown.set("a", 0.1); c.game.cooldown.set("b", 0.1);
        run(c, 1500, [1], 1, 90);
        check("hold, no repeat: one pass only while held", ids(c.game) == "a,b" && !c.seq.isRunning(0), c.game.log.join(","));

        // 7. A request the game drops is repeated once, then the skill is skipped and the rotation goes on.
        c = make(["a", "b"], false);
        c.game.ignoring = ["a"];
        run(c, 3000, [1]);
        check("dropped request: skipped after two tries", ids(c.game) == "b" && !c.seq.isRunning(0), c.game.log.join(","));

        // 8. A cast in progress holds the next skill back.
        c = make(["a", "b"], false);
        c.game.castTime = 0.5;
        run(c, 3000, [1]);
        check("cast: next skill after the cast", ids(c.game) == "a,b" && at(c.game, 1) - at(c.game, 0) >= 500, c.game.log.join(","));

        // 9. Nothing usable: the rotation never starts / stops at once.
        c = make(["", ""], true);
        run(c, 500, [1]);
        check("no skills: does not start", !c.seq.isRunning(0));
        c = make(["gone"], true);
        c.game.missing = ["gone"];
        run(c, 500, [1]);
        check("all skills missing: stops", !c.seq.isRunning(0) && c.game.log.length == 0);

        // 10. Unbound key: only startNow starts it.
        c = make(["a"], false);
        c.seq.hotkeys();
        var r0 = Rotations.create(); r0.slots[0] = "a";
        c.seq.set([r0]);
        run(c, 300, [1]);
        check("no key: a press starts nothing", c.game.log.length == 0);

        // 11. Combat only / not while running follow the macro settings.
        c = make(["a", "b"], false);
        c.seq.combatOnly = true;
        run(c, 300, [1]);
        check("combat only: waits out of combat", c.seq.isRunning(0) && c.game.log.length == 0);
        c.seq.inCombat = true;
        run(c, 300);
        check("combat only: plays in combat", ids(c.game) == "a,b", c.game.log.join(","));
        c = make(["a"], false);
        c.seq.pauseWhileMoving = true;
        c.io.heldCodes = [87];
        c.seq.startNow(0, 0);
        c.game.t = 0.5;
        c.seq.update(0.5);
        check("not while running: waits while W is held", c.game.log.length == 0 && c.seq.isRunning(0));

        // 12. suspended (a key is being chosen): hotkeys do nothing.
        c = make(["a"], false);
        c.seq.suspended = true;
        run(c, 300, [1]);
        check("suspended: hotkey ignored", !c.seq.isRunning(0) && c.game.log.length == 0);

        // 13. Rotations: keys are unique among rotations and macros.
        var list = [Rotations.create(), Rotations.create(), Rotations.create()];
        list[0].hotkey = 117;
        list[1].hotkey = {code: 49, modifier: 0};
        check("key taken by another rotation", Rotations.owner(list, 2, 117, []) != null && Rotations.owner(list, 2, 117, []).number == 1);
        check("a rotation may keep its own key", Rotations.owner(list, 0, 117, []) == null);
        check("Ctrl+1 is not 1", Rotations.owner(list, 2, 49, []) == null && Rotations.owner(list, 2, {code: 49, modifier: 0}, []).number == 2);
        check("Shift+1 is not Ctrl+1", Rotations.owner(list, 2, {code: 49, modifier: 1}, []) == null);
        var byMacro = Rotations.owner(list, 2, 120, [0, 120, {code: 121, modifier: 2}]);
        check("key taken by a macro", byMacro != null && byMacro.isMacro && byMacro.number == 2);
        check("unset key never conflicts", Rotations.owner(list, 2, 0, [0]) == null);

        // 14. Saving: round trip, damaged data.
        list[0].slots[3] = "FireBolt"; list[0].repeat = true; list[1].hold = true;
        var back = Rotations.parse(Rotations.serialize(list));
        check("saved rotations read back", back.length == 3 && back[0].slots[3] == "FireBolt" && back[0].repeat && back[1].hold
            && Rotations.signature(back[1].hotkey) == "49+0" && Rotations.signature(back[0].hotkey) == "117" && back[0].slots.length == Rotations.SLOTS);
        check("garbage gives an empty list", Rotations.parse("not json").length == 0 && Rotations.parse("{}").length == 0);
        var odd = Rotations.parse('[{"slots":["a",5,"b"],"hotkey":"x","repeat":1},null]');
        check("odd data gets defaults", odd.length == 2 && odd[0].slots[0] == "a" && odd[0].slots[1] == "" && odd[0].slots[2] == "b"
            && odd[0].slots.length == Rotations.SLOTS && MacroDefs.keyCode(odd[0].hotkey) == 0 && !odd[0].repeat && odd[1].slots.length == Rotations.SLOTS);

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
