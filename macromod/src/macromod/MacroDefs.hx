package macromod;

typedef MacroStep = {key:Int, delay:Int};

typedef MacroDef = {
    var hotkey:Dynamic;
    var hold:Bool;
    var repeat:Bool;
    var steps:Array<MacroStep>;
}

/** Turns the flat settings object (m1_name, m1_s1_key, ...) into macro definitions. */
class MacroDefs {
    public static inline var MACROS = 3;
    public static inline var STEPS = 10;

    public static function keyCode(binding:Dynamic):Int {
        if (binding == null) return 0;
        if (Std.isOfType(binding, Int)) return binding;
        var code:Dynamic = Reflect.field(binding, "code");
        return Std.isOfType(code, Int) ? code : 0;
    }

    public static function fromConfig(config:Dynamic):Array<MacroDef> {
        var out = [];
        for (m in 1...MACROS + 1) {
            var prefix = "m" + m;
            var steps = [];
            for (s in 1...STEPS + 1) {
                var delay:Dynamic = Reflect.field(config, prefix + "_s" + s + "_delay");
                steps.push({key: keyCode(Reflect.field(config, prefix + "_s" + s + "_key")),
                    delay: Std.isOfType(delay, Int) || Std.isOfType(delay, Float) ? Std.int(delay) : 100});
            }
            out.push({
                hotkey: Reflect.field(config, prefix + "_hotkey"),
                hold: Reflect.field(config, prefix + "_mode") == "Hold",
                repeat: Reflect.field(config, prefix + "_repeat") == true,
                steps: steps
            });
        }
        return out;
    }
}
