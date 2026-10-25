package farmer;

import farmer.GameAccess as G;

/**
 * Wears the better gear of the bag: an item of the bag that fits an equipment slot is compared with what the hero wears there and
 * put on (the game's own equip request, Loadout.equipOnSlot, the one a click in the inventory sends) when its stats are higher.
 * The comparison is made between items of the same type only (a bow does not replace a sword), and only for what the hero may
 * wear now (level, class). The worn item goes back into the bag, to be compared again next time.
 */
class Equip {
    static inline var CHECK_GAP = 2.5;
    static inline var RETRY_AFTER = 120.0;
    /** A candidate must beat the worn item by this much (of the score below). */
    static inline var MARGIN = 0.5;

    static var nextCheck = 0.0;
    static var failed:Map<String, Float> = new Map();
    static var slots:Array<String> = null;

    /** What an item is worth: its level (the game's own measure of power), then its rarity, then its affixes. */
    public static function score(item:Dynamic):Float {
        var level = 0.0;
        try level = G.number(G.call("st.Item", "getILevel", item)) catch (_:Dynamic) {}
        var rank = 0.0;
        var rarity = Services.itemRarity(item);
        for (i => r in ["Common", "Uncommon", "Rare", "Epic", "Legendary"]) if (r == rarity) rank = i;
        var sum = 0.0;
        try {
            for (a in G.array(G.call("st.Item", "getAffixes", item))) {
                if (a == null) continue;
                var v = G.number(G.field(a, "val"));
                sum += Math.abs(v) < 1000 ? Math.abs(v) : 0; // a flat bonus or a share: only the order of two items of one type matters
            }
        } catch (_:Dynamic) {}
        return level * 1000 + rank * 100 + Math.min(sum, 99);
    }

    static function slotNames():Array<String> {
        if (slots != null) return slots;
        var out:Array<String> = [];
        try for (s in G.array(G.current("DataCache", "EQUIPMENT_SLOTS"))) out.push(G.s(s)) catch (_:Dynamic) {}
        if (out.length > 0) slots = out;
        return out;
    }

    static function busy(hero:Dynamic):Bool {
        try {
            return G.call("ent.GameObject", "isDead", hero) == true || G.call("ent.GameObject", "isUnderAnyCC", hero) == true
                || G.call("ent.GameObject", "getActiveSkill", hero) != null || G.field(hero, "inCutscene") == true;
        } catch (_:Dynamic) return true;
    }

    /** Called every frame; looks at the bag every few seconds and puts on one better item at a time. */
    public static function update(hero:Dynamic, now:Float):Void {
        if (now < nextCheck) return;
        nextCheck = now + CHECK_GAP;
        try {
            if (busy(hero)) return;
            var loadout = G.field(hero, "loadout");
            var equipment = G.call("ent.Hero", "get_equipment", hero);
            var names = slotNames();
            if (loadout == null || equipment == null || names.length == 0) return;
            var best:Dynamic = null, bestSlot = "", bestGain = MARGIN;
            for (stack in Services.stacks(Services.bag(hero))) {
                var item = G.field(stack, "item");
                if (!Services.isGear(item)) continue;
                var id = Std.string(G.field(item, "__uid"));
                if (failed.exists(id) && now < failed.get(id)) continue;
                var mine = score(item);
                var type = G.s(G.field(G.field(item, "inf"), "type"));
                var openToHero = false;
                try openToHero = Services.isOk(G.call("st.Item", "getNoEquipReason", item, [hero, null])) catch (_:Dynamic) {}
                if (!openToHero) { failed.set(id, now + RETRY_AFTER); continue; }
                for (slot in names) {
                    if (G.staticCall("st.Equipment", "isEquippableOnSlot", [G.field(item, "inf"), slot]) != true) continue;
                    if (G.call("st.Equipment", "canHaveSlot", equipment, [slot]) != true) continue;
                    var worn = G.call("st.Equipment", "getSlot", equipment, [slot]);
                    var gain = mine;
                    if (worn != null) {
                        if (G.s(G.field(G.field(worn, "inf"), "type")) != type) continue; // never swaps a bow for a sword
                        gain = mine - score(worn);
                    }
                    if (gain > bestGain) { bestGain = gain; best = item; bestSlot = slot; }
                }
            }
            if (best == null) return;
            var id = Std.string(G.field(best, "__uid"));
            failed.set(id, now + RETRY_AFTER); // until it is seen worn (then it is no longer in the bag)
            var reason = G.call("st.Loadout", "equipOnSlot", loadout, [best, bestSlot, null, null, null, null]);
            Log.w("equip " + Services.itemId(best) + " -> " + bestSlot + ": " + (reason == null ? "null" : Type.enumConstructor(reason)));
            nextCheck = now + 1.0;
        } catch (e:Dynamic) {
            Log.w("[Farmer] equip: " + Std.string(e));
        }
    }
}
