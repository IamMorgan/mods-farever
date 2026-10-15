package macromod;

import macromod.MacroDefs;

private class Runner {
    public var index:Int;
    public var running = false;
    public var next = 0;        // index of the next step to activate
    public var nextAt = 0.0;    // when to activate it
    public var busyUntil = 0.0; // longest wait for the game to use the previous step's skill
    public function new(index:Int) this.index = index;
}

/** Runs macros from update(): no timers, so it works inside the game's own loop. */
class Sequencer {
    /** Shortest allowed gap between two skill activations. */
    public static inline var MIN_GAP_MS = 60;
    /** Longest a step waits for the previous one to finish (request still queued, aiming not
        confirmed, skill still casting) before it goes ahead anyway. */
    public static inline var MAX_QUEUE_WAIT = 6.0;

    // Standard WASD movement keys. There's no confirmed "is the character moving" game field,
    // so this checks the keys themselves - works for the default bindings; a player who has
    // remapped movement to different keys won't be covered by this.
    static inline var MOVE_FORWARD = 87; // W
    static inline var MOVE_LEFT = 65;    // A
    static inline var MOVE_BACK = 83;    // S
    static inline var MOVE_RIGHT = 68;   // D

    var runners:Array<Runner> = [for (i in 0...MacroDefs.MACROS) new Runner(i)];
    public var macros:Array<MacroDef> = [];
    /** When true, no macro step fires while the character is moving (any WASD key held);
        already-running macros simply pause and resume once movement stops. */
    public var pauseWhileMoving = false;
    /** Updated by the mod every frame; which hero a step's skill is activated on. */
    public var hero:Dynamic;
    var io:KeyIO;      // activation hotkeys only: steps use skills, they don't simulate key presses
    var skills:SkillIO;

    public function new(io:KeyIO, skills:SkillIO) { this.io = io; this.skills = skills; }

    public function isRunning(index:Int):Bool return runners[index].running;

    public function update(now:Float):Void {
        io.beginFrame([for (def in macros) def.hotkey]);
        for (i in 0...macros.length) tick(i, macros[i], runners[i], now);
    }

    function tick(index:Int, def:MacroDef, runner:Runner, now:Float):Void {
        var bound = MacroDefs.keyCode(def.hotkey) != 0;
        if (bound) {
            if (def.hold) {
                if (!runner.running && io.isPressed(def.hotkey)) start(def, runner, now);
                else if (runner.running && !io.isDown(def.hotkey)) stop(runner);
            } else if (io.isPressed(def.hotkey)) {
                if (runner.running) stop(runner); else start(def, runner, now);
            }
        }
        if (!runner.running || now < runner.nextAt || (pauseWhileMoving && isMoving())) return;
        // The previous step isn't finished (queued, aiming, casting): a new request would cut it off.
        if (skills.isBusy(runner.index) && now < runner.busyUntil) return;
        fire(def, runner, now);
    }

    function isMoving():Bool return io.isDown(MOVE_FORWARD) || io.isDown(MOVE_LEFT) || io.isDown(MOVE_BACK) || io.isDown(MOVE_RIGHT);

    function start(def:MacroDef, runner:Runner, now:Float):Void {
        if (!hasSkills(def)) return;
        runner.running = true;
        runner.next = 0;
        runner.nextAt = now;
    }

    function stop(runner:Runner):Void runner.running = false;

    public function stopAll():Void for (runner in runners) stop(runner);

    static function hasSkills(def:MacroDef):Bool {
        for (step in def.steps) if (step.skillId != "") return true;
        return false;
    }

    function fire(def:MacroDef, runner:Runner, now:Float):Void {
        // Empty steps are skipped instead of ending the def.
        var index = runner.next;
        while (index < def.steps.length && def.steps[index].skillId == "") index++;
        if (index >= def.steps.length) {
            if (!def.repeat || !hasSkills(def)) { stop(runner); return; }
            index = 0;
            while (def.steps[index].skillId == "") index++;
        }
        var step = def.steps[index];
        try skills.useSkill(runner.index, hero, step.skillId) catch (_:Dynamic) {}
        runner.next = index + 1;
        runner.busyUntil = now + MAX_QUEUE_WAIT;
        runner.nextAt = now + Math.max(step.delay, MIN_GAP_MS) / 1000;
    }
}
