import buildcalc.sim.Sim;
import SimTest;
class SunTest {
    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var items:Array<Dynamic> = [];
        for (s in (TalentTest.cdb.sheets : Array<Dynamic>)) if (s.name == "item") items = s.lines;
        var worn = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
        for (id in ["Scepter_Flamie", "Sword_Craft", "Mace_Benediction"]) {
            var it:Dynamic = Lambda.find(items, x -> x.id == id);
            var specs = [for (s in TalentTest.specs(worn)) if (s.slot != 0) s];
            for (e in (it.skills : Array<Dynamic>)) specs.push({id: e.skill, rank: 3, runes: [], kind: "item", slot: 0, item: null});
            var sim = new Sim(env, 1);
            sim.setup(specs);
            var r = sim.run(60);
            var sun = 0, combo = 0;
            for (h in sim.log) if (h.kind == 0) { if (h.inst.info.id == "Priest_Talent_Sunlight_Status") sun++; if (h.inst.info.type == "AttackCombo") combo++; }
            Sys.println(id + ": dps " + Math.round(r.dps) + ", combo hits " + combo + ", sunlight hits " + sun + ", sunlight dps " + Math.round(r.damage.get("Priest_Talent_Sunlight_Status") / 60)
                + " | casts " + [for (k => n in r.casts) if (k.indexOf("Priest") < 0) k + " " + n].join(", "));
        }
    }
}
