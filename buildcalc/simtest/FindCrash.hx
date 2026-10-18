import buildcalc.sim.Sim;
import SimTest;
class FindCrash {
    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var cls = Sys.args()[0];
        var skills:Array<Dynamic> = [];
        for (s in (TalentTest.cdb.sheets : Array<Dynamic>)) if (s.name == "skill") skills = s.lines;
        var weapon = ["Scepter_Base_Attack", "Scepter_Flamie_Combo", "Scepter_Flamie_Skill1", "Scepter_Flamie_S2", "Scepter_Flamie_P"];
        for (l in skills) {
            var id:String = l.id;
            if (!StringTools.startsWith(id, cls + "_")) continue;
            var info = env.skill(id);
            if (info == null || info.type == null || info.type == "") continue;
            var specs:Array<SkillSpec> = [for (w in weapon) {id: w, rank: 3, runes: [], kind: "item", slot: 0, item: null}];
            specs.push({id: id, rank: Std.int(Math.max(1, info.maxPoints)), runes: [], kind: info.type == "Talent" ? "talent" : "class", slot: -1, item: null});
            try {
                var sim = new Sim(env, 1);
                sim.setup(specs);
                sim.run(30);
            } catch (e:Dynamic) Sys.println("CRASH with " + id + " (" + info.type + "): " + Std.string(e).substr(0, 100));
        }
        Sys.println("done");
    }
}
