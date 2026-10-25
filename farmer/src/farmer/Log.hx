package farmer;

/** Diagnostics: written to hlx/config/farmer/test/log.txt, and only while that developer folder exists. */
class Log {
    public static function w(text:String):Void {
        try {
            if (!sys.FileSystem.exists(Probe.DIR)) return;
            var out = sys.io.File.append(Probe.DIR + "/log.txt");
            out.writeString(Std.string(Std.int(haxe.Timer.stamp())) + " " + text + "\n");
            out.close();
        } catch (_:Dynamic) {}
    }
}
