package macromod;

import macromod.MacroDefs;

private class Runner {
    public var index:Int;
    public var running = false;
    public var next = 0;        // index of the next step to press
    public var nextAt = 0.0;    // when to press it
    public var down = 0;        // key currently held by the macro (0 = none)
    public var releaseAt = 0.0;
    public var downFrame = 0;   // update() number in which the key went down
    public function new(index:Int) this.index = index;
}

/** Runs macros from update(): no timers, so it works inside the game's own loop. */
class Sequencer {
    /** How long an injected key stays down. Must span at least one game frame. */
    public static inline var TAP_SECONDS = 0.045;
    /** Shortest allowed gap between two presses. */
    public static inline var MIN_GAP_MS = 60;

    var runners:Array<Runner> = [for (i in 0...MacroDefs.MACROS) new Runner(i)];
    var sentDownThisTick = false;
    var frame = 0;
    public var macros:Array<MacroDef> = [];
    var io:KeyIO;

    public function new(io:KeyIO) this.io = io;

    public function isRunning(index:Int):Bool return runners[index].running;

    public function update(now:Float):Void {
        frame++;
        io.beginFrame([for (def in macros) def.hotkey]);
        sentDownThisTick = false;
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
        // Keep the key down for at least one full game update, even if the game runs at a low frame rate.
        if (runner.down != 0 && now >= runner.releaseAt && frame > runner.downFrame) release(runner);
        if (runner.running && now >= runner.nextAt) fire(def, runner, now);
    }

    function start(def:MacroDef, runner:Runner, now:Float):Void {
        if (!hasKeys(def)) return;
        runner.running = true;
        runner.next = 0;
        runner.nextAt = now;
    }

    function stop(runner:Runner):Void {
        runner.running = false;
        release(runner);
    }

    public function stopAll():Void for (runner in runners) stop(runner);

    function release(runner:Runner):Void {
        if (runner.down == 0) return;
        var code = runner.down;
        runner.down = 0;
        io.send(code, false);
    }

    static function hasKeys(def:MacroDef):Bool {
        for (step in def.steps) if (step.key != 0) return true;
        return false;
    }

    function fire(def:MacroDef, runner:Runner, now:Float):Void {
        // Empty steps are skipped instead of ending the def.
        var index = runner.next;
        while (index < def.steps.length && def.steps[index].key == 0) index++;
        if (index >= def.steps.length) {
            if (!def.repeat || !hasKeys(def)) { stop(runner); return; }
            index = 0;
            while (def.steps[index].key == 0) index++;
        }
        // Two macros never press in the same frame: the game may handle one new key per frame.
        if (sentDownThisTick) { runner.nextAt = now + 0.017; return; }
        sentDownThisTick = true;
        var step = def.steps[index];
        release(runner); // never leave the previous key held
        io.send(step.key, true);
        runner.down = step.key;
        runner.downFrame = frame;
        runner.releaseAt = now + TAP_SECONDS;
        runner.next = index + 1;
        runner.nextAt = now + Math.max(step.delay, MIN_GAP_MS) / 1000;
    }
}
