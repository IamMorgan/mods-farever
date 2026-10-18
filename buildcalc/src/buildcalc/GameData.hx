package buildcalc;

/** Reads the game's data sheets and the hero's current choices. */
class GameData {
    public static function data(sheet:String):Dynamic return HlxRuntime.resolveStaticField(G.type("Data"), sheet);

    public static function skill(id:String):Dynamic {
        if (id == null || id == "") return null;
        try return G.call("haxe.ds.StringMap", "get", [G.field(data("skill"), "byId"), id]) catch (_:Dynamic) return null;
    }

    public static function hero():Dynamic {
        try return G.callStatic("GameApp", "getMyHero", []) catch (_:Dynamic) return null;
    }

    /** Skill id from a reference that may be a plain id or a record. */
    public static function idOf(ref:Dynamic):String {
        if (ref == null) return "";
        // a string of the game is copied into one of the mod (G.str): kept as it is, haxe.Json wrote it as {bytes, length}
        if (Std.isOfType(ref, String)) return G.str(ref);
        var id = G.str(G.field(ref, "id"));
        return id;
    }

    /** Current rank of a talent on the hero (0 when not taken). */
    public static function talentRank(hero:Dynamic, id:String):Int {
        try return Std.int(G.num(G.call("st.player.HeroSpecialization", "getTalent", [G.field(hero, "specialization"), id]))) catch (_:Dynamic) return 0;
    }

    /** Ids of the skill masteries (runes) the hero has switched on. */
    public static function activeMasteries(hero:Dynamic):Array<String> {
        var out = [];
        try {
            var proxy = G.field(G.field(hero, "specialization"), "skillMasteries");
            // hxbit.ArrayProxyData keeps the list in its field "array"
            var list = G.field(proxy, "array");
            if (list == null) list = proxy;
            for (i in 0...G.len(list)) out.push(G.str(G.at(list, i)));
        } catch (e:Dynamic) DebugLog.error("activeMasteries", e);
        return out;
    }

    /**
     * The skills the hero chose for an arsenal weapon, read from HeroSpecialization.arsenals (its `map`)
     * without calling getArsenalSkills, which creates an entry when there is none.
     */
    public static function arsenalSkills(hero:Dynamic, itemId:Dynamic):Array<String> {
        var out = [];
        try {
            var map = G.field(G.field(G.field(hero, "specialization"), "arsenals"), "map");
            var info = map == null ? null : G.call("haxe.ds.StringMap", "get", [map, itemId]);
            var skills = G.field(info, "skills");
            var list = G.field(skills, "array");
            if (list == null) list = skills;
            for (i in 0...G.len(list)) out.push(idOf(G.at(list, i)));
        } catch (e:Dynamic) DebugLog.error("arsenalSkills", e);
        return out;
    }

    /** The equipment item in a slot of the hero's equipment (st.Item), or null. */
    public static function equipped(hero:Dynamic, slot:Int):Dynamic {
        try {
            var content = G.field(G.call("ent.Hero", "get_equipment", [hero]), "content");
            var entry = G.at(content, slot);
            return entry == null ? null : G.field(entry, "item");
        } catch (_:Dynamic) return null;
    }

    /** The hero's instance of a skill (st.skill.BaseSkill), or null when the hero does not have it. */
    public static function skillInstance(hero:Dynamic, id:String):Dynamic {
        try {
            var list = G.field(hero, "skills");
            for (i in 0...G.len(list)) {
                var s = G.at(list, i);
                if (G.str(G.field(G.field(s, "inf"), "id")) == id) return s;
            }
        } catch (e:Dynamic) DebugLog.error("skillInstance " + id, e);
        return null;
    }

    /** The active runes (mastery ids) of one skill. */
    public static function skillMasteries(sk:Dynamic, active:Array<String>):Array<String> {
        var out = [];
        var list = G.field(sk, "mastery");
        for (i in 0...G.len(list)) {
            var id = G.str(G.field(G.at(list, i), "id"));
            if (active.indexOf(id) >= 0) out.push(id);
        }
        return out;
    }

    /**
     * The "skill of a hero" record the game's texts and tooltips take
     * ({inf, rank, maxRank, masteries, heroic}: HText.skillMastery, ui.Tooltip.fromSkill).
     */
    public static function skillInfo(sk:Dynamic, rank:Int, maxRank:Null<Int>, masteries:Array<String>):Dynamic {
        // masteries must be a list of strings (HText.makeSkillText); null when the game adds the rune itself
        return {inf: sk, rank: rank < 1 ? 1 : rank, maxRank: maxRank, masteries: masteries, heroic: false};
    }
}
