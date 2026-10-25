package farmer;

/**
 * The mod's log: hlx/config/farmer/farmer.log, always written (the old one rolls over to farmer.old.log at LIMIT bytes).
 * One line per event: `HH:MM:SS.mmm [tag] text`. Tags: bot (decisions, targets), beat (a status line every second), nav (paths,
 * stuck, glider, obelisks), fight (skills, combo), dodge (the auto-dodge), loot, gear, svc (bag services), trap, mod (start/stop, errors).
 * Lines are kept in memory and written at most once a second (and at once for errors, stops and the end of the game).
 * The same lines go to the developer folder's log.txt when that folder exists (the live-test tools read it).
 */
class Log {
    static inline var DIR = "hlx/config/farmer";
    static inline var FILE = DIR + "/farmer.log";
    static inline var OLD = DIR + "/farmer.old.log";
    static inline var LIMIT = 4000000;

    static var buffer:Array<String> = [];
    static var flushedAt = 0.0;
    static var lastLine = "";
    static var lastAt = 0.0;
    static var repeats = 0;
    static var size = -1;

    public static function w(text:String):Void t("bot", text);

    public static function t(tag:String, text:String):Void {
        var now = haxe.Timer.stamp();
        var body = "[" + tag + "] " + text;
        if (body == lastLine && now - lastAt < 1.0) { repeats++; lastAt = now; return; }
        if (repeats > 0) { buffer.push(stamp() + " [" + tag + "] (the line above repeated " + repeats + " more times)"); repeats = 0; }
        lastLine = body;
        lastAt = now;
        buffer.push(stamp() + " " + body);
        if (buffer.length >= 60 || tag == "err" || tag == "mod") flush(true);
    }

    public static function err(where:String, error:Dynamic):Void {
        var stack = "";
        try stack = " " + StringTools.replace(haxe.CallStack.toString(haxe.CallStack.exceptionStack()), "\n", " | ") catch (_:Dynamic) {}
        t("err", where + ": " + Std.string(error) + stack);
    }

    static function stamp():String {
        var s = haxe.Timer.stamp();
        var ms = Std.int((s - Math.floor(s)) * 1000);
        var text = "";
        try text = Date.now().toString().substr(11, 8) catch (_:Dynamic) { text = Std.string(Std.int(s)); }
        return text + "." + StringTools.lpad(Std.string(ms), "0", 3);
    }

    /** Writes what is kept in memory (at most once a second unless `force`). */
    public static function flush(force:Bool = false):Void {
        if (buffer.length == 0) return;
        var now = haxe.Timer.stamp();
        if (!force && now - flushedAt < 1.0) return;
        flushedAt = now;
        var text = buffer.join("\n") + "\n";
        buffer = [];
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            if (size < 0) size = sys.FileSystem.exists(FILE) ? sys.FileSystem.stat(FILE).size : 0;
            if (size > LIMIT) {
                if (sys.FileSystem.exists(OLD)) sys.FileSystem.deleteFile(OLD);
                sys.FileSystem.rename(FILE, OLD);
                size = 0;
            }
            var out = sys.io.File.append(FILE);
            out.writeString(text);
            out.close();
            size += text.length;
        } catch (_:Dynamic) {}
        try {
            if (sys.FileSystem.exists(Probe.DIR)) {
                var out = sys.io.File.append(Probe.DIR + "/log.txt");
                out.writeString(text);
                out.close();
            }
        } catch (_:Dynamic) {}
    }
}
