import buildcalc.sim.Sim;
import buildcalc.sim.SimData;
import buildcalc.sim.SimData.SkillInfo;
import buildcalc.sim.SimData.SAffix;
import buildcalc.sim.SimData.SEffect;

/** data.cdb's JSON as the simulation's data source. */
class JsonRec implements Rec {
    public var enums = new Map<String, Array<String>>();
    public function new() {}
    public function get(r:Dynamic, field:String):Dynamic return r == null ? null : Reflect.field(r, field);
    public function len(list:Dynamic):Int return list == null ? 0 : (list : Array<Dynamic>).length;
    public function at(list:Dynamic, i:Int):Dynamic return (list : Array<Dynamic>)[i];
    public function enumName(kind:String, v:Dynamic):String {
        if (v == null) return "";
        var names = enums.get(kind);
        var i = Std.int(v);
        return names != null && i >= 0 && i < names.length ? names[i] : Std.string(v);
    }
}

/** Fixed attributes of the hero (as the game showed them), buffs added on top. */
class TestStats implements StatsView {
    public var vals:Map<String, Float>;
    public function new(v:Map<String, Float>) vals = v;
    public function get(name:String):Float return vals.exists(name) ? vals.get(name) : 0;
    public function raw(name:String):Float return get(name);
}

class TestEnv implements SimEnv {
    /** Attributes with Data.attribute flag 8192 (read from data.cdb by main). */
    public static var MAIN:Array<String> = [];
    var skills:Map<String, SkillInfo> = new Map();
    var data:Map<String, Dynamic>;
    var rec:JsonRec;
    var base:Map<String, Float>;
    public function new(rec:JsonRec, data:Map<String, Dynamic>, base:Map<String, Float>) {
        this.rec = rec;
        this.data = data;
        this.base = base;
    }
    public function skill(id:String):SkillInfo {
        if (skills.exists(id)) return skills.get(id);
        var inf = data.get(id);
        var s:SkillInfo = null;
        if (inf != null) {
            var fl:Dynamic = rec.get(rec.get(rec.get(inf, "props"), "status"), "statusFlags"); var flags = fl == null ? 0 : Std.int(fl);
            s = new SkillInfo(rec, inf, (flags & 3) != 0);
            if (s.scriptError != "") Sys.println("script error " + id + ": " + s.scriptError);
        }
        skills.set(id, s);
        return s;
    }
    public function stats(buffs:Array<{a:SAffix, share:Float}>):StatsView {
        var v = base.copy();
        for (b in buffs) {
            var cur = v.exists(b.a.attr) ? v.get(b.a.attr) : 0;
            switch (b.a.ref) {
                case "TAttribute_Flat": v.set(b.a.attr, cur + b.a.val * b.share * (pct(b.a.attr) ? 0.01 : 1));
                case "TAttribute_ARatio": v.set(b.a.attr, cur * (1 + b.a.val * b.share));
                case "TAttribute_MRatio": v.set(b.a.attr, cur * Math.pow(b.a.val, b.share));
                default:
            }
        }
        return new TestStats(v);
    }
    static function pct(a:String):Bool return ["CritChance", "CritDamage", "Fervor", "MagicMastery", "PhysicalMastery", "CooldownReduction", "SpellPenetration", "ArmorPenetration", "DodgeChance"].indexOf(a) >= 0;
    public function effectBase(inst:Inst, e:SEffect, stats:StatsView):Float {
        var out = e.base;
        for (sc in e.scaling) {
            if (!SkillInfo.rankOk(sc.minRank, sc.maxRank, sc.equalRank, inst.rank)) continue;
            if (sc.atb == "AllAttributes") {
                // HSkill.getStepEffectScaling: the mean of the attributes flagged 8192 (Data.attribute)
                for (m in MAIN) out += stats.raw(m) * sc.ratio / MAIN.length;
                continue;
            }
            var atb = sc.atb == "WeaponPower" ? "Faith" : sc.atb;
            out += stats.raw(atb) * sc.ratio;
        }
        return out;
    }
    public function armorReduction(armor:Float):Float { var k = 385 + 100 * 25; return armor / (armor + k); }
    public function targetArmor(physical:Bool):Float return 962;
    public function targetTaken(physical:Bool):Float return 1;
    public function heroLevel():Int return 25;
    public function targetDefense(physical:Bool, buffs:Array<{a:SAffix, share:Float}>):Array<Float> {
        var taken = 1.0;
        for (b in buffs) if (b.a.attr == "DamageTakenModifier" && b.a.ref == "TAttribute_ARatio") taken += b.a.val * b.share;
        return [962, taken];
    }
}

class SimTest {
    static function main() {
        var cdb:Dynamic = haxe.Json.parse(sys.io.File.getContent("C:/Users/bugid/AppData/Local/Temp/claude/C--mods/65421b85-09b5-4064-baec-72e7120c6ba5/scratchpad/data/data.cdb"));
        var rec = new JsonRec();
        var data = new Map<String, Dynamic>();
        for (s in (cdb.sheets : Array<Dynamic>)) {
            var name:String = s.name;
            if (name == "skill") for (l in (s.lines : Array<Dynamic>)) data.set(l.id, l);
            if (name == "affinity") for (l in (s.lines : Array<Dynamic>)) if (l.parent != null) Affinity.parents.set(l.id, l.parent);
            if (name == "attribute") for (l in (s.lines : Array<Dynamic>)) if (l.flags != null && (Std.int(l.flags) & 8192) != 0) TestEnv.MAIN.push(l.id);
            if (name == "attribute") for (l in (s.lines : Array<Dynamic>)) buildcalc.sim.SimData.GameRules.readAttribute(rec, l);
            if (name == "statusType") for (l in (s.lines : Array<Dynamic>)) buildcalc.sim.SimData.GameRules.readStatusType(rec, l);
            if (name == "constant") for (l in (s.lines : Array<Dynamic>)) buildcalc.sim.SimData.GameRules.readConstant(rec, l);
            if (name == "skill" || name == "skill@steps" || name == "skill@steps@effects") for (c in (s.columns : Array<Dynamic>)) {
                var ts:String = c.typeStr;
                if (ts == null || ts.indexOf("5:") != 0) continue;
                var list = ts.substr(2).split(",");
                var key = switch ([name, (c.name : String)]) {
                    case ["skill", "type"]: "type";
                    case ["skill", "nature"]: "nature";
                    case ["skill@steps", "on"]: "on";
                    case ["skill@steps", "type"]: "stepType";
                    case ["skill@steps@effects", "effect"]: "effect";
                    default: "";
                };
                if (key != "") rec.enums.set(key, list);
            }
        }
        // the priest as the game shows him (2026-10-17)
        var base = [
            "Vitality" => 230.0, "Strength" => 38.0, "Dexterity" => 28.0, "Faith" => 176.4, "Intellect" => 30.0, "MaxHealth" => 744.0,
            "Armor" => 1250.0, "CritChance" => 0.183, "CritDamage" => 1.515, "Fervor" => 0.25, "MagicMastery" => 0.06, "PhysicalMastery" => 0.0,
            "SpellPenetration" => 0.17, "ArmorPenetration" => 0.02, "CooldownReduction" => 0.05, "DamageModifier" => 1.0,
            "HealGivenMultiplier" => 1.25, "ShieldPowerMultiplier" => 1.25, "HealthRegen" => 7.0
        ];
        var env = new TestEnv(rec, data, base);
        var specs:Array<SkillSpec> = [];
        function add(id:String, kind:String, slot:Int, rank:Int = 1, ?runes:Array<String>) specs.push({id: id, rank: rank, runes: runes == null ? [] : runes, kind: kind, slot: slot, item: null});
        for (id in ["Scepter_Base_Attack", "Scepter_Flamie_Combo", "Scepter_Flamie_Skill1", "Scepter_Flamie_S2", "Scepter_Flamie_P"]) add(id, "item", 0, 3);
        for (id in ["Staff_Censer_Skill1", "Staff_Censer_Skill2"]) add(id, "arsenal", 1, 2);
        add("Enchant_Lifestealing", "enchant", 0);
        add("Enchant_Devote", "enchant", 1);
        add("Priest_FaithfulWinds", "class", -1, 1, ["Priest_FaithfulWinds_M1"]);
        add("Priest_RadiantVerdict", "class", -1, 1, ["Priest_RadiantVerdict_M3"]);
        add("Priest_BlessingOfFervor", "class", -1, 1, ["Priest_BlessingOfFervor_M2"]);
        add("Priest_Crusader", "class", -1, 1, ["Priest_Crusader_M3"]);
        add("Priest_BeaconOfHope", "class", -1);
        for (id in ["Priest_Sig_DivineIntervention", "Priest_Prayer_Life", "Priest_Prayer_Smite", "Priest_Prayer_Shield", "Priest_Rosary", "RiftstalkersReputation_Skill"]) add(id, "hero", -1);
        for (t in ["Priest_Talent_PurgingStrikes:1", "Priest_Talent_Sunlight:1", "Priest_Talent_PiercingLight:1", "Priest_Talent_MightyExecutioner:2",
                "Priest_Talent_FerventDefender:2", "Priest_Talent_SolarDevotion:1", "Priest_Talent_ZealousFighter:2", "Priest_Talent_SwiftJustice:1",
                "Priest_Talent_SoothingRays:1", "Priest_Talent_PiousAdept:2", "Priest_Talent_Radiance:2", "Priest_Talent_SunHalo:1"]) {
            var p = t.split(":");
            add(p[0], "talent", -1, Std.parseInt(p[1]));
        }
        add("Infusion_Manfish_Support", "infusion", -1, 2);
        var t0 = haxe.Timer.stamp();
        var sim = new Sim(env);
        sim.setup(specs);
        var r = sim.run(60);
        Sys.println("time " + Math.round((haxe.Timer.stamp() - t0) * 1000) + " ms; dps " + Math.round(r.dps) + ", self heal " + Math.round(r.selfHeal) + "/s");
        var lines = [for (id => v in r.damage) {id: id, v: v}];
        lines.sort((a, b) -> a.v > b.v ? -1 : 1);
        for (l in lines) Sys.println("  dmg " + l.id + ": " + Math.round(l.v / 60) + "/s");
        for (id => v in r.heal) Sys.println("  heal " + id + ": " + Math.round(v / 60) + "/s");
        Sys.println("casts: " + [for (id => n in r.casts) id + " " + n].join(", "));
        // per skill: hits and the mean hit without the critical part (to set against the dps meter's non-critical hits)
        var per = new Map<String, {n:Int, sum:Float, mult:Float, ign:Float, step:String}>();
        for (h in sim.log) if (h.kind == 0) {
            var cc = h.crit ? Math.min(1, Math.max(0, base.get("CritChance") + h.ccAdd)) : 0.0;
            var nc = h.amount / (1 + cc * Math.max(0, base.get("CritDamage") + h.cdAdd - 1));
            var id = h.inst.info.id;
            if (!per.exists(id)) per.set(id, {n: 0, sum: 0, mult: 0, ign: 0, step: ""});
            var p = per.get(id);
            p.n++;
            p.sum += nc;
            p.mult += h.mult;
            p.ign += h.ignore;
            p.step = "base " + h.e.base + " scaling " + [for (sc in h.e.scaling) sc.atb + "*" + sc.ratio].join("+") + " split " + h.split + " aff " + h.e.affinity;
        }
        for (id => p in per) Sys.println("  hit " + id + ": " + p.n + " hits, non-crit mean " + Math.round(p.sum / p.n) + ", mult " + Math.round(p.mult / p.n * 1000) / 1000
            + ", ignore " + Math.round(p.ign / p.n * 100) + "%, " + p.step);
        Sys.println("statuses at the end: hero " + [for (st in sim.hero.statuses) st.info.id + "x" + st.stacks].join(",") + " | dummy " + [for (st in sim.dummy.statuses) st.info.id + "x" + st.stacks].join(","));
        var same = sim.replay(env);
        Sys.println("replay same: dps " + Math.round(same.dps) + ", self heal " + Math.round(same.selfHeal) + ", ally heal " + Math.round(same.allyHeal) + "; timing attrs " + [for (k => v in sim.timing) k].join(","));
        var base2 = base.copy();
        base2.set("Faith", base.get("Faith") * 1.1);
        base2.set("CritChance", base.get("CritChance") + 0.05);
        var env2 = new TestEnv(rec, data, base2);
        var t1 = haxe.Timer.stamp();
        var rep = sim.replay(env2);
        Sys.println("replay faith+10%, crit+5: dps " + Math.round(rep.dps) + ", self heal " + Math.round(rep.selfHeal) + " (" + Math.round((haxe.Timer.stamp() - t1) * 1000) + " ms, " + sim.log.length + " hits)");
        for (seed in [1, 2, 3]) {
            var sim2 = new Sim(env2, seed);
            sim2.setup(specs);
            sim2.run(60);
            var full = sim2.replay(env2);
            Sys.println("full sim faith+10%, crit+5 (seed " + seed + "): dps " + Math.round(full.dps) + ", self heal " + Math.round(full.selfHeal) + " | " + [for (id => v in full.heal) id + " " + Math.round(v / 60)].join(", "));
        }
        var miss = [for (k => n in r.missing) {k: k, n: n}];
        miss.sort((a, b) -> b.n - a.n);
        var cl = [for (k => n in sim.calls) {k: k, n: n}];
        cl.sort((a, b) -> b.n - a.n);
        Sys.println("calls: " + [for (i in 0...Std.int(Math.min(80, cl.length))) cl[i].k + " x" + cl[i].n].join("; "));
        Sys.println("missing: " + [for (m in miss) m.k + " x" + m.n].join("; "));
    }
}
