package dpf;

/** Switches for in-game testing: a file next to the settings names the parts to leave out (re-read every two seconds). */
class TestFlags {
    static var flags = "";
    static var nextRead = 0.0;

    public static function has(name:String):Bool {
        var now = haxe.Timer.stamp();
        if (now >= nextRead) {
            nextRead = now + 2;
            flags = try sys.io.File.getContent("hlx/config/" + HlxRuntime.moduleName() + "/test-flags.txt") catch (_:Dynamic) "";
        }
        return flags.indexOf(name) >= 0;
    }
}
