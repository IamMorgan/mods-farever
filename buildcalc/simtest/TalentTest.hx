import buildcalc.sim.Sim;
import buildcalc.sim.SimData;
import SimTest;

/**
 * What each talent is worth in the simulation: the worn and the suggested talents of the debug log (2026-10-17),
 * each talent taken away in turn; dps / self heal averaged over several seeds.
 */
class TalentTest {
    public static var env:TestEnv;
    public static var cdb:Dynamic;
    static var base:Map<String, Float>;
    /** Infusion sets (rank = how many of 2/4/6 items, Const.Items.Item_InfusionCaps). */
    public static var infs:Array<{id:String, rank:Int}> = [{id: "Infusion_Manfish_Support", rank: 3}];
    /** "real": only the skills the player used at the dummy (dps-meter log): no Faithful Winds, Radiant Verdict, Beacon of Hope. */
    static var real = Sys.args().indexOf("real") >= 0;
    /** The optimizer's second rotation: the class skills with no damage left out (Model.isUtility). */
    static var utilityOnly = false;

    public static function specs(talents:String):Array<SkillSpec> {
        var out:Array<SkillSpec> = [];
        function add(id:String, kind:String, slot:Int, rank:Int = 1, ?runes:Array<String>) if (!real || (utilityOnly ? ["Priest_FaithfulWinds", "Priest_BlessingOfFervor", "Priest_Crusader", "Priest_BeaconOfHope"] : ["Priest_FaithfulWinds", "Priest_RadiantVerdict", "Priest_BeaconOfHope"]).indexOf(id) < 0) out.push({id: id, rank: rank, runes: runes == null ? [] : runes, kind: kind, slot: slot, item: null});
        for (id in ["Scepter_Base_Attack", "Scepter_Flamie_Combo", "Scepter_Flamie_Skill1", "Scepter_Flamie_S2", "Scepter_Flamie_P"]) add(id, "item", 0, 3);
        for (id in ["Staff_Censer_Skill1", "Staff_Censer_Skill2"]) add(id, "arsenal", 1, 3);
        add("Enchant_Lifestealing", "enchant", 0);
        add("Enchant_Devote", "enchant", 1);
        add("Priest_FaithfulWinds", "class", -1, 1, ["Priest_FaithfulWinds_M1"]);
        add("Priest_RadiantVerdict", "class", -1, 1, ["Priest_RadiantVerdict_M3"]);
        add("Priest_BlessingOfFervor", "class", -1, 1, ["Priest_BlessingOfFervor_M1"]);
        add("Priest_Crusader", "class", -1, 1, ["Priest_Crusader_M3"]);
        add("Priest_BeaconOfHope", "class", -1);
        for (id in ["Priest_Sig_DivineIntervention", "Priest_Prayer_Life", "Priest_Prayer_Smite", "Priest_Prayer_Shield", "Priest_Rosary", "RiftstalkersReputation_Skill"]) add(id, "hero", -1);
        if (talents != "") for (t in talents.split(",")) {
            var p = t.split(":");
            add(p[0], "talent", -1, Std.parseInt(p[1]));
        }
        for (i in infs) {
            var d = env.skill(i.id);
            add(i.id, "infusion", -1, i.rank);
            if (d != null) for (sub in d.subskills) add(sub, "infusion", -1, i.rank);
        }
        return out;
    }

    static function value(talents:String):Array<Float> {
        var dps = 0.0, heal = 0.0, n = 6;
        for (seed in 1...n + 1) {
            var sim = new Sim(env, seed);
            sim.setup(specs(talents));
            var r = sim.run(60);
            dps += r.dps;
            heal += r.selfHeal;
        }
        return [dps / n, heal / n];
    }

    static function table(name:String, talents:String):Void {
        var all = value(talents);
        Sys.println(name + ": dps " + Math.round(all[0]) + ", self heal " + Math.round(all[1]));
        var list = talents.split(",");
        for (t in list) {
            var rest = [for (o in list) if (o != t) o].join(",");
            var v = value(rest);
            Sys.println("  without " + t + ": dps " + Math.round(all[0] - v[0]) + ", heal " + Math.round(all[1] - v[1]));
        }
    }

    public static function prepare():Void {
        cdb = haxe.Json.parse(sys.io.File.getContent("C:/Users/bugid/AppData/Local/Temp/claude/C--mods/65421b85-09b5-4064-baec-72e7120c6ba5/scratchpad/data/data.cdb"));
        var rec = new JsonRec();
        var data = new Map<String, Dynamic>();
        for (s in (cdb.sheets : Array<Dynamic>)) {
            var name:String = s.name;
            if (name == "skill") for (l in (s.lines : Array<Dynamic>)) data.set(l.id, l);
            if (name == "affinity") for (l in (s.lines : Array<Dynamic>)) if (l.parent != null) buildcalc.sim.SimData.Affinity.parents.set(l.id, l.parent);
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
        // the hero now (the calculator's screen, 2026-10-17)
        base = [
            "Vitality" => 252.0, "Strength" => 37.0, "Dexterity" => 28.0, "Faith" => 187.0, "Intellect" => 46.0, "MaxHealth" => 756.0,
            "Armor" => 1214.0, "CritChance" => 0.201, "CritDamage" => 1.517, "Fervor" => 0.266, "MagicMastery" => 0.02, "PhysicalMastery" => 0.0,
            "SpellPenetration" => 0.166, "ArmorPenetration" => 0.0, "CooldownReduction" => 0.08, "DamageModifier" => 1.0,
            "HealGivenMultiplier" => 1.266, "ShieldPowerMultiplier" => 1.266, "HealthRegen" => 7.5,
            // resources of the classes (Data.unit of the class: MaxSpark 100, MaxRage 20, MaxComboPoint 4; SparkRegen = 0.005 × MaxSpark)
            "MaxSpark" => 100.0, "SparkRegen" => 0.5, "MaxRage" => 20.0, "RageRegen" => -1.0, "RageGainFactor" => 1.0, "MaxComboPoint" => 4.0
        ];
        env = new TestEnv(rec, data, base);
    }

    static function main() {
        prepare();
        if (Sys.args().indexOf("cmp") >= 0) {
            var worn = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
            var chosen = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_FerventDefender:2,Priest_Talent_BurningRays:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Prosecutor:1,Priest_Talent_Radiance:2";
            utilityOnly = true;
            real = true;
            var ua = value(worn), ub = value(chosen);
            Sys.println("optimizer's second rotation (no utility class skills): worn dps " + Math.round(ua[0]) + " heal " + Math.round(ua[1]) + " | suggested dps " + Math.round(ub[0]) + " heal " + Math.round(ub[1]));
            utilityOnly = false;
            for (r in [false, true]) {
                real = r;
                var a = value(worn), b = value(chosen);
                Sys.println((r ? "without Faithful Winds/Radiant Verdict/Beacon" : "all skills") + ": worn dps " + Math.round(a[0]) + " heal " + Math.round(a[1])
                    + " | suggested dps " + Math.round(b[0]) + " heal " + Math.round(b[1]));
            }
            return;
        }
        if (Sys.args().indexOf("inf") >= 0) {
            var t = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
            var keep = base.copy();
            for (o in [
                {name: "none", sets: []},
                {name: "Manfish x6 (r3)", sets: [{id: "Infusion_Manfish_Support", rank: 3}]},
                {name: "Manfish x4 (r2)", sets: [{id: "Infusion_Manfish_Support", rank: 2}]},
                {name: "Crimson x4 + Manfish x4", sets: [{id: "Infusion_Crimson_Support", rank: 2}, {id: "Infusion_Manfish_Support", rank: 2}]},
                {name: "Crimson x6 + Manfish x2", sets: [{id: "Infusion_Crimson_Support", rank: 3}, {id: "Infusion_Manfish_Support", rank: 1}]},
                {name: "Manfish x6 + Crimson x2", sets: [{id: "Infusion_Manfish_Support", rank: 3}, {id: "Infusion_Crimson_Support", rank: 1}]},
                {name: "Crimson x6 (r3)", sets: [{id: "Infusion_Crimson_Support", rank: 3}]},
                {name: "Manfish x6 + Kobold DPS x2", sets: [{id: "Infusion_Manfish_Support", rank: 3}, {id: "Infusion_Kobold_DPS", rank: 1}]},
            ]) {
                infs = o.sets;
                // the set affixes (rank 2+: +2.5 Fervor for Crimson / Manfish support, +2.5% crit for Kobold DPS) are permanent attributes: added here
                for (k => v in keep) base.set(k, v);
                for (i in o.sets) if (i.rank >= 2) {
                    if (i.id == "Infusion_Kobold_DPS") base.set("CritChance", base.get("CritChance") + 0.025);
                    else for (k in ["Fervor", "HealGivenMultiplier", "ShieldPowerMultiplier"]) base.set(k, base.get(k) + 0.025);
                }
                var v = value(t);
                var sim = new Sim(env, 1);
                sim.setup(specs(t));
                var r = sim.run(60);
                var parts = [for (id => d in r.damage) {id: id, d: d}];
                parts.sort((x, y) -> x.d > y.d ? -1 : 1);
                Sys.println("   " + [for (p in parts) p.id.split("_").slice(-2).join("_") + " " + Math.round(p.d / 60)].join(", "));
                Sys.println("   heal " + [for (id => h in r.heal) id.split("_").slice(-2).join("_") + " " + Math.round(h / 60)].join(", ") + " | casts " + [for (id => n in r.casts) if (id.indexOf("Infusion") >= 0) id + " " + n].join(","));
                Sys.println(o.name + ": dps " + Math.round(v[0] * 10) / 10 + ", self heal " + Math.round(v[1] * 10) / 10);
            }
            for (k => v in keep) base.set(k, v);
            return;
        }
        if (Sys.args().indexOf("stat") >= 0) {
            var t = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
            var b0 = value(t);
            var keep = base.copy();
            base.set("Faith", keep.get("Faith") + 4);
            var bf = value(t);
            for (k => v in keep) base.set(k, v);
            // 13 Fervor rating = +0.684% Fervor (the game's rating curve at level 25, from the mod's log); Fervor is in the heal and shield multipliers too
            for (k in ["Fervor", "HealGivenMultiplier", "ShieldPowerMultiplier"]) base.set(k, keep.get(k) + 0.00684);
            var bv = value(t);
            for (k => v in keep) base.set(k, v);
            Sys.println("base dps " + Math.round(b0[0] * 10) / 10 + " heal " + Math.round(b0[1] * 10) / 10);
            Sys.println("+4 Faith: dps +" + Math.round((bf[0] - b0[0]) * 10) / 10 + " (" + Math.round((bf[0] / b0[0] - 1) * 1000) / 10 + "%), heal +" + Math.round((bf[1] - b0[1]) * 10) / 10 + " (" + Math.round((bf[1] / b0[1] - 1) * 1000) / 10 + "%)");
            Sys.println("+13 Fervor rating: dps +" + Math.round((bv[0] - b0[0]) * 10) / 10 + " (" + Math.round((bv[0] / b0[0] - 1) * 1000) / 10 + "%), heal +" + Math.round((bv[1] - b0[1]) * 10) / 10 + " (" + Math.round((bv[1] / b0[1] - 1) * 1000) / 10 + "%)");
            return;
        }
        var worn = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
        for (t in [worn, StringTools.replace(worn, ",Priest_Talent_SolarDevotion:1", "")]) {
            var sim = new Sim(env, 1);
            sim.setup(specs(t));
            var r = sim.run(60);
            var hits = 0;
            for (h in sim.log) if (h.inst.info.id == "Priest_Talent_Sunlight_Status" && h.kind == 0) hits++;
            Sys.println("sunlight hits " + hits + ", applies " + sim.calls.get("Priest_Talent_Sunlight.onInflictHit") + ", combos " + r.casts.get("Scepter_Flamie_Combo") + (t == worn ? " (with Solar Devotion)" : " (without)"));
        }
        if (Sys.args().indexOf("table") < 0) return;
        table("worn", "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1");
        table("suggested", "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_MeltingFaith:1,Priest_Talent_OppressiveRays:2,Priest_Talent_PiercingLight:2,Priest_Talent_FerventDefender:2,Priest_Talent_SunHalo:1,Priest_Talent_BurningRays:1,Priest_Talent_SoothingRays:1,Priest_Talent_SwiftJustice:1,Priest_Talent_Radiance:2,Priest_Talent_SharpMind:1");
    }
}
