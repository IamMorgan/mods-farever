import buildcalc.sim.Sim;
import SimTest;
class MaceTest {
    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var worn = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
        var specs = [for (s in TalentTest.specs(worn)) if (s.slot != 0) s];
        var w = Sys.args().length > 0 ? Std.parseInt(Sys.args()[0]) : -1;
        for (id in ["Mace_Base_Attack", "Mace_Base_Attack2", "Mace_Base_Attack3", "Mace_Benediction_Combo", "Mace_Benediction_Skill1", "Mace_Benediction_Passive"])
            specs.push({id: id, rank: 3, runes: [], kind: "item", slot: 0, item: null, weave: id == "Mace_Benediction_Skill1" ? w : -1});
        var sim = new Sim(env, 1);
        sim.setup(specs);
        var r = sim.run(60);
        Sys.println("dps " + Math.round(r.dps));
        Sys.println("casts " + [for (id => n in r.casts) if (id.indexOf("Mace") >= 0) id + " " + n].join(", "));
        Sys.println("calls " + [for (k => n in sim.calls) if (k.indexOf("Mace") >= 0) k + " x" + n].join("; "));
        var parts = [for (id => d in r.damage) id + " " + Math.round(d / 60)];
        Sys.println("damage/s " + parts.join(", "));
        var crits = 0, n = 0;
        for (h in sim.log) if (h.inst.info.id == "Mace_Benediction_Combo" && h.kind == 0) { n++; }
        Sys.println("combo hits " + n + "; missing " + [for (k => v in r.missing) k + " x" + v].join("; "));
    }
}
