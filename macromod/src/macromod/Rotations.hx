package macromod;

/** One rotation: up to ten skills used in turn, each as soon as it is ready. */
typedef RotationData = {
    /** 0 (not set), a key code, or {code, modifier} like the Better Mod Settings key binding. */
    var hotkey:Dynamic;
    var hold:Bool;
    var repeat:Bool;
    /** Skill kinds, "" = empty cell (skipped). */
    var slots:Array<String>;
}

/** The rotations the player made in the rotation window: data, saving and the one-key-one-rotation rule. */
class Rotations {
    public static inline var SLOTS = 10;
    static inline var DIR = "hlx/config/macromod";
    public static var path = DIR + "/rotations.json"; // the file of the character in the world (see CharacterStore)

    public static function create():RotationData
        return {hotkey: 0, hold: false, repeat: false, slots: [for (_ in 0...SLOTS) ""]};

    public static function hasSkills(rotation:RotationData):Bool {
        for (slot in rotation.slots) if (slot != "") return true;
        return false;
    }

    /** One rotation from loosely typed data (a saved file): everything missing gets its default. */
    public static function normalize(raw:Dynamic):RotationData {
        var out = create();
        if (raw == null) return out;
        var hotkey:Dynamic = Reflect.field(raw, "hotkey");
        if (MacroDefs.keyCode(hotkey) > 0) out.hotkey = hotkey;
        out.hold = Reflect.field(raw, "hold") == true;
        out.repeat = Reflect.field(raw, "repeat") == true;
        var slots:Dynamic = Reflect.field(raw, "slots");
        if (Std.isOfType(slots, Array)) {
            var list:Array<Dynamic> = slots;
            for (i in 0...Std.int(Math.min(list.length, SLOTS)))
                if (Std.isOfType(list[i], String)) out.slots[i] = StringTools.trim(list[i]);
        }
        return out;
    }

    public static function parse(text:String):Array<RotationData> {
        var out:Array<RotationData> = [];
        try {
            var data:Dynamic = haxe.Json.parse(text);
            var list:Dynamic = Std.isOfType(data, Array) ? data : Reflect.field(data, "rotations");
            if (Std.isOfType(list, Array)) for (raw in (list : Array<Dynamic>)) out.push(normalize(raw));
        } catch (_:Dynamic) {}
        return out;
    }

    public static function serialize(list:Array<RotationData>):String
        return haxe.Json.stringify({rotations: list}, null, "  ");

    public static function load():Array<RotationData> {
        try return parse(sys.io.File.getContent(path)) catch (_:Dynamic) return [];
    }

    public static function save(list:Array<RotationData>):Void {
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            sys.io.File.saveContent(path, serialize(list));
        } catch (_:Dynamic) {}
    }

    /** The key and modifier of a binding as one text ("" = not set): equal text = the same key press. */
    public static function signature(binding:Dynamic):String {
        var code = MacroDefs.keyCode(binding);
        if (code <= 0) return "";
        var modifier:Dynamic = (binding == null || Std.isOfType(binding, Int)) ? null : Reflect.field(binding, "modifier");
        return Std.isOfType(modifier, Int) ? code + "+" + modifier : Std.string(code);
    }

    /**
     * Who already has this key: another rotation (isMacro = false, number = its place in the list, from 1) or one
     * of the three macros (isMacro = true, number = 1...3). The rotation `index` itself does not count. Null if free.
     */
    public static function owner(list:Array<RotationData>, index:Int, binding:Dynamic, macroKeys:Array<Dynamic>):Null<{isMacro:Bool, number:Int}> {
        var sig = signature(binding);
        if (sig == "") return null;
        for (i in 0...list.length) if (i != index && signature(list[i].hotkey) == sig) return {isMacro: false, number: i + 1};
        for (i in 0...macroKeys.length) if (signature(macroKeys[i]) == sig) return {isMacro: true, number: i + 1};
        return null;
    }
}
