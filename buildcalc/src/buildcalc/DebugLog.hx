package buildcalc;

/**
 * Full development log: hlx/buildcalc-debug.txt. Every hook, every build step and every error (with
 * its call stack) is written, so a problem in the game can be found from the log alone.
 * A new game session starts with a separator line. Lines are buffered and appended to the file once a
 * frame (and when the buffer grows), so a calculation that logs a lot stays fast.
 * Turned off for releases (`enabled`).
 */
class DebugLog {
    public static var enabled = true;
    static inline var PATH = "hlx/buildcalc-debug.txt";
    static inline var MAX_SIZE = 2000000;
    static var started = false;
    static var buffer = new StringBuf();
    static var pending = 0;
    /** The calculation writes from its own thread: one writer at a time. */
    static var lock = new sys.thread.Mutex();

    static function stamp():String {
        var t = haxe.Timer.stamp();
        return Date.now().toString() + "." + StringTools.lpad(Std.string(Std.int((t - Math.ffloor(t)) * 1000)), "0", 3);
    }

    /** Appends the buffered lines to the file. */
    public static function flush():Void {
        lock.acquire();
        if (pending == 0) { lock.release(); return; }
        var text = buffer.toString();
        buffer = new StringBuf();
        pending = 0;
        lock.release();
        try {
            var out = sys.io.File.append(PATH, true);
            out.writeString(text);
            out.close();
        } catch (_:Dynamic) {}
    }

    public static function line(s:String):Void {
        if (!enabled) return;
        lock.acquire();
        if (!started) {
            started = true;
            // keep the file from growing without end: start over when it is large
            try if (sys.FileSystem.exists(PATH) && sys.FileSystem.stat(PATH).size > MAX_SIZE) sys.io.File.saveContent(PATH, "") catch (_:Dynamic) {}
            buffer.add("\n========== buildcalc session " + Date.now().toString() + " ==========\n");
        }
        buffer.add(stamp() + " " + s + "\n");
        pending++;
        var full = pending > 400;
        lock.release();
        if (full) flush();
    }

    /** An error with its message and call stack. */
    public static function error(where:String, e:Dynamic):Void {
        var stack = "";
        try stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack()) catch (_:Dynamic) {}
        line("ERROR in " + where + ": " + Std.string(e) + (stack != "" ? "\n    stack:" + StringTools.replace(stack, "\n", "\n      ") : ""));
        flush();
    }

    /** Runs `body`, logging any error; never throws. */
    public static function guard(where:String, body:Void->Void):Void {
        try {
            body();
        } catch (e:Dynamic) {
            error(where, e);
        }
    }
}
