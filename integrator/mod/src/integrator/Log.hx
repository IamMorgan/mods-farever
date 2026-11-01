package integrator;

class Log {
    static inline var DIR = "hlx/config/integrator";
    static inline var FILE = DIR + "/integrator.log";

    public static function t(tag:String, text:String):Void {
        try {
            sys.FileSystem.createDirectory(DIR);
            var f = sys.io.File.append(FILE);
            f.writeString(tag + ": " + text + "\n");
            f.close();
        } catch (_:Dynamic) {}
    }
}
