package buildcalc;

/** What the hero did in a fight, by skill: damage, heals on the hero, heals on others. */
typedef SkillRecord = {dmg:Float, selfHeal:Float, allyHeal:Float, hits:Int, crits:Int};

/**
 * The hero's last fight as the game's own combat meter keeps it (ent.Unit.combatStats.damages and
 * combatDamageHistory: every st.skill.DamageResult the hero dealt — damage, heals, shields — with its skill,
 * amount, target and critical flag). The calculator uses it to value builds the way the player really
 * fights (e.g. against a training dummy): the per-second totals of each skill are scaled by how much the
 * model says that skill changes in a new build.
 */
class Combat {
    public var duration = 0.0;
    public var bySkill = new Map<String, SkillRecord>();
    public var dmg = 0.0;
    public var selfHeal = 0.0;
    public var allyHeal = 0.0;
    public var ok = false;
    var fallback = 0.0;
    /** Every damage/heal/shield result in the order of the fight (FightLog writes it). */
    public var hits:Array<Dynamic> = [];
    public var startTime = 0.0;

    public function new(hero:Dynamic, fallbackDuration:Float = 0) {
        this.fallback = fallbackDuration;
        try read(hero) catch (e:Dynamic) DebugLog.error("combat record", e);
    }

    function read(hero:Dynamic):Void {
        var stats = G.field(hero, "combatStats");
        var list = G.field(stats, "damages");
        var inCombat = G.field(hero, "isInCombat") == true;
        var start = G.num(G.field(hero, "combatStartTime"));
        var end = G.num(G.field(hero, "combatEndTime"));
        var now = start;
        try now = G.num(G.field(G.call("st.State", "get_time", [hero]), "serverNow")) catch (_:Dynamic) {}
        duration = (inCombat ? now : end) - start;
        if (duration < 3 && G.len(list) > 0) duration = fallback;
        startTime = start;
        var from = "current fight";
        if (G.len(list) == 0 || duration < 3) {
            // the last finished fight of the history
            var hist = G.field(hero, "combatDamageHistory");
            var n = G.len(hist);
            if (n > 0) {
                var last = G.at(hist, n - 1);
                list = G.field(last, "damages");
                duration = G.num(G.field(last, "duration"));
                startTime = G.num(G.field(last, "startTime"));
                from = "history #" + (n - 1);
            }
        }
        var count = G.len(list);
        DebugLog.line("combat: " + from + ", " + count + " records over " + r1(duration) + " s (in combat " + inCombat + ")");
        if (count == 0 || duration < 3) return;
        for (i in 0...count) {
            var d = G.at(list, i);
            var amount = 0.0;
            try amount = G.num(G.call("st.skill.DamageResult", "get_amount", [d])) catch (_:Dynamic) amount = G.num(G.field(d, "_amount"));
            var effect = Std.int(G.num(G.field(d, "effect")));
            var kind = SkillData.effectName(effect);
            var skill = G.field(G.field(d, "ctx"), "skill");
            var id = G.str(G.field(G.field(skill, "inf"), "id"));
            if (id == "") id = "?";
            var target = G.field(d, "target");
            var critical = G.field(d, "_critical") == true;
            var r = bySkill.get(id);
            if (r == null) { r = {dmg: 0, selfHeal: 0, allyHeal: 0, hits: 0, crits: 0}; bySkill.set(id, r); }
            r.hits++;
            var rec:Dynamic = {i: i, skill: id, kind: kind, amount: amount, crit: critical, target: G.str(G.field(G.field(target, "inf"), "id"))};
                        // st.skill.DamageResult.get_isPhysical / get_isMagic
            try {
                if (G.call("st.skill.DamageResult", "get_isPhysical", [d]) == true) Reflect.setField(rec, "damageType", "physical");
                else if (G.call("st.skill.DamageResult", "get_isMagic", [d]) == true) Reflect.setField(rec, "damageType", "magical");
            } catch (_:Dynamic) {}
            hits.push(rec);
            if (critical) r.crits++;
            if (kind == "Damage") { r.dmg += amount; dmg += amount; }
            else if (kind == "Heal" || kind == "Shield") {
                if (target == hero) { r.selfHeal += amount; selfHeal += amount; } else { r.allyHeal += amount; allyHeal += amount; }
            }
        }
        ok = dmg > 0 || selfHeal + allyHeal > 0;
        var lines = [for (id => r in bySkill) id + ": dmg " + r1(r.dmg / duration) + "/s, self heal " + r1(r.selfHeal / duration) + "/s, ally heal "
            + r1(r.allyHeal / duration) + "/s, hits " + r.hits + ", crits " + r.crits];
        DebugLog.line("combat: per second dmg " + r1(dmg / duration) + ", self heal " + r1(selfHeal / duration) + ", ally heal " + r1(allyHeal / duration)
            + "\n    " + lines.join("\n    "));
    }

    static function r1(v:Float):String return Std.string(Math.round(v * 10) / 10);
}
