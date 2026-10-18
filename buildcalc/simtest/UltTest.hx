import buildcalc.sim.Sim;
import SimTest;
class UltTest {
    static function main() {
        TalentTest.prepare();
        TalentTest.infs = [{id: "Infusion_Manfish_Support", rank: 3}];
        var sim = new Sim(TalentTest.env, 1);
        sim.setup(TalentTest.specs("Priest_Talent_Sunlight:1"));
        var r = sim.run(60);
        Sys.println("casts " + [for (id => n in r.casts) id + " " + n].join(", "));
        Sys.println("calls " + [for (k => n in sim.calls) if (k.indexOf("Manfish") >= 0) k + " x" + n].join("; "));
        Sys.println("missing " + [for (k => n in r.missing) k + " x" + n].join("; "));
        Sys.println("hero skills " + [for (s in sim.hero.skills) if (s.info.id.indexOf("Manfish") >= 0) s.info.id + "(" + s.info.type + " r" + s.rank + ")"].join(", "));
    }
}
