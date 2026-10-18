package buildcalc;

/**
 * Fight log: when the hero's fight ends, the game's own combat meter (Combat) is written to
 * hlx/config/buildcalc/fights/fight_<date>_<n>.json — per-skill totals, every hit in order, and the hero's
 * build (class, level, skills, worn items). It works for every character with this mod alone (no other
 * mod needed) and is what a build can be checked against. Independent of the debug log.
 */
class FightLog {
    public static inline var DIR = "hlx/config/buildcalc/fights";
    static inline var MAX_FILES = 200;
    static var wasInCombat = false;
    static var nextCheck = 0.0;
    static var lastKey = "";
    static var counter = 0;
    /** When each result of the running fight was first seen (seconds from the fight's start, half a second apart). */
    static var seenAt:Array<Float> = [];
    static var fightStart = 0.0;

    /** Each frame (GameApp.update): twice a second looks whether the hero's fight has just ended. */
    public static function tick():Void {
        var now = haxe.Timer.stamp();
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        var hero = GameData.hero();
        if (hero == null) { wasInCombat = false; return; }
        var inCombat = G.field(hero, "isInCombat") == true;
        if (wasInCombat && !inCombat) DebugLog.guard("fight log", () -> save(hero));
        if (inCombat) {
            if (!wasInCombat) { seenAt = []; fightStart = now; }
            var n = G.len(G.field(G.field(hero, "combatStats"), "damages"));
            while (seenAt.length < n) seenAt.push(now - fightStart);
        }
        wasInCombat = inCombat;
    }

    static function save(hero:Dynamic):Void {
        var c = new Combat(hero);
        if (!c.ok) { DebugLog.line("fight log: no fight to save (too short or empty)"); return; }
        if (seenAt.length == c.hits.length) for (h in c.hits) h.seen = Math.round(seenAt[h.i] * 10) / 10;
        var key = Std.string(c.startTime) + "/" + c.hits.length;
        if (key == lastKey) return;
        lastKey = key;
        var skills = [for (id => r in c.bySkill) {id: id, damage: r.dmg, selfHeal: r.selfHeal, allyHeal: r.allyHeal, hits: r.hits, crits: r.crits,
            dps: r.dmg / c.duration}];
        var out:Dynamic = {
            written: Date.now().toString(),
            duration: c.duration, damage: c.dmg, dps: c.dmg / c.duration, selfHeal: c.selfHeal, allyHeal: c.allyHeal,
            hero: describe(hero), skills: skills, hits: c.hits
        };
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            prune();
            var d = Date.now();
            var name = "fight_" + DateTools.format(d, "%Y%m%d_%H%M%S") + "_" + (++counter) + ".json";
            sys.io.File.saveContent(DIR + "/" + name, haxe.Json.stringify(out));
            DebugLog.line("fight log: saved " + name + ", " + c.hits.length + " hits over " + Math.round(c.duration * 10) / 10 + " s");
        } catch (e:Dynamic) DebugLog.error("fight log write", e);
    }

    /** The hero's build at the end of the fight, as far as the game lets it be read. */
    static function describe(hero:Dynamic):Dynamic {
        var info:Dynamic = {};
        for (n in ["name", "_level", "classId", "className", "heroClass", "class"]) {
            var v = G.field(hero, n);
            if (v != null) Reflect.setField(info, n, Std.isOfType(v, Float) || Std.isOfType(v, Int) ? v : G.str(G.field(v, "id") != null ? G.field(v, "id") : v));
        }
        var skills = [];
        var list = G.field(hero, "skills");
        for (i in 0...G.len(list)) {
            var s = G.at(list, i);
            skills.push({id: G.str(G.field(G.field(s, "inf"), "id")), rank: G.num(G.field(s, "rank"))});
        }
        Reflect.setField(info, "skills", skills);
        var items = [];
        for (slot in 0...12) {
            var it = GameData.equipped(hero, slot);
            if (it == null) continue;
            items.push({slot: slot, id: G.str(G.field(G.field(it, "inf"), "id")), upgrade: G.num(G.field(it, "upgradeLevel")),
                infusion: G.str(G.field(it, "infusion")), rarity: G.str(G.field(it, "rarity")), level: G.num(G.field(it, "level"))});
        }
        Reflect.setField(info, "items", items);
        return info;
    }

    /** Keeps the folder from growing without end: the oldest files go. */
    static function prune():Void {
        var files = [for (f in sys.FileSystem.readDirectory(DIR)) if (StringTools.startsWith(f, "fight_")) f];
        if (files.length < MAX_FILES) return;
        files.sort((a, b) -> a < b ? -1 : 1);
        for (i in 0...files.length - MAX_FILES + 1) try sys.FileSystem.deleteFile(DIR + "/" + files[i]) catch (_:Dynamic) {}
    }
}
