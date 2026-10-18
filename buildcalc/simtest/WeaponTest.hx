import buildcalc.sim.Sim;
import SimTest;
/** The priest's worn talents and skills with each weapon of the cleric at rank 3 (skills only, no item attributes). */
class WeaponTest {
    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var items:Array<Dynamic> = [];
        for (s in (TalentTest.cdb.sheets : Array<Dynamic>)) if (s.name == "item") items = s.lines;
        var worn = "Priest_Talent_PurgingStrikes:1,Priest_Talent_Sunlight:1,Priest_Talent_PiercingLight:2,Priest_Talent_MightyExecutioner:2,Priest_Talent_FerventDefender:2,Priest_Talent_SolarDevotion:1,Priest_Talent_ZealousFighter:2,Priest_Talent_SwiftJustice:1,Priest_Talent_SoothingRays:1,Priest_Talent_PiousAdept:2,Priest_Talent_Radiance:1";
        for (id in ["Scepter_Flamie", "Mace_Benediction", "Sword_Craft", "Sword_Swarm", "Fists_LightMonk", "GA_Demon", "GM_MassGrab", "Spear_Eruption"]) {
            var it:Dynamic = Lambda.find(items, x -> x.id == id);
            var specs = [for (s in TalentTest.specs(worn)) if (s.slot != 0) s];
            for (e in (it.skills : Array<Dynamic>)) specs.push({id: e.skill, rank: 3, runes: [], kind: "item", slot: 0, item: null});
            function fight():Array<Float> {
                var dps = 0.0, heal = 0.0;
                for (seed in 1...5) { var sim = new Sim(env, seed); sim.setup(specs); var r = sim.run(60); dps += r.dps / 4; heal += r.selfHeal / 4; }
                return [dps, heal];
            }
            var asap = fight();
            // the model's weaving: each weapon skill (cooldown <= 20 s) before attack i of the chain, greedy
            var chain = 0;
            for (sp in specs) if (sp.slot == 0) { var i = env.skill(sp.id); if (i != null && Sim.ATTACKS.indexOf(i.type) >= 0) chain++; }
            var best = asap, shown = [];
            for (sp in specs) {
                var i = env.skill(sp.id);
                if ((sp.slot != 0 && sp.slot != 1) || i == null || i.type != "WeaponSkill" || i.cooldown <= 0 || i.cooldown > 20) continue;
                var keep = -1;
                for (pos in 0...chain) { sp.weave = pos; var v = fight(); if (v[0] + v[1] > best[0] + best[1]) { best = v; keep = pos; } }
                sp.weave = keep;
                if (keep >= 0) shown.push(sp.id + "@" + (keep + 1));
            }
            Sys.println(id + ": as soon as ready dps " + Math.round(asap[0]) + " | woven dps " + Math.round(best[0]) + ", heal " + Math.round(best[1]) + " " + shown.join(" "));
        }
    }
}
