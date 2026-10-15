package macromod;

/** Remembers which skill kind every picked name stands for (hlx/config/macromod/picked-skills.json),
    so a step keeps working when the name can't be matched any more (other client language). */
class PickStore {
    static inline var PATH = "hlx/config/macromod/picked-skills.json";

    public static function load():Map<String, String> {
        var out = new Map<String, String>();
        try {
            var data:Dynamic = haxe.Json.parse(sys.io.File.getContent(PATH));
            for (name in Reflect.fields(data)) {
                var kind:Dynamic = Reflect.field(data, name);
                if (Std.isOfType(kind, String) && (kind : String) != "") out.set(name, kind);
            }
        } catch (_:Dynamic) {}
        return out;
    }

    public static function save(picks:Map<String, String>):Void {
        try {
            var data = {};
            for (name => kind in picks) Reflect.setField(data, name, kind);
            if (!sys.FileSystem.exists("hlx/config/macromod")) sys.FileSystem.createDirectory("hlx/config/macromod");
            sys.io.File.saveContent(PATH, haxe.Json.stringify(data, null, "  "));
        } catch (_:Dynamic) {}
    }
}
