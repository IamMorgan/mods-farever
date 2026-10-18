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
    /** A fight ends when the hero has dealt or received no result for this long (seconds). */
    static inline var IDLE = 5.0;

    static var hits:Array<Dynamic> = [];
    static var start = 0.0;
    static var last = 0.0;
    static var counter = 0;
    static var nextCheck = 0.0;
    // diagnostics for the test mode
    static var seen = 0;
    static var foreign = 0;
    static var errors = 0;
    static var getSource:hlx.runtime.ResolvedMember = null;
    static var lastSkipped = "";
    /** The hero, looked up twice a second (not for every result of the world). */
    static var heroNow:Dynamic = null;
    static inline var MAX_HITS = 20000;

    /** Hook ent.Unit.rpcReceiveDamage__impl (instance: the target): every damage result in the world. */
    public static function damage(target:Dynamic, result:Dynamic):Void {
        try {
            if (G.num(G.field(result, "effect")) == 1) return; // heals come through rpcDisplayHeal
            record(target, result, false);
        } catch (e:Dynamic) { if (errors++ < 3) DebugLog.error("fight log damage", e); }
    }

    /** Hook ent.Unit.rpcDisplayHeal__impl (instance: the healed unit). */
    public static function heal(target:Dynamic, result:Dynamic):Void {
        try record(target, result, true) catch (e:Dynamic) { if (errors++ < 3) DebugLog.error("fight log heal", e); }
    }

    static function record(target:Dynamic, result:Dynamic, isHeal:Bool):Void {
        seen++;
        var hero = heroNow;
        if (hero == null) return;
        var src = sourceOf(result);
        if (src != hero) { foreign++; return; }
        if (hits.length >= MAX_HITS) return;
        var now = haxe.Timer.stamp();
        // heals (a pet's passive healing) neither start a fight nor keep it going: only damage dealt does
        if (isHeal && (hits.length == 0 || now - last > IDLE)) return;
        if (hits.length > 0 && now - last > IDLE) saveFight(hero);
        if (hits.length == 0) { start = now; DebugLog.line("fight log: fight started"); }
        if (!isHeal) last = now;
        var skill = "";
        try skill = G.str(G.call("st.skill.DamageResult", "get_skillId", [result])) catch (_:Dynamic) {}
        if (skill == "" || skill == "null") skill = G.str(G.field(G.field(G.field(G.field(result, "ctx"), "skill"), "inf"), "id"));
        var rec:Dynamic = {t: Math.round((now - start) * 100) / 100, skill: skill == "" ? "?" : skill, kind: isHeal ? "Heal" : "Damage",
            amount: G.num(G.field(result, "_amount")), crit: G.field(result, "_critical") == true,
            target: G.str(G.field(G.field(target, "inf"), "id")), self: target == hero};
        if (!isHeal) {
            var aff = G.field(result, "affinity");
            if (aff != null) Reflect.setField(rec, "affinity", G.str(aff));
            try {
                if (G.call("st.skill.DamageResult", "get_isPhysical", [result]) == true) Reflect.setField(rec, "damageType", "physical");
                else if (G.call("st.skill.DamageResult", "get_isMagic", [result]) == true) Reflect.setField(rec, "damageType", "magical");
            } catch (_:Dynamic) {}
        }
        hits.push(rec);
    }

    /** Who dealt the result: its source unit, a summon or a pet counted for its owner. */
    static function sourceOf(result:Dynamic):Dynamic {
        var u:Dynamic = null;
        // the getter is looked up once: this runs for every damage result of the world
        try {
            if (getSource == null) getSource = G.member("st.skill.DamageResult", "get_source", false);
            u = HlxRuntime.callResolved(getSource, [result]);
        } catch (_:Dynamic) {}
        if (u == null) u = G.field(G.field(result, "ctx"), "sourceUnit");
        for (_ in 0...5) {
            var owner = G.field(u, "summonOwner");
            if (owner == null || owner == u) break;
            u = owner;
        }
        return u;
    }

    /** Each frame: a fight with no results for IDLE seconds is over. */
    public static function tick():Void {
        var now = haxe.Timer.stamp();
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        heroNow = GameData.hero();
        if (hits.length > 0 && now - last > IDLE) {
            var hero = heroNow;
            DebugLog.guard("fight log", () -> saveFight(hero));
        }
    }

    /** Test mode: what has been seen; with `write` the running fight is saved as it is. */
    public static function probe(write:Bool):Dynamic {
        var out:Dynamic = {hits: hits.length, seen: seen, foreign: foreign, errors: errors, lastSkipped: lastSkipped,
            files: sys.FileSystem.exists(DIR) ? sys.FileSystem.readDirectory(DIR).length : -1};
        if (write) { saveFight(GameData.hero()); out.saved = sys.FileSystem.exists(DIR) ? sys.FileSystem.readDirectory(DIR).length : -1; }
        return out;
    }

    static function saveFight(hero:Dynamic):Void {
        var list = hits;
        hits = [];
        if (list.length == 0) return;
        var duration = Math.max(last - start, 0.1);
        var per = new Map<String, Dynamic>();
        var dmg = 0.0, selfHeal = 0.0, allyHeal = 0.0;
        for (h in list) {
            var r = per.get(h.skill);
            if (r == null) { r = {id: h.skill, damage: 0.0, selfHeal: 0.0, allyHeal: 0.0, hits: 0, crits: 0}; per.set(h.skill, r); }
            r.hits++;
            if (h.crit) r.crits++;
            if (h.kind == "Damage") { r.damage += h.amount; dmg += h.amount; }
            else if (h.self) { r.selfHeal += h.amount; selfHeal += h.amount; }
            else { r.allyHeal += h.amount; allyHeal += h.amount; }
        }
        var out:Dynamic = {written: Date.now().toString(), duration: duration, damage: dmg, dps: dmg / duration, selfHeal: selfHeal, allyHeal: allyHeal,
            hero: describe(hero), skills: [for (r in per) r], hits: list};
        try {
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            prune();
            var name = "fight_" + DateTools.format(Date.now(), "%Y%m%d_%H%M%S") + "_" + (++counter) + ".json";
            sys.io.File.saveContent(DIR + "/" + name, haxe.Json.stringify(out));
            DebugLog.line("fight log: saved " + name + ", " + list.length + " results over " + Math.round(duration * 10) / 10 + " s, dps " + Math.round(dmg / duration));
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
