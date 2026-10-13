import macromod.Edges;
import macromod.KeyIO;
import macromod.MacroDefs;
import macromod.Sequencer;

class FakeIO implements KeyIO {
    public var pressedCodes:Array<Int> = [];  // hotkeys that went down this frame
    public var heldCodes:Array<Int> = [];     // hotkeys currently held
    public var log:Array<String> = [];
    public var t = 0.0;
    public function new() {}
    public function beginFrame(hotkeys:Array<Dynamic>):Void {}
    public function isPressed(b:Dynamic):Bool return pressedCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function isDown(b:Dynamic):Bool return heldCodes.indexOf(MacroDefs.keyCode(b)) >= 0;
    public function send(code:Int, down:Bool):Void log.push(Std.int(t * 1000) + (down ? " down " : " up ") + code);
}

/** Like the real game: hotkeys are only "held" samples, presses come from Edges. */
class RealisticIO extends FakeIO {
    var edges = new Edges();
    var codes:Array<Int> = [];
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

class SequencerTest {
    static var failures = 0;
    static function check(name:String, cond:Bool, ?info:String):Void {
        if (!cond) { failures++; Sys.println("FAIL " + name + (info != null ? ": " + info : "")); }
        else Sys.println("ok   " + name);
    }

    static function def(hold:Bool, repeat:Bool, steps:Array<Array<Int>>):Dynamic
        return {hotkey: 117, hold: hold, repeat: repeat, steps: [for (s in steps) {key: s[0], delay: s[1]}]};

    static function make(d:Dynamic):{io:FakeIO, seq:Sequencer} {
        var io = new FakeIO();
        var seq = new Sequencer(io);
        seq.macros = [d];
        return {io: io, seq: seq};
    }

    /** Advance 16 ms frames; `pressAtFrame` simulates one hotkey press edge. */
    static function run(c:{io:FakeIO, seq:Sequencer}, ms:Int, ?pressAt:Array<Int>, ?holdFrom:Int = -1, ?holdTo:Int = -1):Void {
        var frame = 0;
        var t = 0;
        while (t <= ms) {
            c.io.t = t / 1000;
            var pressed = pressAt != null && pressAt.indexOf(frame) >= 0;
            c.io.pressedCodes = pressed ? [117] : [];
            c.io.heldCodes = pressed || (holdFrom >= 0 && frame >= holdFrom && frame < holdTo) ? [117] : [];
            c.seq.update(t / 1000);
            frame++;
            t += 16;
        }
    }

    static function downs(io:FakeIO):Array<String> return [for (l in io.log) if (l.indexOf(" down ") > 0) l.split(" ")[2]];

    static function main():Void {
        // 1. Toggle, no repeat: A, B, C once, with the configured pauses.
        var c = make(def(false, false, [[65, 100], [66, 200], [67, 0]]));
        run(c, 1000, [1]);
        check("toggle once: keys in order", downs(c.io).join(",") == "65,66,67", Std.string(c.io.log));
        check("toggle once: stops by itself", !c.seq.isRunning(0));
        check("toggle once: every key released", c.io.log.length == 6, Std.string(c.io.log));

        // 2. Pause between presses is honoured (A at ~16, B >= 100 ms later).
        var a = Std.parseInt(c.io.log[0].split(" ")[0]), b = Std.parseInt(c.io.log[2].split(" ")[0]);
        check("pause A->B >= 100ms", b - a >= 100, a + " -> " + b);
        var up = Std.parseInt(c.io.log[1].split(" ")[0]);
        check("key released after tap (>=45ms, before next)", up - a >= 45 && up < b, a + " up " + up);

        // 3. Empty step in the middle is skipped, not a stop.
        c = make(def(false, false, [[65, 100], [0, 100], [67, 100]]));
        run(c, 600, [1]);
        check("empty step skipped", downs(c.io).join(",") == "65,67", Std.string(c.io.log));

        // 4. Toggle + repeat loops until pressed again; stop releases the key.
        c = make(def(false, true, [[65, 100], [66, 100]]));
        run(c, 2000, [1, 100]);
        var d = downs(c.io);
        check("repeat loops", d.length >= 6 && d[0] == "65" && d[1] == "66" && d[2] == "65", d.join(","));
        check("second press stops", !c.seq.isRunning(0));
        var last = c.io.log[c.io.log.length - 1];
        check("no key left held after stop", last.indexOf(" up ") > 0, last);

        // 5. Hold: runs while held, stops on release.
        c = make(def(true, true, [[65, 100]]));
        run(c, 1500, [1], 1, 40);   // held for frames 1..39 (~640ms)
        d = downs(c.io);
        check("hold: runs while held", d.length >= 4, Std.string(d.length));
        check("hold: stops on release", !c.seq.isRunning(0));
        var presses = d.length;
        check("hold: no presses after release", presses <= 8, Std.string(presses));

        // 6. Hold without repeat: single pass, no restart while still held.
        c = make(def(true, false, [[65, 100], [66, 100]]));
        run(c, 1500, [1], 1, 80);
        check("hold no repeat: one pass", downs(c.io).join(",") == "65,66", Std.string(c.io.log));

        // 7. Unbound hotkey / no steps never starts.
        var d0:Dynamic = def(false, false, [[65, 100]]);
        d0.hotkey = 0;
        c = make(d0);
        run(c, 500, [1]);
        check("unbound hotkey does nothing", c.io.log.length == 0);
        c = make(def(false, false, [[0, 100]]));
        run(c, 500, [1]);
        check("macro with no keys does nothing", c.io.log.length == 0);

        // 8. Delay 0 is clamped so key-up always registers before the next key-down.
        c = make(def(false, false, [[65, 0], [66, 0]]));
        run(c, 400, [1]);
        var l = c.io.log;
        check("delay 0 clamped", l.length == 4 && l[1].indexOf(" up 65") > 0 && l[2].indexOf(" down 66") > 0, Std.string(l));

        // 9. Two macros at once: both run, neither stops the other, never two key-downs in one frame.
        var io = new FakeIO();
        var seq = new Sequencer(io);
        var first:Dynamic = def(false, true, [[65, 100], [66, 100]]);
        var second:Dynamic = def(false, true, [[67, 100], [68, 100]]);
        second.hotkey = 118;
        seq.macros = [first, second];
        var frame = 0, tm = 0;
        while (tm <= 1500) {
            io.t = tm / 1000;
            io.pressedCodes = frame == 1 ? [117, 118] : []; // both hotkeys in the same frame
            io.heldCodes = [];
            seq.update(tm / 1000);
            frame++; tm += 16;
        }
        var all = [for (l in io.log) if (l.indexOf(" down ") > 0) l.split(" ")];
        var keys = [for (a in all) a[2]];
        check("two macros: both run", keys.indexOf("65") >= 0 && keys.indexOf("67") >= 0, Std.string(keys));
        check("two macros: both running", seq.isRunning(0) && seq.isRunning(1));
        var times = [for (a in all) a[0]];
        var unique = new Map<String, Bool>();
        for (x in times) unique.set(x, true);
        check("two macros: never two key-downs in one tick", Lambda.count(unique) == times.length, times.join(","));
        // Stopping one must leave the other running.
        io.pressedCodes = [117]; seq.update(1.6);
        io.pressedCodes = [];
        for (k in 0...30) { io.t = 1.6 + k * 0.016; seq.update(1.6 + (k + 1) * 0.016); }
        check("two macros: stopping one keeps the other running", !seq.isRunning(0) && seq.isRunning(1));

        // 10. A key held for a long time (auto-repeat) is ONE press: the toggle macro keeps running after release.
        var rio = new RealisticIO();
        var rseq = new Sequencer(rio);
        var m1:Dynamic = def(false, true, [[65, 100]]);
        var m2:Dynamic = def(false, true, [[66, 100], [67, 100]]);
        var m3:Dynamic = def(false, true, [[68, 100]]);
        m2.hotkey = 118; m3.hotkey = 119;
        rseq.macros = [m1, m2, m3];
        var tt = 0;
        var holds = [{code: 117, from: 100, to: 200}, {code: 118, from: 500, to: 1300}, {code: 119, from: 900, to: 1100}];
        while (tt <= 3000) {
            rio.t = tt / 1000;
            rio.downNow = [for (h in holds) if (tt >= h.from && tt < h.to) h.code];
            rseq.update(tt / 1000);
            tt += 16;
        }
        check("held key = one press: macro 1 still running", rseq.isRunning(0));
        check("held 800 ms: macro 2 still running after release", rseq.isRunning(1));
        check("macro 3 runs in parallel too", rseq.isRunning(2));
        var started = [for (l in rio.log) if (l.indexOf(" down ") > 0) l.split(" ")[2]];
        check("all three macros produced keys", started.indexOf("65") >= 0 && started.indexOf("66") >= 0 && started.indexOf("68") >= 0, Std.string(started.length));
        var lastSecond = [for (l in rio.log) if (l.indexOf(" down ") > 0 && Std.parseInt(l.split(" ")[0]) > 2500) l.split(" ")[2]];
        check("all three still pressing at the end", lastSecond.indexOf("65") >= 0 && lastSecond.indexOf("66") >= 0 && lastSecond.indexOf("68") >= 0, lastSecond.join(","));

        // 11. Edges: held 100 frames = 1 press, bounce ignored, a real second press counts.
        var e = new Edges();
        var presses = 0;
        for (i in 0...100) if (e.pressed(5, true, i * 0.016)) presses++;
        check("edges: long hold is one press", presses == 1, Std.string(presses));
        e.pressed(5, false, 5.0);
        check("edges: press", e.pressed(5, true, 5.01));
        e.pressed(5, false, 5.03);
        check("edges: bounce within 150 ms ignored", !e.pressed(5, true, 5.06));
        e.pressed(5, false, 6.0);
        check("edges: later press counts", e.pressed(5, true, 6.5));

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
