package buildcalc;

import buildcalc.sim.Sim;
import buildcalc.sim.SimData;
import buildcalc.sim.SimData.SkillInfo;
import buildcalc.sim.SimData.SAffix;
import buildcalc.sim.SimData.SEffect;
import buildcalc.StatEngine.Sums;
import buildcalc.Items.Candidate;

/** The game's data records as the simulation reads them. */
class GameRec implements Rec {
    public function new() {}
    public function get(r:Dynamic, field:String):Dynamic return G.field(r, field);
    public function len(list:Dynamic):Int return G.len(list);
    public function at(list:Dynamic, i:Int):Dynamic return G.at(list, i);
    public function enumName(kind:String, v:Dynamic):String {
        return switch (kind) {
            case "type": SkillData.typeName(v);
            case "on": SkillData.onName(v);
            case "stepType": SkillData.stepTypeName(v);
            case "effect": SkillData.effectName(v);
            default: G.str(v);
        }
    }
}

/** Attributes the simulation sees: raw values of StatEngine, displayed ones with the percentage factor. */
class GameStats implements StatsView {
    var engine:StatEngine;
    public var vals:Array<Float>;
    public function new(engine:StatEngine, vals:Array<Float>) {
        this.engine = engine;
        this.vals = vals;
    }
    public function get(name:String):Float return engine.get(vals, name);
    public function raw(name:String):Float {
        var i = engine.index.get(name);
        return i == null ? 0 : vals[i];
    }
}

/**
 * The simulation's view of the game for one build: skills from the game's data, the build's attributes
 * (StatEngine with the build's permanent bonuses, statuses on top), effect values as HSkill computes them
 * (the item's own power part from HSkill.getStepEffectItemScaling), the target's armour of the model.
 */
class GameEnv implements SimEnv {
    static var rec = new GameRec();
    static var skills = new Map<String, SkillInfo>();
    static var affinitiesRead = false;
    var model:Model;
    var perm:Sums;
    var statsCache = new Map<String, GameStats>();
    var itemPartCache:Map<String, Float>;

    public function new(model:Model, perm:Sums, itemPartCache:Map<String, Float>) {
        this.model = model;
        this.perm = perm;
        this.itemPartCache = itemPartCache;
        if (!affinitiesRead) {
            affinitiesRead = true;
            try {
                var all = G.field(GameData.data("affinity"), "all");
                for (i in 0...G.len(all)) {
                    var a = G.at(all, i);
                    var parent = GameData.idOf(G.field(a, "parent"));
                    if (parent != "") Affinity.parents.set(G.str(G.field(a, "id")), parent);
                }
            } catch (e:Dynamic) DebugLog.error("affinities", e);
            readRules();
        }
    }

    /** The game's rules the fight needs besides skills: resource attributes, status type parents, constants. */
    static function readRules():Void {
        for (sheet in ["attribute", "statusType", "constant"]) try {
            var all = G.field(GameData.data(sheet), "all");
            for (i in 0...G.len(all)) {
                var line = G.at(all, i);
                switch (sheet) {
                    case "attribute": GameRules.readAttribute(rec, line);
                    case "statusType": GameRules.readStatusType(rec, line);
                    default: GameRules.readConstant(rec, line);
                }
            }
        } catch (e:Dynamic) DebugLog.error("rules " + sheet, e);
        // constants the game keeps in Const.Classes (when Data.constant is not there)
        try {
            var classes = HlxRuntime.resolveStaticField(G.type("Const"), "Classes");
            for (name in ["Mage_Spark_SpellMinCost", "Mage_Spark_SpellCDCostRatio", "Mage_Spark_SpellCDCost_FinalCombo", "Mage_Conduit_SparkBounds", "Mage_Conduit_Levels"]) {
                if (GameRules.constants.exists(name)) continue;
                var v = G.field(classes, name);
                if (v == null) continue;
                if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) GameRules.constants.set(name, G.num(v));
                else GameRules.constants.set(name, [for (i in 0...G.len(v)) G.num(G.at(v, i))]);
            }
        } catch (e:Dynamic) DebugLog.error("rules Const.Classes", e);
        DebugLog.line("rules: " + Lambda.count(GameRules.attributes) + " resource attributes (" + [for (k in GameRules.attributes.keys()) k].join(",")
            + "), " + Lambda.count(GameRules.statusParents) + " status type parents, " + Lambda.count(GameRules.constants) + " constants");
    }

    public function heroLevel():Int return Std.int(model.engine.level);

    public function skill(id:String):SkillInfo {
        if (skills.exists(id)) return skills.get(id);
        var inf = GameData.skill(id);
        var s:SkillInfo = null;
        if (inf != null) try {
            var dot = false;
            try dot = G.callStatic("HSkill", "isDoT", [inf]) == true || G.callStatic("HSkill", "isHoT", [inf]) == true catch (_:Dynamic) {}
            s = new SkillInfo(rec, inf, dot);
            if (s.scriptError != "") DebugLog.line("sim: script of " + id + " not read: " + s.scriptError);
        } catch (e:Dynamic) DebugLog.error("sim skill " + id, e);
        skills.set(id, s);
        return s;
    }

    public function stats(buffs:Array<{a:SAffix, share:Float}>):StatsView {
        var key = [for (b in buffs) b.a.attr + b.a.ref + b.a.val + "x" + b.share].join(",");
        var s = statsCache.get(key);
        if (s != null) return s;
        var sums = perm;
        if (buffs.length > 0) {
            sums = perm.copy();
            for (b in buffs) sums.affix(model.engine.index, b.a.ref, b.a.attr, b.a.val, b.share);
        }
        s = new GameStats(model.engine, model.engine.evaluate(sums));
        statsCache.set(key, s);
        return s;
    }

    public function effectBase(inst:Inst, e:SEffect, stats:StatsView):Float {
        var item:Candidate = inst.item;
        var out = e.base;
        var r = item != null ? item.powerRatio : 0.0;
        if (r > 0) out += itemPart(inst, item, e, r);
        var engine = model.engine;
        for (sc in e.scaling) {
            if (!SkillInfo.rankOk(sc.minRank, sc.maxRank, sc.equalRank, inst.rank)) continue;
            var ratio = sc.ratio;
            if (r > 0 && model.itemScaled(sc.atb)) ratio *= (1 - r);
            if (sc.atb == "AllAttributes") {
                var n = engine.mainAttributes.length;
                if (n > 0) for (i in engine.mainAttributes) out += stats.raw(engine.names[i]) * ratio / n;
            } else if (sc.atb == "WeaponPower" && item != null && item.aptAtbs.length > 0) {
                for (a in item.aptAtbs) out += stats.raw(a) * ratio / item.aptAtbs.length;
            } else out += stats.raw(sc.atb) * ratio;
        }
        return out;
    }

    function itemPart(inst:Inst, item:Candidate, e:SEffect, ratio:Float):Float {
        // by the candidate (its key), not its id: an owned +3 censer and a created +5 one have other item data
        var key = "sim|" + item.key + "|" + inst.rank + "|" + inst.info.id + "|" + e.uid;
        if (itemPartCache.exists(key)) return itemPartCache.get(key);
        var v = 0.0;
        try {
            var info = {inf: inst.info.inf, rank: inst.rank, maxRank: null, masteries: inst.runes, heroic: false};
            v = G.num(G.callStatic("HSkill", "getStepEffectItemScaling", [info, e.raw, item.inf, ratio]));
        } catch (err:Dynamic) DebugLog.error("item part " + inst.info.id, err);
        itemPartCache.set(key, v);
        return v;
    }

    public function armorReduction(armor:Float):Float return model.reduction(armor);

    public function targetArmor(physical:Bool):Float return model.foeArmor(physical);

    public function targetTaken(physical:Bool):Float return model.foeTaken(physical);

    var defenseCache = new Map<String, Array<Float>>();

    /**
     * The target's armour (magic armour) and what is left of a hit after it, with the affixes of its statuses:
     * Armor / MagicArmor (flat, ratios), DamageTakenModifier, MagicReduction, Resilience (the game's damage taken
     * formula, see Model.defense).
     */
    public function targetDefense(physical:Bool, buffs:Array<{a:SAffix, share:Float}>):Array<Float> {
        if (buffs.length == 0) return [targetArmor(physical), targetTaken(physical)];
        var key = (physical ? "p" : "m") + [for (b in buffs) b.a.attr + b.a.ref + b.a.val + "x" + b.share].join(",");
        var c = defenseCache.get(key);
        if (c != null) return c;
        var armorAtb = physical ? "Armor" : "MagicArmor";
        var armor = targetArmor(physical), armorAdd = 0.0, armorMul = 1.0;
        var takenAdd = 0.0, takenMul = 1.0, magicRed = 0.0, resil = 0.0;
        var engine = model.engine;
        for (b in buffs) {
            var i = engine.index.get(b.a.attr);
            var pc = i == null ? 1.0 : engine.percent(i);
            var flat = b.a.val * b.share * pc;
            switch [b.a.attr, b.a.ref] {
                case [a, "TAttribute_Flat"] if (a == armorAtb): armor += flat;
                case [a, "TAttribute_ARatio"] if (a == armorAtb): armorAdd += b.a.val * b.share;
                case [a, "TAttribute_MRatio"] if (a == armorAtb): armorMul *= Math.pow(b.a.val, b.share);
                case ["DamageTakenModifier", "TAttribute_Flat"]: takenAdd += flat;
                case ["DamageTakenModifier", "TAttribute_ARatio"]: takenAdd += b.a.val * b.share;
                case ["DamageTakenModifier", "TAttribute_MRatio"]: takenMul *= Math.pow(b.a.val, b.share);
                case ["MagicReduction", "TAttribute_Flat"]: magicRed += flat;
                case ["Resilience", "TAttribute_Flat"]: resil += flat;
                default:
            }
        }
        armor = Math.max(0, armor * (1 + armorAdd) * armorMul);
        var taken = targetTaken(physical) * Math.max(0, 1 + takenAdd) * takenMul * Math.max(0, 1 - resil);
        if (!physical) taken *= Math.max(0, 1 - magicRed);
        c = [armor, taken];
        defenseCache.set(key, c);
        return c;
    }
}
