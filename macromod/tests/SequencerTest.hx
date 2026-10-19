import macromod.Edges;
import macromod.KeyIO;
import macromod.SkillIO;
import macromod.MacroDefs;
import macromod.Sequencer;

class FakeIO implements KeyIO {
    public var pressedCodes:Array<Int> = [];  // hotkeys that went down this frame
    public var heldCodes:Array<Int> = [];     // hotkeys currently held (also used for WASD movement in tests)
    public var t = 0.0;
    public function new() {}
    public function beginFrame(hotkeys:Array<Dynamic>):Void {}
    public function isPressed(b:Dynamic):Bool return pressedCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function isDown(b:Dynamic):Bool return heldCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function send(code:Int, down:Bool):Void {}
}

/** Like the real game: hotkeys are only "held" samples, presses come from Edges. */
class RealisticIO extends FakeIO {
    var edges = new Edges();
    public var downNow:Array<Int> = [];
    override public function beginFrame(hotkeys:Array<Dynamic>):Void {
        pressedCodes = [];
        for (b in hotkeys) {
            var code = MacroDefs.keyCode(b);
            if (code > 0 && edges.pressed(code, downNow.indexOf(code) >= 0, t) && pressedCodes.indexOf(code) < 0) pressedCodes.push(code);
        }
        heldCodes = downNow.copy();
    }
}

class FakeSkills implements SkillIO {
    public var log:Array<String> = [];
    public var t = 0.0;
    public var knownIds:Array<String> = []; // if non-empty, useSkill only "succeeds" for ids in here
    public function new() {}
    public var busy = false;
    public var busyMacros:Array<Int> = []; // only these macros are busy, when non-empty
    public function isBusy(macroIndex:Int):Bool return busy && (busyMacros.length == 0 || busyMacros.indexOf(macroIndex) >= 0);
    public function skillState(hero:Dynamic, skillId:String):Int return 1;
    public function wasUsed(macroIndex:Int):Bool return true;
    public function useSkill(macroIndex:Int, hero:Dynamic, skillId:String):Bool {
        if (knownIds.length > 0 && knownIds.indexOf(skillId) < 0) return false;
        log.push(Std.int(t * 1000) + " " + skillId);
        return true;
    }
}

class SequencerTest {
    static var failures = 0;
    static function check(name:String, cond:Bool, ?info:String):Void {
        if (!cond) { failures++; Sys.println("FAIL " + name + (info != null ? ": " + info : "")); }
        else Sys.println("ok   " + name);
    }

    static function def(hold:Bool, repeat:Bool, steps:Array<Array<Dynamic>>):Dynamic
        return {hotkey: 117, hold: hold, repeat: repeat, steps: [for (s in steps) {skillId: s[0], delay: s[1]}]};

    static function make(d:Dynamic):{io:FakeIO, skills:FakeSkills, seq:Sequencer} {
        var io = new FakeIO();
        var skills = new FakeSkills();
        var seq = new Sequencer(io, skills);
        seq.macros = [d];
        return {io: io, skills: skills, seq: seq};
    }

    /** Advance 16 ms frames; `pressAt` simulates one hotkey press edge. */
    static function run(c:{io:FakeIO, skills:FakeSkills, seq:Sequencer}, ms:Int, ?pressAt:Array<Int>, ?holdFrom:Int = -1, ?holdTo:Int = -1):Void {
        var frame = 0;
        var t = 0;
        while (t <= ms) {
            c.io.t = t / 1000; c.skills.t = t / 1000;
            c.io.pressedCodes = pressAt != null && pressAt.indexOf(frame) >= 0 ? [117] : [];
            c.io.heldCodes = c.io.pressedCodes.length > 0 || (holdFrom >= 0 && frame >= holdFrom && frame < holdTo) ? [117] : [];
            c.seq.update(t / 1000);
            frame++; t += 16;
        }
    }

    static function ids(skills:FakeSkills):Array<String> return [for (l in skills.log) l.split(" ")[1]];

    static function main():Void {
        // 1. Toggle, no repeat: skills activated in order, with the configured pauses.
        var c = make(def(false, false, [["fireball", 100], ["heal", 200], ["dash", 0]]));
        run(c, 1000, [1]);
        check("toggle once: skills in order", ids(c.skills).join(",") == "fireball,heal,dash", c.skills.log.join(","));
        check("toggle once: stops by itself", !c.seq.isRunning(0));

        // 2. Pause between activations is honoured (at least the configured delay, clamped to 60ms min).
        var a = Std.parseInt(c.skills.log[0].split(" ")[0]), b = Std.parseInt(c.skills.log[1].split(" ")[0]);
        check("pause fireball->heal >= 100ms", b - a >= 100, a + " -> " + b);

        // 3. Empty step in the middle is skipped, not a stop.
        c = make(def(false, false, [["fireball", 100], ["", 100], ["dash", 100]]));
        run(c, 600, [1]);
        check("empty step skipped", ids(c.skills).join(",") == "fireball,dash", c.skills.log.join(","));

        // 4. Toggle + repeat loops until pressed again.
        c = make(def(false, true, [["fireball", 100], ["heal", 100]]));
        run(c, 2000, [1, 100]);
        var got = ids(c.skills);
        check("repeat loops", got.length >= 6 && got[0] == "fireball" && got[1] == "heal" && got[2] == "fireball", got.join(","));
        check("second press stops", !c.seq.isRunning(0));

        // 5. Hold: runs while held, stops on release.
        c = make(def(true, true, [["fireball", 100]]));
        run(c, 1500, [1], 1, 40);
        check("hold: runs while held", ids(c.skills).length >= 4);
        check("hold: stops on release", !c.seq.isRunning(0));

        // 6. Hold without repeat: single pass.
        c = make(def(true, false, [["fireball", 100], ["heal", 100]]));
        run(c, 1500, [1], 1, 80);
        check("hold no repeat: one pass", ids(c.skills).join(",") == "fireball,heal", c.skills.log.join(","));

        // 7. Unbound hotkey / no steps never starts.
        var d0:Dynamic = def(false, false, [["fireball", 100]]);
        d0.hotkey = 0;
        c = make(d0);
        run(c, 500, [1]);
        check("unbound hotkey does nothing", c.skills.log.length == 0);
        c = make(def(false, false, [["", 100]]));
        run(c, 500, [1]);
        check("macro with no skills does nothing", c.skills.log.length == 0);

        // 8. Delay below the 60ms floor is clamped.
        c = make(def(false, false, [["fireball", 0], ["heal", 0]]));
        run(c, 400, [1]);
        var g = c.skills.log;
        check("delay 0 clamped to the 60ms floor", g.length == 2 && Std.parseInt(g[1].split(" ")[0]) - Std.parseInt(g[0].split(" ")[0]) >= 60, g.join(","));

        // 9. Two macros run in parallel, independently.
        var io = new FakeIO(); var fakeSkills = new FakeSkills();
        var seq = new Sequencer(io, fakeSkills);
        var first:Dynamic = def(false, true, [["fireball", 100], ["heal", 100]]);
        var second:Dynamic = def(false, true, [["dash", 100], ["shield", 100]]);
        second.hotkey = 118;
        seq.macros = [first, second];
        var frame = 0, tm = 0;
        while (tm <= 1500) {
            io.t = tm / 1000; fakeSkills.t = tm / 1000;
            io.pressedCodes = frame == 1 ? [117, 118] : [];
            io.heldCodes = [];
            seq.update(tm / 1000);
            frame++; tm += 16;
        }
        var got2 = ids(fakeSkills);
        check("two macros: both run", got2.indexOf("fireball") >= 0 && got2.indexOf("dash") >= 0, got2.join(","));
        check("two macros: both running", seq.isRunning(0) && seq.isRunning(1));

        // 10. A skill id the game doesn't currently recognise (useSkill returns false) is simply
        // not logged, but the macro keeps advancing to its next step rather than getting stuck.
        var io4 = new FakeIO(); var skills4 = new FakeSkills(); skills4.knownIds = ["heal"];
        var seq4 = new Sequencer(io4, skills4);
        seq4.macros = [def(false, false, [["notEquipped", 100], ["heal", 100]])];
        var t4 = 0;
        io4.t = 0; skills4.t = 0; io4.pressedCodes = [117]; seq4.update(0); io4.pressedCodes = [];
        t4 = 16;
        while (t4 <= 400) { io4.t = t4 / 1000; skills4.t = t4 / 1000; seq4.update(t4 / 1000); t4 += 16; }
        check("an unrecognised skill id doesn't block later steps", ids(skills4).join(",") == "heal", skills4.log.join(","));

        // 11. pauseWhileMoving: no skill is activated while a movement key (W/A/S/D) is held,
        // but the macro keeps running and resumes exactly where it left off once movement stops.
        var io2 = new FakeIO(); var skills2 = new FakeSkills();
        var seq2 = new Sequencer(io2, skills2);
        seq2.pauseWhileMoving = true;
        seq2.macros = [def(false, true, [["fireball", 100], ["heal", 100]])];
        var t2 = 0;
        io2.pressedCodes = [117]; io2.heldCodes = [87]; io2.t = 0; skills2.t = 0; seq2.update(0); io2.pressedCodes = [];
        t2 = 16;
        while (t2 <= 300) { io2.t = t2 / 1000; skills2.t = t2 / 1000; io2.heldCodes = [87]; seq2.update(t2 / 1000); t2 += 16; } // W held: moving
        check("pauseWhileMoving: nothing activated while moving", skills2.log.length == 0, skills2.log.join(","));
        check("pauseWhileMoving: macro is still running, just paused", seq2.isRunning(0));
        while (t2 <= 600) { io2.t = t2 / 1000; skills2.t = t2 / 1000; io2.heldCodes = []; seq2.update(t2 / 1000); t2 += 16; } // released: not moving
        check("pauseWhileMoving: resumes once movement stops", skills2.log.length > 0, skills2.log.join(","));

        // 12. pauseWhileMoving off (default): movement doesn't affect the macro at all.
        var io3 = new FakeIO(); var skills3 = new FakeSkills();
        var seq3 = new Sequencer(io3, skills3);
        seq3.macros = [def(false, true, [["fireball", 100]])];
        io3.pressedCodes = [117]; io3.t = 0; skills3.t = 0; seq3.update(0); io3.pressedCodes = [];
        var t3 = 16;
        while (t3 <= 300) { io3.t = t3 / 1000; skills3.t = t3 / 1000; io3.heldCodes = [87]; seq3.update(t3 / 1000); t3 += 16; }
        check("pauseWhileMoving off: macro fires normally while moving", skills3.log.length > 0, skills3.log.join(","));

        // 13. The game still holds the previous request: the next step waits instead of replacing it.
        var c13 = make(def(false, false, [["fireball", 100], ["heal", 100]]));
        c13.skills.busy = true;
        run(c13, 7000, [0]);
        check("busy: next step waits for the queued skill", ids(c13.skills).join(",") == "fireball,heal", c13.skills.log.join(","));
        var healAt = Std.parseInt(c13.skills.log[1].split(" ")[0]);
        check("busy: waits up to the cap, not forever", healAt >= Std.int(Sequencer.MAX_QUEUE_WAIT * 1000) - 20 && healAt <= Std.int(Sequencer.MAX_QUEUE_WAIT * 1000) + 40, c13.skills.log.join(","));

        // 14. Request used right away: no extra wait beyond the step delay.
        var c14 = make(def(false, false, [["fireball", 100], ["heal", 100]]));
        run(c14, 400, [0]);
        var heal14 = Std.parseInt(c14.skills.log[1].split(" ")[0]);
        check("not busy: next step after its delay", heal14 >= 100 && heal14 <= 130, c14.skills.log.join(","));

        // 15. Macros are independent: macro 1 waiting for its skill doesn't hold up macro 2.
        var io15 = new FakeIO(); var skills15 = new FakeSkills();
        var seq15 = new Sequencer(io15, skills15);
        var m1:Dynamic = {hotkey: 117, hold: false, repeat: false, steps: [{skillId: "a1", delay: 100}, {skillId: "a2", delay: 100}]};
        var m2:Dynamic = {hotkey: 118, hold: false, repeat: false, steps: [{skillId: "b1", delay: 100}, {skillId: "b2", delay: 100}]};
        seq15.macros = [m1, m2];
        skills15.busy = true; skills15.busyMacros = [0];
        var t15 = 0;
        while (t15 <= 400) {
            io15.t = t15 / 1000; skills15.t = t15 / 1000;
            io15.pressedCodes = t15 == 0 ? [117, 118] : [];
            seq15.update(t15 / 1000);
            t15 += 16;
        }
        var got15 = ids(skills15);
        check("independent: macro 2 runs all its steps while macro 1 waits",
            got15.indexOf("b1") >= 0 && got15.indexOf("b2") >= 0 && got15.indexOf("a2") < 0, got15.join(","));

        // Combat only: the hotkey works out of combat, but the macro plays only in combat,
        // waits when combat ends and plays again from step 1 in the next fight.
        c = make(def(false, true, [["fireball", 100], ["heal", 100]]));
        c.seq.combatOnly = true;
        run(c, 300, [1]);
        check("combat only: hotkey starts the macro out of combat", c.seq.isRunning(0));
        check("combat only: nothing played out of combat", c.skills.log.length == 0, c.skills.log.join(","));
        c.seq.inCombat = true;
        run(c, 150);
        check("combat only: plays once combat starts", ids(c.skills).join(",") == "fireball,heal", c.skills.log.join(","));
        c.seq.inCombat = false;
        var before = c.skills.log.length;
        run(c, 300);
        check("combat only: out of combat it waits, not stops", c.seq.isRunning(0) && c.skills.log.length == before, c.skills.log.join(","));
        c.seq.inCombat = true;
        run(c, 50);
        check("combat only: next fight plays from step 1", ids(c.skills)[before] == "fireball", c.skills.log.join(","));
        c.seq.inCombat = false;
        run(c, 300, [1]);
        check("combat only: hotkey stops it out of combat", !c.seq.isRunning(0));
        c.seq.inCombat = true;
        before = c.skills.log.length;
        run(c, 300);
        check("combat only: stopped macro stays stopped in combat", c.skills.log.length == before, c.skills.log.join(","));
        c = make(def(false, false, [["fireball", 100]]));
        run(c, 300, [1]);
        check("combat only off: works out of combat", ids(c.skills).join(",") == "fireball", c.skills.log.join(","));

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
