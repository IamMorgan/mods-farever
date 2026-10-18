package buildcalc;

typedef SkillEffect = {kind:String, base:Float, scaling:Array<{attr:String, ratio:Float}>, physical:Bool, perSecond:Float};

/**
 * The four axes of a build, from the computed attributes:
 *  - damage: Σ over the hero's damaging skills of (baseVal + Σ ratio × attribute) per second of
 *    cooldown, × crit (1 + chance × (crit damage − 1)) × mastery × penetration × DamageModifier;
 *  - healing: the same for heal and shield effects, × HealGivenMultiplier / ShieldPowerMultiplier, × crit;
 *  - defense: effective health factor 1 / ((1 − armor reduction) × DamageTakenModifier), armor reduction
 *    as the game computes it (GameObject.getAffinityDamageReduction): A / (A + F0 + F1 × level);
 *  - health: MaxHealth.
 */
class Scoring {
    public static inline var DAMAGE = 0;
    public static inline var DEFENSE = 1;
    public static inline var HEALTH = 2;
    public static inline var HEALING = 3;

    public var effects:Array<SkillEffect> = [];
    var engine:StatEngine;
    var armorF0 = 0.0;
    var armorF1 = 0.0;
    /** Armour of a typical target of the hero's level: the one with the game's expected reduction
        (Const.Attributes.Armor_ExpectedReduction R): R × k / (1 − R), k = F0 + F1 × level. */
    var targetArmor = 0.0;

    static function effectName(v:Dynamic):String {
        try return G.str(G.callStatic("_Data.Skill_steps_effects_effect_Impl_", "getName", [Std.int(G.num(v))])) catch (_:Dynamic) return Std.string(v);
    }

    public function new(engine:StatEngine, hero:Dynamic) {
        this.engine = engine;
        try {
            var f = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Attributes"), "ResistanceScalableReductionFormula");
            armorF0 = G.num(G.at(f, 0));
            armorF1 = G.num(G.at(f, 1));
            var r = G.num(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Attributes"), "Armor_ExpectedReduction"));
            var k = armorF0 + armorF1 * engine.level;
            if (r > 0 && r < 1) targetArmor = r * k / (1 - r);
            DebugLog.line("scoring: expected target reduction " + r + " -> target armour " + targetArmor);
        } catch (e:Dynamic) DebugLog.error("armor formula", e);
        var skills = G.field(hero, "skills");
        var summary = [];
        for (i in 0...G.len(skills)) {
            var inf = G.field(G.at(skills, i), "inf");
            var cd = G.num(G.field(inf, "cooldown"));
            var dur = G.num(G.field(inf, "duration"));
            var period = Math.max(cd, Math.max(dur, 0.5));
            var steps = G.field(inf, "steps");
            for (s in 0...G.len(steps)) {
                var effs = G.field(G.at(steps, s), "effects");
                for (e in 0...G.len(effs)) {
                    var ef = G.at(effs, e);
                    var kind = effectName(G.field(ef, "effect"));
                    if (kind != "Damage" && kind != "Heal" && kind != "Shield") continue;
                    var list = [];
                    var sc = G.field(ef, "scaling");
                    for (k in 0...G.len(sc)) {
                        var x = G.at(sc, k);
                        list.push({attr: G.str(G.field(x, "atb")), ratio: G.num(G.field(x, "ratio"))});
                    }
                    var physical = false;
                    try physical = G.callStatic("HSkill", "isPhysical", [G.field(ef, "affinity")]) == true catch (_:Dynamic) {}
                    effects.push({kind: kind, base: G.num(G.field(ef, "baseVal")), scaling: list, physical: physical, perSecond: 1 / period});
                    summary.push(G.str(G.field(inf, "id")) + ":" + kind + "[" + [for (l in list) l.attr + "*" + l.ratio].join(",") + "]/" + period + "s");
                }
            }
        }
        DebugLog.line("scoring: armor formula F0=" + armorF0 + " F1=" + armorF1 + "; " + effects.length + " effects: " + summary.join("  "));
    }

    function effectSum(vals:Array<Float>, kinds:Array<String>):Float {
        var sum = 0.0;
        for (e in effects) {
            if (kinds.indexOf(e.kind) < 0) continue;
            var v = e.base;
            for (s in e.scaling) v += s.ratio * engine.get(vals, s.attr);
            if (e.kind == "Damage") {
                // GameObject.getAffinityDamageReduction: armour × (1 − penetration), reduction = A / (A + F0 + F1 × level)
                var mastery = engine.get(vals, e.physical ? "PhysicalMastery" : "MagicMastery");
                var pen = Math.min(1, Math.max(0, engine.get(vals, e.physical ? "ArmorPenetration" : "SpellPenetration")));
                var a = targetArmor * (1 - pen);
                var k = armorF0 + armorF1 * engine.level;
                v *= (1 + mastery) * (1 - (a + k > 0 ? a / (a + k) : 0));
            }
            sum += Math.max(0, v) * e.perSecond;
        }
        return sum;
    }

    function crit(vals:Array<Float>):Float {
        var chance = Math.min(1, Math.max(0, engine.get(vals, "CritChance")));
        return 1 + chance * Math.max(0, engine.get(vals, "CritDamage") - 1);
    }

    /** The four axis values (damage, defense, health, healing). */
    public function axes(vals:Array<Float>):Array<Float> {
        var damage = effectSum(vals, ["Damage"]) * crit(vals) * Math.max(0.01, engine.get(vals, "DamageModifier"));
        var heal = effectSum(vals, ["Heal"]) * engine.get(vals, "HealGivenMultiplier") + effectSum(vals, ["Shield"]) * engine.get(vals, "ShieldPowerMultiplier");
        heal *= crit(vals);
        var armor = engine.get(vals, "Armor");
        var k = armorF0 + armorF1 * engine.level;
        var reduction = armor > 0 && armor + k > 0 ? armor / (armor + k) : 0;
        var taken = Math.max(0.05, (1 - reduction) * Math.max(0.05, engine.get(vals, "DamageTakenModifier")));
        return [damage, 1 / taken, engine.get(vals, "MaxHealth"), heal];
    }
}
