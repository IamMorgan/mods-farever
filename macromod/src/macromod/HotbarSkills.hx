package macromod;

import macromod.GameAccess as G;
import macromod.SkillMatch.SkillRef;

typedef HotbarSkill = {
    > SkillRef,
    var input:String;   // the game input of the slot, e.g. "Skill2" or "WeaponSkill1"
    var weapon:Bool;
    var skill:Dynamic;  // st.skill.Skill
};

/**
 * The skills on the character's action bars, read from the game's own HUD slot buttons
 * (ui.hud.SkillSlotButton and ui.hud.WeaponSkillSlotButton). Each button already holds the
 * skill it shows, including weapon swaps and overrides, so this is exactly what the player sees.
 */
class HotbarSkills {
    static inline var SLOT = "ui.hud.SkillSlotButton";
    static inline var WEAPON_SLOT = "ui.hud.WeaponSkillSlotButton";
    static inline var MAX_NODES = 200000;
    static inline var NATURE_PASSIVE = 5; // skipped by the game's own slot input as well

    var buttons:Array<{node:Dynamic, weapon:Bool}> = [];
    var tree = new GameScene();

    public function new() {}

    function stillOnScreen():Bool {
        if (buttons.length == 0) return false;
        for (b in buttons) if (G.field(b.node, "allocated") != true) return false;
        return true;
    }

    function scan(root:Dynamic):Void {
        buttons = [];
        var stack:Array<Dynamic> = [root];
        var visited = 0;
        while (stack.length > 0 && visited++ < MAX_NODES) {
            var node = stack.pop();
            var weapon = G.isA(node, WEAPON_SLOT);
            if (weapon || G.isA(node, SLOT)) {
                buttons.push({node: node, weapon: weapon});
                continue; // nothing of interest inside a slot button
            }
            var kids = tree.children(node);
            var i = kids.length;
            while (i-- > 0) stack.push(kids[i]);
        }
    }

    /** Display name in the client's language, the way the game's own tooltip finds it. */
    public static function displayName(skill:Dynamic):String {
        var inf = G.field(skill, "inf");
        var name = SkillMatch.cleanName(G.str(G.field(G.field(inf, "texts"), "name")));
        if (name == "") {
            try {
                var ref = G.staticCall("HSkill", "getSkillRef", [G.field(inf, "id")]);
                name = SkillMatch.cleanName(G.str(G.field(G.field(ref, "texts"), "name")));
            } catch (_:Dynamic) {}
        }
        if (name == "") name = G.text(G.str(G.field(inf, "id")));
        return name;
    }

    public static function describe(skill:Dynamic):SkillRef {
        var inf = G.field(skill, "inf");
        var kind = G.text(G.str(G.field(skill, "kind")));
        var id = G.text(G.str(G.field(inf, "id")));
        return {kind: kind != "" ? kind : id, id: id, name: displayName(skill)};
    }

    /** Mount, the dash key and block are not rotation skills: never offered (class skills that move the hero, like a rogue's shadow step, are). */
    static function isExcluded(skill:Dynamic, input:String):Bool {
        if (input == "Mount" || input == "Dash") return true;
        if (G.isA(skill, "st.skill.Mount") || G.isA(skill, "st.skill.Block")) return true;
        try {
            if (G.call("st.skill.BaseSkill", "isBlock", skill) == true) return true;
        } catch (_:Dynamic) {}
        return false;
    }

    /** Weapon skills first, then the class skills, each skill once. Empty if no HUD is found. */
    public function read(root:Dynamic):Array<HotbarSkill> {
        if (root != null && !stillOnScreen()) scan(root);
        var weapon:Array<HotbarSkill> = [], other:Array<HotbarSkill> = [];
        var seen = new Map<String, Bool>();
        for (b in buttons) {
            try {
                var skill = G.field(G.field(b.node, "button"), "skill");
                if (skill == null && !b.weapon) skill = G.field(b.node, "skill");
                if (skill == null || G.field(skill, "removed") == true) continue;
                if (G.integer(G.field(G.field(skill, "inf"), "nature"), -1) == NATURE_PASSIVE) continue;
                if (isExcluded(skill, G.text(G.str(G.field(b.node, "input"))))) continue;
                var ref = describe(skill);
                if (ref.kind == "" || seen.exists(ref.kind)) continue;
                seen.set(ref.kind, true);
                var input = G.text(G.str(G.field(b.node, "input")));
                var entry:HotbarSkill = {kind: ref.kind, id: ref.id, name: ref.name, input: input, weapon: b.weapon, skill: skill};
                (b.weapon ? weapon : other).push(entry);
            } catch (_:Dynamic) {}
        }
        return weapon.concat(other);
    }

    /** Every skill the hero has (not only the bars): lets a step still find a skill by name
        after it was taken off the bar. */
    public static function heroSkills(hero:Dynamic):Array<SkillRef> {
        var out:Array<SkillRef> = [];
        if (hero == null) return out;
        try {
            for (skill in G.array(G.field(hero, "skills"))) {
                if (skill == null) continue;
                var ref = describe(skill);
                if (ref.kind != "") out.push(ref);
            }
        } catch (_:Dynamic) {}
        return out;
    }
}
