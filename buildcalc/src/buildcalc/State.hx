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
    /** The weapon skills in the hero's slots: [main weapon's, arsenal weapon's]. */
    @:optional var weaponSkills:Array<Array<String>>;
}

/** The last calculation: the questionnaire and the build it gave (the next calculation starts from it too). */
typedef LastResult = {
    var settings:Settings;
    var savedAt:String;
    var build:Array<TemplateItem>;
    @:optional var talents:Array<{id:String, rank:Int}>;
    @:optional var skills:Array<{id:String, runes:Array<String>}>;
    /** Optimizer.MODEL_VERSION it was valued with: a result of an older model is not a start (it may be wrong now). */
    @:optional var model:Int;
    /** The ranges of the axes and their highest values it was valued with (the score of this questionnaire, kept). */
    @:optional var spans:Array<Float>;
    @:optional var hi:Array<Float>;
    /** The fight choices it was valued with (Model.exportChoices). */
    @:optional var choices:Dynamic;
}

/**
 * An item of a template: enough to show it as calculated. `lootLevel` is the level it dropped at (st.item.Gear.level,
 * what st.Item.create takes); templates saved before kept `level` = st.Item.getLevel (item level incl. upgrades): ignored.
 * `own`: one of the hero's real items (worn or owned), not one created from the game's data.
 */
typedef TemplateItem = {slot:Int, id:String, ?lootLevel:Int, ?own:Bool, ?rarity:String, ?upgrade:Int, ?augs:Array<String>, ?infusion:String, ?bonus:String};

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
    /**
     * The last result of each questionnaire (priorities, melee/ranged, ideal/own): a calculation with other priorities
     * does not take the place of this one's (with one place only, "Healing: Medium" wiped the result of "Healing: Low"
     * and the next "Low" calculation started from the worn build again — other talents came out).
     */
    public static var lasts:Array<LastResult> = [];

    static function settingsKey(s:Settings):String return s.priorities.join(",") + "|" + s.ranged + "|" + s.ideal;

    /** The last result for this questionnaire (null: none). */
    public static function lastFor(s:Settings):Null<LastResult> {
        for (l in lasts) if (l.settings != null && settingsKey(l.settings) == settingsKey(s)) return l;
        return null;
    }
    static var loaded = false;
    static var idRe = ~/^[A-Za-z0-9_]+$/;

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
                var build = parseBuild(Reflect.field(t, "build"));
                var inf:Dynamic = Reflect.field(t, "infusions");
                var infusions = Std.isOfType(inf, Array) ? [for (e in (inf : Array<Dynamic>)) {id: Std.string(Reflect.field(e, "id")), count: Std.int(Reflect.field(e, "count"))}] : null;
                var talents = parseTalents(Reflect.field(t, "talents"));
                var sg:Dynamic = Reflect.field(t, "sigils");
                // templates saved before the fix of GameData.idOf hold "{bytes : ???, length : 21}": not an id, dropped
                var sigils = Std.isOfType(sg, Array) ? [for (e in (sg : Array<Dynamic>)) if (Std.isOfType(e, String) && idRe.match(e)) Std.string(e)] : null;
                var skills = parseSkills(Reflect.field(t, "skills"));
                var ws:Dynamic = Reflect.field(t, "weaponSkills");
                var weaponSkills = Std.isOfType(ws, Array) ? [for (e in (ws : Array<Dynamic>)) Std.isOfType(e, Array) ? [for (x in (e : Array<Dynamic>)) Std.string(x)] : []] : null;
                templates[i] = {settings: valid(Reflect.field(t, "settings")), savedAt: Std.string(Reflect.field(t, "savedAt")), build: build,
                    talents: talents, sigils: sigils, skills: skills, infusions: infusions, weaponSkills: weaponSkills};
            }
            dummy = Reflect.field(data, "dummy");
            // "lasts": one per questionnaire; "last": the single one kept before
            var ls:Dynamic = Reflect.field(data, "lasts");
            var list:Array<Dynamic> = Std.isOfType(ls, Array) ? ls : [];
            var l1:Dynamic = Reflect.field(data, "last");
            if (l1 != null) list.push(l1);
            lasts = [];
            for (l in list) {
                var lb = parseBuild(Reflect.field(l, "build"));
                if (lb == null) continue;
                var r:LastResult = {settings: valid(Reflect.field(l, "settings")), savedAt: Std.string(Reflect.field(l, "savedAt")), build: lb,
                    talents: parseTalents(Reflect.field(l, "talents")), skills: parseSkills(Reflect.field(l, "skills")),
                    model: int(Reflect.field(l, "model")), spans: floats(Reflect.field(l, "spans")), hi: floats(Reflect.field(l, "hi")),
                    choices: Reflect.field(l, "choices")};
                if (lastFor(r.settings) == null) lasts.push(r);
            }
            var a:Dynamic = Reflect.field(data, "active");
            active = Std.isOfType(a, Int) && a >= 0 && a < TEMPLATES && templates[a] != null ? a : -1;
            DebugLog.line("state: loaded " + haxe.Json.stringify(data));
        } catch (e:Dynamic) DebugLog.error("state: load", e);
    }

    static function str(v:Dynamic):String return v == null ? null : Std.string(v);
    static function floats(v:Dynamic):Array<Float> {
        if (!Std.isOfType(v, Array) || (v : Array<Dynamic>).length != 4) return null;
        return [for (x in (v : Array<Dynamic>)) Std.parseFloat(Std.string(x))];
    }

    static function int(v:Dynamic):Null<Int> return Std.isOfType(v, Int) || Std.isOfType(v, Float) ? Std.int(v) : null;

    static function parseBuild(b:Dynamic):Array<TemplateItem> {
        return Std.isOfType(b, Array) ? [for (e in (b : Array<Dynamic>)) {
            var ag:Dynamic = Reflect.field(e, "augs");
            ({slot: Std.int(Reflect.field(e, "slot")), id: Std.string(Reflect.field(e, "id")), lootLevel: int(Reflect.field(e, "lootLevel")), own: Reflect.field(e, "own") == true,
                rarity: str(Reflect.field(e, "rarity")), upgrade: int(Reflect.field(e, "upgrade")),
                augs: Std.isOfType(ag, Array) ? [for (x in (ag : Array<Dynamic>)) Std.string(x)] : null,
                infusion: str(Reflect.field(e, "infusion")), bonus: str(Reflect.field(e, "bonus"))} : TemplateItem);
        }] : null;
    }

    static function parseTalents(tl:Dynamic):Array<{id:String, rank:Int}> {
        return Std.isOfType(tl, Array) ? [for (e in (tl : Array<Dynamic>)) {id: Std.string(Reflect.field(e, "id")), rank: Std.int(Reflect.field(e, "rank"))}] : null;
    }

    static function parseSkills(sk:Dynamic):Array<{id:String, runes:Array<String>}> {
        return Std.isOfType(sk, Array) ? [for (e in (sk : Array<Dynamic>)) {
            var r:Dynamic = Reflect.field(e, "runes");
            {id: Std.string(Reflect.field(e, "id")), runes: Std.isOfType(r, Array) ? [for (x in (r : Array<Dynamic>)) Std.string(x)] : []};
        }] : null;
    }

    /** Keeps the result of a calculation done with the questionnaire of now. */
    public static function setLast(s:Settings, build:Array<TemplateItem>, talents:Array<{id:String, rank:Int}>, skills:Array<{id:String, runes:Array<String>}>,
            model:Int, ?spans:Array<Float>, ?hi:Array<Float>, ?choices:Dynamic):Void {
        var r:LastResult = {settings: copy(s), savedAt: Date.now().toString(), build: build, talents: talents, skills: skills, model: model,
            spans: spans, hi: hi, choices: choices};
        lasts = [for (l in lasts) if (settingsKey(l.settings) != settingsKey(s)) l];
        lasts.unshift(r);
        // the 24 questionnaires used last are kept
        if (lasts.length > 24) lasts = lasts.slice(0, 24);
        save();
    }

    public static function save():Void {
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            var text = haxe.Json.stringify({settings: settings, templates: templates, active: active, dummy: dummy, lasts: lasts}, null, "  ");
            sys.io.File.saveContent(PATH, text);
            DebugLog.line("state: saved " + StringTools.replace(text, "\n", " "));
        } catch (e:Dynamic) DebugLog.error("state: save", e);
    }

    public static function saveTemplate(slot:Int, ?build:Array<TemplateItem>, ?talents:Array<{id:String, rank:Int}>, ?sigils:Array<String>,
            ?skills:Array<{id:String, runes:Array<String>}>, ?infusions:Array<{id:String, count:Int}>, ?weaponSkills:Array<Array<String>>):Void {
        templates[slot] = {settings: copy(settings), savedAt: Date.now().toString(), build: build, talents: talents, sigils: sigils, skills: skills,
            infusions: infusions, weaponSkills: weaponSkills};
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
