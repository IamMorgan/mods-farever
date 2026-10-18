package buildcalc;

/** The questionnaire: priority of each axis (0 none .. 3 high), melee or ranged, ideal or own items. */
typedef Settings = {
    var priorities:Array<Int>; // damage, defense, health, healing
    var ranged:Bool;
    var ideal:Bool;
}

/** A saved template: the questionnaire (the computed build is added once the calculation exists). */
typedef Template = {
    var settings:Settings;
    var savedAt:String;
    /** The calculated equipment: slot index -> item id (null = nothing calculated when saved). */
    @:optional var build:Array<TemplateItem>;
    @:optional var talents:Array<{id:String, rank:Int}>;
    @:optional var sigils:Array<String>;
    @:optional var skills:Array<{id:String, runes:Array<String>}>;
    /** The recommended infusion sets: infusion id and number of items. */
    @:optional var infusions:Array<{id:String, count:Int}>;
}

/** An item of a template: enough to show it as calculated (its level, upgrade, augments, infusion). */
typedef TemplateItem = {slot:Int, id:String, ?level:Int, ?rarity:String, ?upgrade:Int, ?augs:Array<String>, ?infusion:String, ?bonus:String};

/**
 * What the player chose in the calculator and the three templates, kept in
 * hlx/config/buildcalc/state.json so the tab shows them again next time.
 */
class State {
    static inline var DIR = "hlx/config/buildcalc";
    static inline var PATH = "hlx/config/buildcalc/state.json";
    public static inline var TEMPLATES = 3;

    public static var settings:Settings = defaults();
    public static var templates:Array<Null<Template>> = [for (_ in 0...TEMPLATES) null];
    /** The template shown (0..2), -1 = none. */
    public static var active = -1;
    /**
     * The training dummy as last read from the game (its level is set where it stands on the map, so only a
     * dummy in the world tells its armour): {armor, magicArmor, magicReduction, resilience, taken, level}.
     */
    public static var dummy:Dynamic = null;
    static var loaded = false;

    public static function defaults():Settings return {priorities: [3, 1, 1, 0], ranged: false, ideal: true};

    public static function copy(s:Settings):Settings return {priorities: s.priorities.copy(), ranged: s.ranged, ideal: s.ideal};

    static function valid(s:Dynamic):Settings {
        var d = defaults();
        if (s == null) return d;
        var p:Dynamic = Reflect.field(s, "priorities");
        if (Std.isOfType(p, Array) && (p : Array<Dynamic>).length == 4)
            d.priorities = [for (v in (p : Array<Dynamic>)) Std.isOfType(v, Int) ? Std.int(Math.max(0, Math.min(3, v))) : 1];
        // the rules of the questionnaire: one High, at most two Medium (later ones are lowered)
        var high = false, medium = 0;
        for (i in 0...d.priorities.length) {
            if (d.priorities[i] == 3) { if (high) d.priorities[i] = 2; else high = true; }
            if (d.priorities[i] == 2) { if (medium >= 2) d.priorities[i] = 1; else medium++; }
        }
        d.ranged = Reflect.field(s, "ranged") == true;
        d.ideal = Reflect.field(s, "ideal") == true;
        return d;
    }

    public static function load():Void {
        if (loaded) return;
        loaded = true;
        try {
            if (!sys.FileSystem.exists(PATH)) { DebugLog.line("state: no saved state, defaults"); return; }
            var data:Dynamic = haxe.Json.parse(sys.io.File.getContent(PATH));
            settings = valid(Reflect.field(data, "settings"));
            var list:Dynamic = Reflect.field(data, "templates");
            if (Std.isOfType(list, Array)) for (i in 0...TEMPLATES) {
                var t:Dynamic = (list : Array<Dynamic>)[i];
                if (t == null) { templates[i] = null; continue; }
                var b:Dynamic = Reflect.field(t, "build");
                function str(v:Dynamic):String return v == null ? null : Std.string(v);
                function int(v:Dynamic):Null<Int> return Std.isOfType(v, Int) || Std.isOfType(v, Float) ? Std.int(v) : null;
                var build:Array<TemplateItem> = Std.isOfType(b, Array) ? [for (e in (b : Array<Dynamic>)) {
                    var ag:Dynamic = Reflect.field(e, "augs");
                    ({slot: Std.int(Reflect.field(e, "slot")), id: Std.string(Reflect.field(e, "id")), level: int(Reflect.field(e, "level")),
                        rarity: str(Reflect.field(e, "rarity")), upgrade: int(Reflect.field(e, "upgrade")),
                        augs: Std.isOfType(ag, Array) ? [for (x in (ag : Array<Dynamic>)) Std.string(x)] : null,
                        infusion: str(Reflect.field(e, "infusion")), bonus: str(Reflect.field(e, "bonus"))} : TemplateItem);
                }] : null;
                var inf:Dynamic = Reflect.field(t, "infusions");
                var infusions = Std.isOfType(inf, Array) ? [for (e in (inf : Array<Dynamic>)) {id: Std.string(Reflect.field(e, "id")), count: Std.int(Reflect.field(e, "count"))}] : null;
                var tl:Dynamic = Reflect.field(t, "talents");
                var talents = Std.isOfType(tl, Array) ? [for (e in (tl : Array<Dynamic>)) {id: Std.string(Reflect.field(e, "id")), rank: Std.int(Reflect.field(e, "rank"))}] : null;
                var sg:Dynamic = Reflect.field(t, "sigils");
                var sigils = Std.isOfType(sg, Array) ? [for (e in (sg : Array<Dynamic>)) Std.string(e)] : null;
                var sk:Dynamic = Reflect.field(t, "skills");
                var skills = Std.isOfType(sk, Array) ? [for (e in (sk : Array<Dynamic>)) {
                    var r:Dynamic = Reflect.field(e, "runes");
                    {id: Std.string(Reflect.field(e, "id")), runes: Std.isOfType(r, Array) ? [for (x in (r : Array<Dynamic>)) Std.string(x)] : []};
                }] : null;
                templates[i] = {settings: valid(Reflect.field(t, "settings")), savedAt: Std.string(Reflect.field(t, "savedAt")), build: build,
                    talents: talents, sigils: sigils, skills: skills, infusions: infusions};
            }
            dummy = Reflect.field(data, "dummy");
            var a:Dynamic = Reflect.field(data, "active");
            active = Std.isOfType(a, Int) && a >= 0 && a < TEMPLATES && templates[a] != null ? a : -1;
            DebugLog.line("state: loaded " + haxe.Json.stringify(data));
        } catch (e:Dynamic) DebugLog.error("state: load", e);
    }

    public static function save():Void {
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            var text = haxe.Json.stringify({settings: settings, templates: templates, active: active, dummy: dummy}, null, "  ");
            sys.io.File.saveContent(PATH, text);
            DebugLog.line("state: saved " + StringTools.replace(text, "\n", " "));
        } catch (e:Dynamic) DebugLog.error("state: save", e);
    }

    public static function saveTemplate(slot:Int, ?build:Array<TemplateItem>, ?talents:Array<{id:String, rank:Int}>, ?sigils:Array<String>,
            ?skills:Array<{id:String, runes:Array<String>}>, ?infusions:Array<{id:String, count:Int}>):Void {
        templates[slot] = {settings: copy(settings), savedAt: Date.now().toString(), build: build, talents: talents, sigils: sigils, skills: skills,
            infusions: infusions};
        active = slot;
        save();
    }

    public static function openTemplate(slot:Int):Void {
        var t = templates[slot];
        active = slot;
        if (t != null) settings = copy(t.settings);
        save();
    }

    public static function resetTemplate(slot:Int):Void {
        templates[slot] = null;
        if (active == slot) active = -1;
        save();
    }

    public static function resetTemplates():Void {
        templates = [for (_ in 0...TEMPLATES) null];
        active = -1;
        save();
    }
}
