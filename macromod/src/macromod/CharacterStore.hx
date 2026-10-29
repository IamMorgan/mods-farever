package macromod;

/** The macros (m1_..m3_ fields of the config) and the rotations belong to a character: each one has its own files in
    hlx/config/macromod, and the config of the settings page always holds the macros of the character in the world. */
class CharacterStore {
    static inline var DIR = "hlx/config/macromod";

    public static function keyOf(uid:String, name:String):String
        return ~/[^A-Za-z0-9_\-]/g.replace(uid + "_" + name, "_");

    public static function macrosPath(key:String):String return DIR + "/macros_" + key + ".json";
    public static function rotationsPath(key:String):String return DIR + "/rotations_" + key + ".json";

    /** The first character to load takes over the macros and rotations saved before they were split by character. */
    public static function adoptShared(key:String):Void {
        for (path in [rotationsPath(key)])
            try if (!sys.FileSystem.exists(path) && sys.FileSystem.exists(DIR + "/rotations.json")) sys.FileSystem.rename(DIR + "/rotations.json", path) catch (_:Dynamic) {}
    }

    public static function hasAnyMacros():Bool {
        try {
            for (file in sys.FileSystem.readDirectory(DIR)) if (StringTools.startsWith(file, "macros_")) return true;
        } catch (_:Dynamic) {}
        return false;
    }

    public static function isMacroField(field:String):Bool return ~/^m\d+_/.match(field);

    public static function save(key:String, config:Dynamic):Void {
        try {
            var out = {};
            for (field in Reflect.fields(config)) if (isMacroField(field)) Reflect.setField(out, field, Reflect.field(config, field));
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            sys.io.File.saveContent(macrosPath(key), haxe.Json.stringify(out, null, "  "));
        } catch (_:Dynamic) {}
    }

    /** Puts the character's macros into the config; a character with none gets the defaults. */
    public static function apply(key:String, config:Dynamic):Void {
        var saved:Dynamic = {};
        try saved = haxe.Json.parse(sys.io.File.getContent(macrosPath(key))) catch (_:Dynamic) {}
        var defaults = new Map<String, Dynamic>();
        for (m in 1...MacroDefs.MACROS + 1) {
            defaults.set("m" + m + "_name", "Macro " + m);
            defaults.set("m" + m + "_hotkey", 0);
            defaults.set("m" + m + "_mode", "Press (Toggle)");
            defaults.set("m" + m + "_repeat", false);
            for (s in 1...MacroDefs.STEPS + 1) {
                defaults.set("m" + m + "_s" + s + "_skill", "");
                defaults.set("m" + m + "_s" + s + "_delay", 100);
            }
        }
        for (field => fallback in defaults) {
            var value:Dynamic = Reflect.field(saved, field);
            Reflect.setField(config, field, value == null ? fallback : value);
        }
    }
}
