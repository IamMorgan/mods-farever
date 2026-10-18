import buildcalc.sim.Sim;
import SimTest;
class FindCrash2 {
    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var all = Sys.args();
        for (skip in [""].concat(all)) {
            var specs:Array<SkillSpec> = [for (id in all) if (id != skip) {id: id, rank: 3, runes: [], kind: "item", slot: 0, item: null}];
            try {
                var sim = new Sim(env, 1);
                sim.setup(specs);
                sim.run(30);
                Sys.println("ok without " + skip);
            } catch (e:Dynamic) Sys.println("CRASH without '" + skip + "': " + Std.string(e).substr(0, 80));
        }
    }
}
