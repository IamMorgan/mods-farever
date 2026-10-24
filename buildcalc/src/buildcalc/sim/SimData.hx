package buildcalc.sim;

/** Reads a record of the game's data, whatever holds it (the game's objects, or data.cdb's JSON offline). */
interface Rec {
    function get(r:Dynamic, field:String):Dynamic;
    function len(list:Dynamic):Int;
    function at(list:Dynamic, i:Int):Dynamic;
    /** Name of value `v` of the data enum `kind` ("effect", "on", "type", "stepType"). */
    function enumName(kind:String, v:Dynamic):String;
}

typedef SScaling = {atb:String, ratio:Float, minRank:Int, maxRank:Int, equalRank:Int};
/** stackScale: the effect's flag ScaleWithStacks (a status's tick, hit or consumption counts once per stack). */
typedef SEffect = {uid:Int, kind:String, affinity:String, physical:Bool, base:Float, scaling:Array<SScaling>, dynVal:Int, status:String, duration:Dynamic, raw:Dynamic, stackScale:Bool};
typedef SStep = {index:Int, id:String, on:String, type:String, mastery:String, masteryExclude:String, minRank:Int, maxRank:Int, equalRank:Int,
    delay:Dynamic, duration:Dynamic, tick:Dynamic, targetCd:Float, spread:Bool, hitFilter:Int, ignoreMain:Bool, presence:Bool, status:String, statusSelf:Bool,
    statusStacks:Int, condStep:String, travel:Float, alignment:Int, globalId:String, summon:String, summonCount:Int, effects:Array<SEffect>};
/** dyn: the dynamic value (Inst.dyn index) the affix's value follows, 0 none; dynOp: 0 multiply, 1 override, 2 add (skill@affixes@mod@dynVal). */
typedef SAffix = {ref:String, attr:String, val:Float, minRank:Int, maxRank:Int, equalRank:Int, mastery:String, dyn:Int, dynOp:Int};
typedef SMastery = {id:String, cooldown:Null<Float>, duration:Null<Float>, charges:Null<Int>, vars:Dynamic};

/** One skill of the data (Data.skill), read once into plain values; its script parsed. */
class SkillInfo {
    public var id:String;
    public var inf:Dynamic;
    public var type:String;
    public var nature:String;
    public var cooldown:Float;
    public var duration:Float;
    public var charges:Int;
    public var steps:Array<SStep> = [];
    public var affixes:Array<SAffix> = [];
    public var masteries:Array<SMastery> = [];
    public var rankOverride:Array<{minRank:Int, vars:Dynamic}> = [];
    /** The skills the description refers to (texts.refs: ref, ref2…): the variables of a passive and of the status it applies are read in the description together. */
    public var refIds:Array<String> = [];
    public var vars:Dynamic;
    public var maxPoints = 0;
    public var subskills:Array<String> = [];
    /** Passives the skill gives from a rank on (props.rankPassives). */
    public var rankPassives:Array<{minRank:Int, ids:Array<String>}> = [];
    public var maxStacks = 1;
    /** The skill's flags (bit 2048: one status for every instigator, st.skill.Status.stacksWith). */
    public var flags = 0;
    /** What a use costs (props.costs: a resource attribute and an amount; scripts may change it with evalCost). */
    public var costs:Array<{atb:String, amount:Float}> = [];
    /** The status's types (props.status.types: Poison, Poison_Dose, Buff…). */
    public var statusTypes:Array<String> = [];
    /** The skills the status puts in the hero's skill slots while it lasts (props.status.skillOverride: Nova's ultimate). */
    public var overrides:Array<String> = [];
    /** The farthest reach of its hitting steps (projectiles, areas, effects on the target), in metres. */
    public var reach = 0.0;
    public var dotHot = false;
    public var script:Script = null;
    /** The script's source (to read which skills it names). */
    public var scriptText = "";
    public var scriptError = "";
    var rec:Rec;
    var varCache = new Map<String, Null<Float>>();
    static var uid = 0;

    public function new(rec:Rec, inf:Dynamic, dotHot:Bool) {
        this.rec = rec;
        this.inf = inf;
        this.dotHot = dotHot;
        id = str(rec.get(inf, "id"));
        type = rec.enumName("type", rec.get(inf, "type"));
        nature = rec.enumName("nature", rec.get(inf, "nature"));
        cooldown = num(rec.get(inf, "cooldown"));
        duration = num(rec.get(inf, "duration"));
        flags = Std.int(num(rec.get(inf, "flags")));
        vars = rec.get(inf, "vars");
        var props = rec.get(inf, "props");
        charges = Std.int(num(rec.get(props, "charges")));
        maxPoints = Std.int(num(rec.get(rec.get(props, "talent"), "maxPoints")));
        var cs = rec.get(props, "costs");
        for (i in 0...rec.len(cs)) {
            var c = rec.at(cs, i);
            var atb = ref(rec.get(c, "atb"));
            if (atb != "") costs.push({atb: atb, amount: num(rec.get(c, "amount"))});
        }
        var types = rec.get(rec.get(props, "status"), "types");
        for (i in 0...rec.len(types)) {
            var t = ref(rec.get(rec.at(types, i), "type"));
            if (t != "") statusTypes.push(t);
        }
        var so = rec.get(rec.get(props, "status"), "skillOverride");
        for (i in 0...rec.len(so)) {
            var o = ref(rec.get(rec.at(so, i), "skill"));
            if (o != "") overrides.push(o);
        }
        // HSkill.isDoT / isHoT: a status type flagged periodic damage or healing
        if (!dotHot && GameRules.typesFlag(statusTypes, 9)) dotHot = true;
        var ms0 = rec.get(rec.get(props, "status"), "maxStacks");
        if (ms0 != null && num(ms0) > 1) maxStacks = Std.int(num(ms0));
        else if (ms0 != null && num(ms0) < 0) maxStacks = 1000000; // -1: no limit
        var ro = rec.get(props, "rankOverride");
        for (i in 0...rec.len(ro)) {
            var o = rec.at(ro, i);
            rankOverride.push({minRank: Std.int(num(rec.get(o, "minRank"))), vars: rec.get(o, "vars")});
        }
        var subs = rec.get(props, "subskills");
        for (i in 0...rec.len(subs)) {
            var s = ref(rec.get(rec.at(subs, i), "skill"));
            if (s != "") subskills.push(s);
        }
        var rp = rec.get(props, "rankPassives");
        for (i in 0...rec.len(rp)) {
            var e = rec.at(rp, i);
            var ids:Array<String> = [];
            var list = rec.get(e, "passives");
            for (k in 0...rec.len(list)) { var id = ref(rec.get(rec.at(list, k), "ref")); if (id != "") ids.push(id); }
            rankPassives.push({minRank: Std.int(num(rec.get(e, "minRank"))), ids: ids});
        }
        var ms = rec.get(inf, "mastery");
        for (i in 0...rec.len(ms)) {
            var m = rec.at(ms, i);
            var p = rec.get(m, "props");
            var cd = rec.get(p, "cooldown"), du = rec.get(p, "duration"), ch = rec.get(p, "charges");
            masteries.push({id: str(rec.get(m, "id")), cooldown: cd == null ? null : num(cd), duration: du == null ? null : num(du),
                charges: ch == null ? null : Std.int(num(ch)), vars: rec.get(m, "vars")});
        }
        var refs = rec.get(rec.get(inf, "texts"), "refs");
        for (k in ["ref", "ref1", "ref2", "ref3", "ref4", "ref5", "ref6"]) {
            var r = ref(rec.get(refs, k));
            if (r != "" && refIds.indexOf(r) < 0) refIds.push(r);
        }
        var afx = rec.get(inf, "affixes");
        for (i in 0...rec.len(afx)) {
            var a = rec.at(afx, i);
            var c = rec.get(a, "conds");
            affixes.push({ref: ref(rec.get(a, "ref")), attr: ref(rec.get(rec.get(a, "target"), "attribute")), val: num(rec.get(a, "val")),
                minRank: intOr(rec.get(c, "minRank"), 0), maxRank: intOr(rec.get(c, "maxRank"), 999), equalRank: intOr(rec.get(c, "equalRank"), -1),
                mastery: ref(rec.get(c, "mastery")), dyn: Std.int(num(rec.get(rec.get(rec.get(a, "mod"), "dynVal"), "id"))),
                dynOp: Std.int(num(rec.get(rec.get(rec.get(a, "mod"), "dynVal"), "op")))});
        }
        var st = rec.get(inf, "steps");
        for (i in 0...rec.len(st)) {
            var s = rec.at(st, i);
            var c = rec.get(s, "cond");
            var p = rec.get(s, "props");
            var status = rec.get(p, "status");
            var effects:Array<SEffect> = [];
            var ef = rec.get(s, "effects");
            for (k in 0...rec.len(ef)) {
                var e = rec.at(ef, k);
                var sc:Array<SScaling> = [];
                var list = rec.get(e, "scaling");
                for (j in 0...rec.len(list)) {
                    var x = rec.at(list, j);
                    var xc = rec.get(x, "conds");
                    sc.push({atb: ref(rec.get(x, "atb")), ratio: num(rec.get(x, "ratio")), minRank: intOr(rec.get(xc, "minRank"), 0),
                        maxRank: intOr(rec.get(xc, "maxRank"), 999), equalRank: intOr(rec.get(xc, "equalRank"), -1)});
                }
                var affinity = ref(rec.get(e, "affinity"));
                effects.push({uid: uid++, kind: rec.enumName("effect", rec.get(e, "effect")), affinity: affinity, physical: Affinity.isPhysical(affinity),
                    base: num(rec.get(e, "baseVal")), scaling: sc, dynVal: Std.int(num(rec.get(e, "dynVal"))), status: ref(rec.get(e, "status")),
                    duration: rec.get(e, "duration"), raw: e, stackScale: (Std.int(num(rec.get(e, "flags"))) & 1) != 0});
            }
            var area = rec.get(p, "area");
            var stype = rec.enumName("stepType", rec.get(s, "type"));
            var rg = rec.get(s, "range");
            if (["Projectile", "Area", "EffectTarget", "Channel"].indexOf(stype) >= 0 && rg != null && (Std.isOfType(rg, Float) || Std.isOfType(rg, Int)))
                reach = Math.max(reach, num(rg));
            // st.skill.SkillStep.applyStatus: no target -> the step's current target; Self (0) -> the skill's owner
            var target = rec.get(status, "target");
            var loop = rec.get(p, "loop");
            steps.push({index: i, id: str(rec.get(s, "id")), on: rec.enumName("on", rec.get(s, "on")), type: rec.enumName("stepType", rec.get(s, "type")),
                mastery: ref(rec.get(c, "mastery")), masteryExclude: ref(rec.get(c, "masteryExclude")), minRank: intOr(rec.get(c, "minRank"), 0),
                maxRank: intOr(rec.get(c, "maxRank"), 999), equalRank: intOr(rec.get(c, "equalRank"), -1), delay: rec.get(s, "delay"),
                duration: rec.get(s, "duration"), tick: rec.get(loop, "tick"), targetCd: num(rec.get(area, "targetCooldown")),
                spread: (Std.int(num(rec.get(loop, "flags"))) & 1) != 0, hitFilter: Std.int(num(area != null ? rec.get(area, "hitFilter") : rec.get(rec.get(p, "projectile"), "hitFilter"))),
                ignoreMain: rec.get(area, "ignoreMainTarget") == true, presence: rec.get(area, "detectPresence") == true, status: ref(rec.get(status, "ref")), statusSelf: target != null && (num(target) == 0 || num(target) == 2), // Self; Group (the party: Battle Shout) holds the hero
                statusStacks: Std.int(num(rec.get(status, "stacks"))), condStep: ref(rec.get(c, "step")), travel: num(area != null ? rec.get(area, "travelTime") : rec.get(rec.get(p, "pickup"), "travelTime")), alignment: intOr(rec.get(c, "alignment"), -1), globalId: ref(rec.get(rec.get(p, "stepGlobal"), "globalId")),
                summon: ref(rec.get(rec.get(p, "summon"), "unit")), summonCount: Std.int(Math.max(1, num(rec.get(rec.get(p, "summon"), "count")))), effects: effects});
        }
        var src = str(rec.get(inf, "script"));
        scriptText = src;
        if (src != "") try script = Script.parse(src) catch (e:Dynamic) scriptError = Std.string(e);
    }

    function str(v:Dynamic):String return v == null ? "" : Std.string(v);

    /** An id from a reference that may be a plain id or a record. */
    function ref(v:Dynamic):String {
        if (v == null) return "";
        if (Std.isOfType(v, String)) return v;
        var id = rec.get(v, "id");
        return id == null ? Std.string(v) : Std.string(id);
    }

    static function num(v:Dynamic):Float {
        if (v == null) return 0;
        if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
        var f = Std.parseFloat(Std.string(v));
        return Math.isNaN(f) ? 0 : f;
    }

    static function intOr(v:Dynamic, d:Int):Int return v == null ? d : Std.int(num(v));

    /** The skill's variable at this rank with these runes: rune vars, then rank overrides, then its own. */
    public function v(name:String, rank:Int, runes:Array<String>):Null<Float> {
        if (name == null || name == "") return null;
        var key = name + "|" + rank + "|" + runes.join(",");
        if (varCache.exists(key)) return varCache.get(key);
        var out:Null<Float> = null;
        for (m in masteries) if (runes.indexOf(m.id) >= 0) {
            var x = rec.get(m.vars, name);
            if (x != null) { out = num(x); break; }
        }
        if (out == null) {
            var bestMin = -1;
            for (o in rankOverride) if (o.minRank <= rank && o.minRank > bestMin) {
                var x = rec.get(o.vars, name);
                if (x != null) { out = num(x); bestMin = o.minRank; }
            }
        }
        if (out == null) {
            var x = rec.get(vars, name);
            if (x != null) out = num(x);
        }
        varCache.set(key, out);
        return out;
    }

    /** A number of the data that may also be a variable name ("dur1"). */
    public function value(raw:Dynamic, rank:Int, runes:Array<String>, d:Float):Float {
        if (raw == null) return d;
        if (Std.isOfType(raw, String)) {
            var s:String = raw;
            if (s == "") return d;
            var f = Std.parseFloat(s);
            if (!Math.isNaN(f)) return f;
            var x = v(s, rank, runes);
            return x == null ? d : x;
        }
        return num(raw);
    }

    public function cooldownWith(runes:Array<String>):Float {
        for (m in masteries) if (runes.indexOf(m.id) >= 0 && m.cooldown != null) return m.cooldown;
        return cooldown;
    }

    public function durationWith(runes:Array<String>):Float {
        for (m in masteries) if (runes.indexOf(m.id) >= 0 && m.duration != null) return m.duration;
        return duration;
    }

    public function chargesWith(runes:Array<String>):Int {
        for (m in masteries) if (runes.indexOf(m.id) >= 0 && m.charges != null) return m.charges;
        return charges;
    }

    public static function rankOk(min:Int, max:Int, equal:Int, rank:Int):Bool
        return rank >= min && rank <= max && (equal < 0 || rank == equal);

    public function stepActive(s:SStep, rank:Int, runes:Array<String>):Bool {
        if (s.mastery != "" && runes.indexOf(s.mastery) < 0) return false;
        if (s.masteryExclude != "" && runes.indexOf(s.masteryExclude) >= 0) return false;
        return rankOk(s.minRank, s.maxRank, s.equalRank, rank);
    }

    public function affixActive(a:SAffix, rank:Int, runes:Array<String>):Bool {
        if (a.mastery != "" && runes.indexOf(a.mastery) < 0) return false;
        return rankOk(a.minRank, a.maxRank, a.equalRank, rank);
    }

    public function step(id:String):SStep {
        for (s in steps) if (s.id == id) return s;
        return null;
    }
}

/** Damage kinds by affinity (Data.affinity: each one Physical or Magic by itself or by its parent). */
class Affinity {
    public static var parents = new Map<String, String>();

    public static function isPhysical(a:String):Bool {
        var guard = 0;
        while (a != null && a != "" && guard++ < 5) {
            if (a == "Physical") return true;
            if (a == "Magic") return false;
            a = parents.get(a);
        }
        return false;
    }

    public static function isMagic(a:String):Bool return a != "" && a != "Raw" && !isPhysical(a);
}

/** A resource-like attribute (Data.attribute with maxAtb): its maximum, its gain factor, its regenerations. */
typedef SAttr = {id:String, max:String, gain:String, regen:Array<{atb:String, factor:Float, cond:String}>};

/**
 * Rules of the game's data the simulation needs besides skills, read once from the game (GameEnv) or from data.cdb
 * (tests): resource attributes, the parents of status types, constants (Data.constant).
 */
class GameRules {
    public static var attributes = new Map<String, SAttr>();
    public static var statusParents = new Map<String, String>();
    public static var constants = new Map<String, Dynamic>();

    static function id(rec:Rec, v:Dynamic):String {
        if (v == null) return "";
        if (Std.isOfType(v, String)) return v;
        var i = rec.get(v, "id");
        return i == null ? Std.string(v) : Std.string(i);
    }

    /** One line of Data.attribute: kept if it has a maximum (a resource: Spark, Rage, ComboPoint…). */
    public static function readAttribute(rec:Rec, line:Dynamic):Void {
        var max = id(rec, rec.get(line, "maxAtb"));
        if (max == "") return;
        var regen = [];
        var list = rec.get(line, "regenAtbs");
        for (i in 0...rec.len(list)) {
            var r = rec.at(list, i);
            var conds = rec.get(r, "conds");
            // the first condition the entry has (timeInCombat, timeOutsideCombat, target, waterState); "" none
            var cond = "";
            for (c in ["timeInCombat", "timeOutsideCombat", "target", "waterState"]) if (rec.get(conds, c) != null) { cond = c; break; }
            var f = rec.get(r, "factor");
            regen.push({atb: id(rec, rec.get(r, "atb")), factor: f == null ? 1.0 : Std.parseFloat(Std.string(f)), cond: cond});
        }
        var aid = id(rec, rec.get(line, "id"));
        attributes.set(aid, {id: aid, max: max, gain: id(rec, rec.get(line, "gainAtb")), regen: regen});
    }

    /** One line of Data.statusType: its parent type (Hemorage -> Bleed). */
    public static function readStatusType(rec:Rec, line:Dynamic):Void {
        var p = id(rec, rec.get(line, "parent"));
        if (p != "") statusParents.set(id(rec, rec.get(line, "id")), p);
        var fl = rec.get(line, "flags");
        if (fl != null) statusFlags.set(id(rec, rec.get(line, "id")), Std.int(Std.parseFloat(Std.string(fl))));
    }

    /** The flags of the status types (Data.statusType.flags: 1 periodic damage, 2 crowd control, 4 hard crowd control, 8 periodic healing). */
    public static var statusFlags = new Map<String, Int>();

    /** Some of the status types has one of the flags (HSkill.hasStatusFlag). */
    public static function typesFlag(types:Array<String>, flags:Int):Bool {
        for (t in types) if (statusFlags.exists(t) && (statusFlags.get(t) & flags) != 0) return true;
        return false;
    }

    /** One line of Data.constant: a number (v.float / v.int) or a list of numbers (v.floats[].v). */
    public static function readConstant(rec:Rec, line:Dynamic):Void {
        var v = rec.get(line, "v");
        if (v == null) return;
        var cid = id(rec, rec.get(line, "id"));
        var fl = rec.get(v, "floats");
        if (fl != null && rec.len(fl) > 0) {
            constants.set(cid, [for (i in 0...rec.len(fl)) Std.parseFloat(Std.string(rec.get(rec.at(fl, i), "v")))]);
            return;
        }
        var f = rec.get(v, "float");
        if (f == null) f = rec.get(v, "int");
        if (f != null) constants.set(cid, Std.parseFloat(Std.string(f)));
    }

    public static function constant(name:String):Float {
        var v:Dynamic = constants.get(name);
        return v == null || Std.isOfType(v, Array) ? 0 : v;
    }

    public static function constantList(name:String):Array<Float> {
        var v:Dynamic = constants.get(name);
        return Std.isOfType(v, Array) ? v : [];
    }

    /** A status type is `type` or one of its children (Hemorage is a Bleed). */
    public static function isType(types:Array<String>, type:String):Bool {
        for (t in types) {
            var cur = t, guard = 0;
            while (cur != null && cur != "" && guard++ < 8) {
                if (cur == type) return true;
                cur = statusParents.get(cur);
            }
        }
        return false;
    }
}
