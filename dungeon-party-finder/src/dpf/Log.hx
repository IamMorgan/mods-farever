package dpf;

/** An opt-in log (hlx/dpf-debug.txt, switched on in the settings) for bug reports: what the search did and why. */
class Log {
    public static var enabled = false;
    static inline var PATH = "hlx/dpf-debug.txt";
    static var started = false;

    public static function write(text:String):Void {
        if (!enabled) return;
        try {
            var out = started ? sys.io.File.append(PATH) : sys.io.File.write(PATH);
            started = true;
            out.writeString(DateTools.format(Date.now(), "%H:%M:%S") + " " + text + "\n");
            out.close();
        } catch (_:Dynamic) {}
    }
}
