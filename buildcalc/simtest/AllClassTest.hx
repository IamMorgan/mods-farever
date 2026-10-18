import buildcalc.sim.Sim;
import buildcalc.sim.SimData;
import SimTest;

/**
 * Every class with every weapon of the game (and every infusion): what the simulation cannot do yet (its "missing"
 * list), errors, and the fight's damage, so a class or weapon the model does not handle shows at once.
 */
class AllClassTest {
    static var CLASS_TYPES = ["ClassSkill", "SignatureSkill", "ClassPassive", "PriestPrayer", "RoguePoison", "MageConduit"];

    static function main() {
        TalentTest.prepare();
        var env = TalentTest.env;
        var skills:Array<Dynamic> = [], items:Array<Dynamic> = [];
        for (s in (TalentTest.cdb.sheets : Array<Dynamic>)) {
            if (s.name == "skill") skills = s.lines;
            if (s.name == "item") items = s.lines;
        }
        // weapons: items whose skills include an attack, one per set of skills
        var weapons:Array<{id:String, skills:Array<String>}> = [], seen = new Map<String, Bool>();
        for (it in items) {
            var list:Array<Dynamic> = it.skills;
            if (list == null || list.length == 0) continue;
            var ids = [for (e in list) (e.skill : String)];
            var attack = false;
            for (id in ids) { var i = env.skill(id); if (i != null && Sim.ATTACKS.indexOf(i.type) >= 0) attack = true; }
            if (!attack) continue;
            var key = ids.join(",");
            if (seen.exists(key)) continue;
            seen.set(key, true);
            weapons.push({id: it.id, skills: ids});
        }
        var only = Sys.args().length > 0 ? Sys.args()[0] : "";
        if (only == "diag") {
            // each class with a weapon of its own aptitude (Data.unit of the class: props.aptitudes)
            var apt = ["Priest" => "Cleric", "Mage" => "Wizard", "Rogue" => "Assassin", "Warrior" => "Fighter"];
            for (cls => ap in apt) {
                var base:Array<SkillSpec> = [];
                for (l in skills) {
                    var id:String = l.id;
                    if (!StringTools.startsWith(id, cls + "_")) continue;
                    var info = env.skill(id);
                    if (info == null) continue;
                    if (CLASS_TYPES.indexOf(info.type) >= 0) base.push({id: id, rank: 1, runes: [], kind: info.type == "ClassSkill" ? "class" : "hero", slot: -1, item: null});
                    if (info.type == "Talent") base.push({id: id, rank: Std.int(Math.max(1, info.maxPoints)), runes: [], kind: "talent", slot: -1, item: null});
                }
                var shown = 0;
                for (it in items) {
                    var apts:Array<Dynamic> = it.aptitudes;
                    if (apts == null || !Lambda.exists(apts, x -> x.ref == ap)) continue;
                    var list:Array<Dynamic> = it.skills;
                    if (list == null || list.length < 3) continue;
                    var specs = base.copy();
                    for (e in list) specs.push({id: e.skill, rank: 3, runes: [], kind: "item", slot: 0, item: null});
                    var sim = new Sim(env, 1);
                    sim.setup(specs);
                    var r = sim.run(60);
                    var cs = [for (id => n in r.casts) id + " " + n];
                    cs.sort((x, y) -> x < y ? -1 : 1);
                    Sys.println("== " + cls + " with " + it.id + ": dps " + Math.round(r.dps) + ", resources " + [for (k => v in sim.hero.res) k + "=" + Math.round(v * 10) / 10].join(",")
                        + ", reach " + sim.targetDistance + "
   casts " + cs.join(", ") + "
   missing " + [for (k => n in r.missing) k + " x" + n].join("; "));
                    if (++shown >= 2) break;
                }
            }
            return;
        }
        var allMissing = new Map<String, Map<String, Int>>();
        for (cls in ["Priest", "Mage", "Rogue", "Warrior"]) {
            if (only != "" && only != cls && only != "inf") continue;
            var base:Array<SkillSpec> = [];
            for (l in skills) {
                var id:String = l.id;
                if (!StringTools.startsWith(id, cls + "_")) continue;
                var info = env.skill(id);
                if (info == null) continue;
                if (CLASS_TYPES.indexOf(info.type) >= 0) base.push({id: id, rank: 1, runes: [], kind: info.type == "ClassSkill" ? "class" : "hero", slot: -1, item: null});
                if (info.type == "Talent") base.push({id: id, rank: Std.int(Math.max(1, info.maxPoints)), runes: [], kind: "talent", slot: -1, item: null});
            }
            var missing = new Map<String, Int>();
            allMissing.set(cls, missing);
            var dps = [];
            for (w in weapons) {
                if (only == "inf") break;
                var specs = base.copy();
                for (id in w.skills) specs.push({id: id, rank: 3, runes: [], kind: "item", slot: 0, item: null});
                try {
                    var sim = new Sim(env, 1);
                    sim.setup(specs);
                    var r = sim.run(30);
                    dps.push(w.id + " " + Math.round(r.dps));
                    for (k => n in r.missing) missing.set(k + "  [" + w.id + "]", n);
                } catch (e:Dynamic) missing.set("CRASH " + w.id + ": " + Std.string(e).substr(0, 120), 1);
            }
            if (only != "inf") Sys.println("== " + cls + " (" + base.length + " class skills/talents): " + dps.join(", "));
        }
        // infusions, each at rank 3, with the priest and the first weapon
        if (only == "" || only == "inf") {
            var missing = new Map<String, Int>();
            allMissing.set("infusions", missing);
            for (l in skills) {
                var info = env.skill(l.id);
                if (info == null || info.type != "InfusionPassive") continue;
                var specs:Array<SkillSpec> = [for (id in weapons[0].skills) {id: id, rank: 3, runes: [], kind: "item", slot: 0, item: null}];
                specs.push({id: l.id, rank: 3, runes: [], kind: "infusion", slot: -1, item: null});
                for (sub in info.subskills) specs.push({id: sub, rank: 3, runes: [], kind: "infusion", slot: -1, item: null});
                try {
                    var sim = new Sim(env, 1);
                    sim.setup(specs);
                    var r = sim.run(30);
                    for (k => n in r.missing) missing.set(k + "  [" + l.id + "]", n);
                } catch (e:Dynamic) missing.set("CRASH " + l.id + ": " + Std.string(e).substr(0, 120), 1);
            }
        }
        for (cls => m in allMissing) {
            // the same gap for many weapons: shown once, with how many weapons have it
            var byKey = new Map<String, Int>();
            for (k => n in m) {
                var key = k.indexOf("  [") >= 0 ? k.substr(0, k.indexOf("  [")) : k;
                byKey.set(key, (byKey.exists(key) ? byKey.get(key) : 0) + 1);
            }
            var keys = [for (k in byKey.keys()) k];
            keys.sort((a, b) -> byKey.get(b) - byKey.get(a));
            Sys.println("-- " + cls + " missing (" + keys.length + "):");
            for (k in keys) Sys.println("   " + k + "  x" + byKey.get(k));
        }
    }
}
