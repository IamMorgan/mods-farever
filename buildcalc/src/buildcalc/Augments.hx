package buildcalc;

import buildcalc.Items.Affix;

typedef Augment = {
    var inf:Dynamic;
    var id:String;
    var type:String;          // augment type: one of each type per item (st.item.Gear.isConflictingAugmentType)
    var affixes:Array<Affix>; // flat attributes it adds
    var skills:Array<String>; // skills it gives (sigils: a talent; weapon enchants)
    var available:Bool;       // can be obtained now (Sources) or the hero has it
    var raw:Dynamic;          // the id as the game's string (what the game's maps compare)
}

/**
 * Slot augments (enchantments, gems, sigils) of the game: every item whose type has augmentTargets.
 * An augment fits an item when HItem.canAugment says so, the hero's class may use it (aptitudes) and it
 * can be obtained now (Sources); an item holds one augment of each augment type.
 */
class Augments {
    static var all:Array<Augment> = null;
    static var targetRe = ~/attribute\s*:\s*([A-Za-z0-9_]+)/;

    static function load(hero:Dynamic):Void {
        if (all != null) return;
        all = [];
        var types = G.field(GameData.data("itemType"), "all");
        var augTypes = new Map<String, Bool>();
        for (i in 0...G.len(types)) {
            var t = G.at(types, i);
            if (G.len(G.field(G.field(t, "props"), "augmentTargets")) > 0) augTypes.set(G.str(G.field(t, "id")), true);
        }
        var items = G.field(GameData.data("item"), "all");
        var skippedClass = 0, skippedSource = 0;
        for (i in 0...G.len(items)) {
            var inf = G.at(items, i);
            var type = G.str(G.field(inf, "type"));
            if (!augTypes.exists(type)) continue;
            var id = G.str(G.field(inf, "id"));
            var ok = true;
            try ok = G.callStatic("HItem", "hasUnitAptitude", [inf, hero]) == true catch (_:Dynamic) {}
            if (!ok) { skippedClass++; continue; }
            var available = Sources.available(id);
            if (!available) skippedSource++;
            var affixes:Array<Affix> = [];
            var afx = G.field(inf, "affixes");
            for (k in 0...G.len(afx)) {
                var a = G.at(afx, k);
                var target = Std.string(G.field(a, "target"));
                if (!targetRe.match(target)) continue;
                affixes.push({attr: targetRe.matched(1), kind: G.str(G.field(a, "ref")), val: G.num(G.field(a, "val"))});
            }
            var skills = [];
            var sk = G.field(inf, "skills");
            for (k in 0...G.len(sk)) skills.push(GameData.idOf(G.field(G.at(sk, k), "skill")));
            all.push({inf: inf, id: id, type: type, affixes: affixes, skills: skills, available: available, raw: G.field(inf, "id")});
        }
        DebugLog.line("augments: " + all.length + " of the class (" + skippedClass + " for other classes; " + skippedSource + " of them not obtainable now): "
            + [for (a in all) a.id + "[" + [for (x in a.affixes) x.attr + (x.val >= 0 ? "+" : "") + x.val].join(" ") + (a.skills.length > 0 ? " skill " + a.skills.join(",") : "") + "]"].join(" "));
    }

    /** The augments that fit this item, grouped by augment type. */
    public static function forItem(hero:Dynamic, itemInf:Dynamic):Map<String, Array<Augment>> {
        load(hero);
        var out = new Map<String, Array<Augment>>();
        for (a in all) {
            if (!a.available) continue;
            var fits = false;
            try fits = G.callStatic("HItem", "canAugment", [a.inf, itemInf]) == true catch (_:Dynamic) {}
            if (!fits) continue;
            if (!out.exists(a.type)) out.set(a.type, []);
            out.get(a.type).push(a);
        }
        return out;
    }

    /** The augments set in a real item (st.item.Gear.slots: item ids). */
    public static function inItem(hero:Dynamic, item:Dynamic):Array<Augment> {
        load(hero);
        var out = [];
        var slots = G.field(item, "slots");
        var list = G.field(slots, "array");
        if (list == null) list = slots;
        for (i in 0...G.len(list)) {
            var v = G.at(list, i);
            var id = Std.isOfType(v, String) ? v : G.str(G.field(v, "id"));
            if (id == "") id = Std.string(v);
            var found = false;
            for (a in all) if (a.id == id) { out.push(a); found = true; }
            if (!found) for (a in all) if (id.indexOf(a.id) >= 0) { out.push(a); break; }
        }
        return out;
    }
}
