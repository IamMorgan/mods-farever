package macromod;

import macromod.Rotations.RotationData;
import macromod.SkillIO.Readiness;

private class Runner {
    public var running = false;
    public var next = 0;         // cell of the skill to use next
    public var attempts = 0;     // requests made for that cell
    public var awaiting = false; // the skill was requested; its use is not confirmed yet
    public var nextAt = 0.0;
    public var busyUntil = 0.0;  // longest wait for the game to use the requested skill
    public var waitingForCombat = false;
    public function new() {}
}

/**
 * Plays the rotations of the rotation window. Like a macro it starts from a hotkey, in Toggle or Hold
 * mode, but it has no delays: the skills are used in turn, each one the moment it is ready. A skill on
 * cooldown holds the rotation back (the next skill is not used before it), and the rotation goes on
 * only once the game has used that skill. Empty cells and skills the hero does not have are skipped.
 */
class RotationSequencer {
    /** A skill that is still ready after this many requests (queue expired, no target...) is skipped. */
    public static inline var MAX_ATTEMPTS = 2;

    static inline var MOVE_FORWARD = 87; // W
    static inline var MOVE_LEFT = 65;    // A
    static inline var MOVE_BACK = 83;    // S
    static inline var MOVE_RIGHT = 68;   // D

    var runners:Array<Runner> = [];
    var rotations:Array<RotationData> = [];
    var io:KeyIO;
    var skills:SkillIO;

    /** Same meaning as in Sequencer; the mod keeps them in step with the macro settings. */
    public var pauseWhileMoving = false;
    public var combatOnly = false;
    public var inCombat = false;
    public var hero:Dynamic;
    /** True while a key is being chosen in the window: hotkeys do nothing. */
    public var suspended = false;
    /** Called when a skill is requested (rotation number from 0, cell from 0, skill); for tests and logs. */
    public var onUse:(rotation:Int, cell:Int, skill:String) -> Void;

    public function new(io:KeyIO, skills:SkillIO) { this.io = io; this.skills = skills; }

    public function set(list:Array<RotationData>):Void {
        rotations = list;
        runners = [for (_ in list) new Runner()];
    }

    public function isRunning(index:Int):Bool return index < runners.length && runners[index].running;

    public function hotkeys():Array<Dynamic> return [for (r in rotations) r.hotkey];

    public function stopAll():Void for (r in runners) r.running = false;

    /** Starts rotation `index` as its hotkey does. */
    public function startNow(index:Int, now:Float):Void if (index < rotations.length) start(rotations[index], runners[index], now);

    public function stopNow(index:Int):Void if (index < runners.length) runners[index].running = false;

    public function update(now:Float):Void {
        for (i in 0...rotations.length) tick(i, rotations[i], runners[i], now);
    }

    function isMoving():Bool return io.isDown(MOVE_FORWARD) || io.isDown(MOVE_LEFT) || io.isDown(MOVE_BACK) || io.isDown(MOVE_RIGHT);

    function start(def:RotationData, runner:Runner, now:Float):Void {
        if (!Rotations.hasSkills(def)) return;
        runner.running = true;
        runner.waitingForCombat = false;
        runner.awaiting = false;
        runner.attempts = 0;
        runner.next = 0;
        runner.nextAt = now;
    }

    function tick(index:Int, def:RotationData, runner:Runner, now:Float):Void {
        if (!suspended && MacroDefs.keyCode(def.hotkey) != 0) {
            if (def.hold) {
                if (!runner.running && io.isPressed(def.hotkey)) start(def, runner, now);
                else if (runner.running && !io.isDown(def.hotkey)) runner.running = false;
            } else if (io.isPressed(def.hotkey)) {
                if (runner.running) runner.running = false; else start(def, runner, now);
            }
        }
        if (!runner.running) return;
        if (combatOnly && !inCombat) { runner.waitingForCombat = true; return; }
        if (runner.waitingForCombat) {
            runner.waitingForCombat = false;
            runner.awaiting = false;
            runner.attempts = 0;
            runner.next = 0;
            runner.nextAt = now;
        }
        if (now < runner.nextAt || (pauseWhileMoving && isMoving())) return;
        // The skill used last is not finished (request queued, aiming, casting): the next one would cut it off.
        var slot = MacroDefs.MACROS + index; // the skill layer keeps one progress per macro and rotation
        if (skills.isBusy(slot) && now < runner.busyUntil) return;
        play(index, def, runner, slot, now);
    }

    function play(index:Int, def:RotationData, runner:Runner, slot:Int, now:Float):Void {
        if (runner.awaiting) {
            runner.awaiting = false;
            // Still ready after the request: it was not used (queue expired); ask again, then give up on it.
            if (skills.skillState(hero, def.slots[runner.next]) == Readiness.READY && runner.attempts < MAX_ATTEMPTS) {
                // fall through: request it again
            } else {
                runner.next++;
                runner.attempts = 0;
                runner.nextAt = now + Sequencer.MIN_GAP_MS / 1000;
                return;
            }
        }
        var checked = 0;
        while (checked++ <= def.slots.length * 2 + 2) {
            while (runner.next < def.slots.length && def.slots[runner.next] == "") runner.next++;
            if (runner.next >= def.slots.length) {
                if (!def.repeat) { runner.running = false; return; }
                runner.next = 0;
                runner.attempts = 0;
                continue;
            }
            var skill = def.slots[runner.next];
            var state = skills.skillState(hero, skill);
            if (state == Readiness.MISSING) { runner.next++; runner.attempts = 0; continue; }
            if (state == Readiness.WAITING) return; // the rotation waits for this skill
            try skills.useSkill(slot, hero, skill) catch (_:Dynamic) {}
            if (onUse != null) onUse(index, runner.next, skill);
            runner.awaiting = true;
            runner.attempts++;
            runner.busyUntil = now + Sequencer.MAX_QUEUE_WAIT;
            runner.nextAt = now + Sequencer.MIN_GAP_MS / 1000;
            return;
        }
        runner.running = false; // nothing in the rotation can be used (all cells missing)
    }
}
