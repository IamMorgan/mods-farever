package buildcalc;

typedef Affix = {attr:String, kind:String, val:Float};

/** A piece of equipment the calculator can put in a slot. */
typedef Candidate = {
    var item:Dynamic;            // st.Item (the real item, or one created by the game for the calculation)
    var inf:Dynamic;             // its data record
    var id:String;
    var type:String;
    var weapon:Bool;
    var ranged:Bool;
    var affixes:Array<Affix>;    // as the game counts them (base, upgrade, slots; worn items: also the active infusion bonus)
    var source:String;           // "equipped" (worn), "owned" (in the bag, the mail or the bank, as it is) or "game"
    var skills:Array<String>;    // the item's own skills (weapon attacks and skills, trinket skills)
    var aptAtbs:Array<String>;   // attributes its "WeaponPower" stands for (statGroup 0 of its aptitudes)
    var powerRatio:Float;        // share of its skills' attribute scaling replaced by the item's own power
    var infusable:Bool;
    var faction:String;          // faction origin (infusion bonus is active when the infusion's faction matches)
    var infusion:String;         // worn items: the infusion they have
    var upgrade:Int;
    var real:Bool;               // a real item of the hero (worn or owned): its affixes already hold its augments and infusion bonus
    var realAugs:Array<Dynamic>; // real items: the augments in its slots (Augments.inItem)
    var key:String;              // unique among candidates: the id (created items), id@n (real items, there may be several)
    var bonusStat:String;        // real items: the infusion bonus attribute they have ("" none)
    var ownBonus:Affix;          // real items: their active infusion bonus, the last of `affixes` (null: none)
    @:optional var probe:Dynamic; // real items: a copy (st.Item.clone) to try other infusions on, the real item is never changed
}

/** Reads equipment: affixes (with slots, upgrade and infusion bonus, as the game counts them), slots, weapon type. */
class Items {
    public static var SLOTS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];
    /** Slot_OffhandWeapon (a shield): it works only with a one-handed main weapon (offhandWorks). */
    public static inline var OFFHAND = 2;

    static var targetRe = ~/ETAttribute\(([A-Za-z0-9_]+)\)/;

    public static function isGear(item:Dynamic):Bool {
        var cls = G.typeName(item);
        return cls == "st.item.Gear" || cls == "st.item.Armor" || cls == "st.item.Weapon";
    }

    /** The item's affixes as the game applies them (st.item.Gear.getAffixes: base + slot augments + active infusion bonus). */
    public static function affixes(item:Dynamic):Array<Affix> {
        var out:Array<Affix> = [];
        try {
            var list = G.call("st.item.Gear", "getAffixes", [item]);
            for (i in 0...G.len(list)) {
                var a = affixOf(G.at(list, i));
                if (a != null) out.push(a);
            }
        } catch (e:Dynamic) DebugLog.error("affixes " + G.str(G.field(G.field(item, "inf"), "id")), e);
        return out;
    }

    /** An affix description of the game ({ref, target: ETargetKind, val}) as attribute, kind, value. */
    public static function affixOf(a:Dynamic):Affix {
        if (a == null) return null;
        var target = Std.string(G.field(a, "target"));
        if (!targetRe.match(target)) return null;
        return {attr: targetRe.matched(1), kind: G.str(G.field(G.field(a, "ref"), "id")), val: G.num(G.field(a, "val"))};
    }

    static var rangedTypes = new Map<String, Bool>();

    /** A weapon is ranged when the move set of its item type is (Data.moveSet props.range, as ent.Unit.isRanged reads it). */
    public static function isRanged(type:String):Bool {
        if (rangedTypes.exists(type)) return rangedTypes.get(type);
        var ranged = false;
        try {
            var ms = G.str(G.field(typeRecord(type), "moveSet"));
            var rec = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("moveSet"), "byId"), ms]);
            ranged = G.field(G.field(rec, "props"), "range") == true;
        } catch (e:Dynamic) DebugLog.error("isRanged " + type, e);
        rangedTypes.set(type, ranged);
        return ranged;
    }

    public static function typeRecord(type:String):Dynamic
        return G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("itemType"), "byId"), type]);

    static var powerRatios = new Map<String, Float>();

    /**
     * Share of the attribute scaling of an item's skills that the item's own power replaces
     * (HSkill.getStepEffectScaling: Const.Skills.WeaponPowerRatio.MainhandWeaponSkill for main-hand weapons,
     * 1 for trinkets, none otherwise).
     */
    public static function powerRatio(type:String):Float {
        if (powerRatios.exists(type)) return powerRatios.get(type);
        var r = 0.0;
        try {
            var rec = typeRecord(type);
            if (G.callStatic("HItem", "isSameType", [rec, "MainhandWeapon"]) == true) {
                var c = G.field(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Skills"), "WeaponPowerRatio"), "MainhandWeaponSkill");
                r = Math.max(0, Math.min(1, G.num(c)));
            } else if (G.callStatic("HItem", "isSameType", [rec, "GearTrinket"]) == true) r = 1.0;
        } catch (e:Dynamic) DebugLog.error("powerRatio " + type, e);
        powerRatios.set(type, r);
        return r;
    }

    /** Attributes the "WeaponPower" scaling of the item's skills stands for (HSkill.convertWeaponPowerScaling). */
    static function aptitudeAtbs(inf:Dynamic):Array<String> {
        var out = [];
        var apts = G.field(inf, "aptitudes");
        var byId = G.field(GameData.data("aptitude"), "byId");
        for (i in 0...G.len(apts)) {
            var ref = G.field(G.at(apts, i), "ref");
            var apt = Std.isOfType(ref, String) ? G.call("haxe.ds.StringMap", "get", [byId, ref]) : ref;
            var sc = G.field(apt, "atbScaling");
            for (j in 0...G.len(sc)) {
                var s = G.at(sc, j);
                if (Std.int(G.num(G.field(s, "statGroup"))) == 0) { out.push(G.str(G.field(s, "endAtb"))); break; }
            }
        }
        return out;
    }

    public static function candidate(item:Dynamic, source:String):Candidate {
        var inf = G.field(item, "inf");
        var weapon = G.typeName(item) == "st.item.Weapon";
        var type = G.str(G.field(inf, "type"));
        var skills = [];
        var sk = G.field(inf, "skills");
        for (i in 0...G.len(sk)) {
            var id = GameData.idOf(G.field(G.at(sk, i), "skill"));
            if (id != "") skills.push(id);
        }
        var infusable = false;
        try infusable = G.callStatic("HInfusion", "canBeInfused", [inf]) == true catch (_:Dynamic) {}
        var faction = "";
        try faction = G.str(G.callStatic("HItem", "getFactionOrigin", [inf])) catch (_:Dynamic) {}
        var id = G.str(G.field(inf, "id"));
        var real = source != "game";
        var list = affixes(item);
        // st.item.Gear.getAffixes: the active infusion bonus comes last
        var ownBonus:Affix = null;
        if (real) try {
            if (G.call("st.item.Gear", "isInfusionBonusActive", [item]) == true && list.length > 0) {
                var b = affixOf(G.call("st.item.Gear", "getInfusionBonusAffix", [item]));
                var last = list[list.length - 1];
                if (b != null && last.attr == b.attr && last.kind == b.kind && last.val == b.val) ownBonus = last;
            }
        } catch (e:Dynamic) DebugLog.error("infusion bonus " + id, e);
        return {item: item, inf: inf, id: id, type: type, weapon: weapon, ranged: weapon && isRanged(type),
            affixes: list, source: source, skills: skills, aptAtbs: aptitudeAtbs(inf), powerRatio: powerRatio(type),
            infusable: infusable, faction: faction, infusion: G.str(G.field(item, "infusion")), upgrade: Std.int(G.num(G.field(item, "upgradeLevel"))),
            real: real, realAugs: [], key: real ? id + "@" + (realCount++) : id,
            bonusStat: real ? G.str(G.field(item, "infusionBonusStat")) : "", ownBonus: ownBonus};
    }

    static var realCount = 0;

    /**
     * Every item of the game the hero could wear (class, level) that `slotOk` puts in some slot and that
     * `available` says can be obtained, created by the game itself (st.Item.create at the hero's level) so its
     * affixes are exactly those of a real drop, then upgraded to its maximum (Gear.getMaxUpgradeLevel).
     */
    /**
     * One item of the game data as a candidate: the hero can wear it (class, level), `slotOk` puts it in
     * some slot and `available` says it can be obtained; created by the game itself (st.Item.create at the
     * hero's level) so its affixes are exactly those of a real drop; weapons upgraded to their maximum.
     * `typeFits` remembers item types that fit no slot. Null when the item is not a candidate.
     */
    public static function consider(hero:Dynamic, inf:Dynamic, level:Int, typeFits:Map<String, Bool>, slotOk:Candidate->Bool, available:String->Bool):Candidate {
        if (G.field(inf, "gfx") == null) return null;
        var type = G.str(G.field(inf, "type"));
        if (typeFits.get(type) == false) return null; // a type already known not to fit any slot
        var ok = true;
        try ok = G.callStatic("HItem", "hasUnitAptitude", [inf, hero]) == true catch (_:Dynamic) {}
        if (!ok || G.num(G.field(inf, "level")) > level) return null;
        var id = G.str(G.field(inf, "id"));
        try {
            // st.Item.create gives a weapon the drop's rarity (st.item.Weapon(id, level, rarity)); armour has its rarity in its id
            var drop = {count: 1, flags: null, item: id, itemFlags: null, lootLevel: level, lootTableFlags: null, maxRarity: null, minRarity: null, rarity: bestRarity(level)};
            var item = G.callStatic("st.Item", "create", [id, drop]);
            if (item == null || !isGear(item)) { typeFits.set(type, false); return null; }
            var c = candidate(item, "game");
            // the slot rule is the item type's: a type that fits no slot is skipped from now on
            if (!slotOk(c)) { typeFits.set(type, false); return null; }
            typeFits.set(type, true);
            if (!available(id)) return null;
            var max = 0;
            try max = Std.int(G.num(G.call("st.item.Gear", "getMaxUpgradeLevel", [item]))) catch (_:Dynamic) {}
            if (!c.weapon) max = 0; // the upgrade station takes weapons only (ui.win.GearUpgrade)
            if (max > 0) {
                G.call("st.item.Gear", "set_upgradeLevel", [item, max]);
                c.affixes = affixes(item);
                c.upgrade = max;
            }
            return c;
        } catch (e:Dynamic) {
            DebugLog.error("create " + id, e);
            return null;
        }
    }

    static var bestRarityAt = new Map<Int, String>();

    /**
     * The highest rarity that drops at this level (Data.rarity: props.generationChance > 0 for the level), the one with
     * the most gear upgrades: a weapon of the ideal build is valued at it (Legendary at level 25: 5 upgrades, +70 item level).
     */
    public static function bestRarity(level:Int):String {
        if (bestRarityAt.exists(level)) return bestRarityAt.get(level);
        var best:String = null, bestUp = -1.0;
        try {
            var all = G.field(GameData.data("rarity"), "all");
            for (i in 0...G.len(all)) {
                var r = G.at(all, i);
                var props = G.field(r, "props");
                var chances = G.field(props, "generationChance");
                var drops = false;
                for (k in 0...G.len(chances)) {
                    var c = G.at(chances, k);
                    if (G.num(G.field(c, "minLevel")) <= level && level <= G.num(G.field(c, "maxLevel")) && G.num(G.field(c, "chance")) > 0) drops = true;
                }
                var up = G.num(G.field(props, "gearUpgrades"));
                if (drops && up > bestUp) { bestUp = up; best = G.str(G.field(r, "id")); }
            }
        } catch (e:Dynamic) DebugLog.error("best rarity", e);
        bestRarityAt.set(level, best);
        DebugLog.line("items: weapons valued at rarity " + best + " (the highest that drops at level " + level + ", " + bestUp + " upgrades)");
        return best;
    }

    /** An item type is of `kind` or inherits from it (itemType.inherit). */
    public static function isType(type:String, kind:String):Bool {
        var t = type, guard = 0;
        while (t != null && t != "" && guard++ < 8) {
            if (t == kind) return true;
            var rec = typeRecord(t);
            t = rec == null ? null : G.str(G.field(rec, "inherit"));
        }
        return false;
    }

    /** The item type's flags with those of the types it inherits from. */
    static function typeFlags(type:String):Int {
        var t = type, f = 0, guard = 0;
        while (t != null && t != "" && guard++ < 8) {
            var rec = typeRecord(t);
            if (rec == null) break;
            f |= Std.int(G.num(G.field(rec, "flags")));
            t = G.str(G.field(rec, "inherit"));
        }
        return f;
    }

    /**
     * ent.Hero.isActiveOffhandAllowedWithWeapon: an off-hand item works, a shield only with a main weapon whose type has
     * flag 4 (one-handed: OHWeapon; a scepter, staff, book, halos or great weapon is not).
     */
    public static function offhandWorks(main:Candidate, off:Candidate):Bool {
        if (main == null || off == null) return false;
        if (!isType(off.type, "Shield")) return true;
        return (typeFlags(main.type) & 4) != 0;
    }

    /** A slot list of a worn item: copied (hxbit ArrayProxy.copy) for created items that have none. */
    public static var slotsTemplate:Dynamic = null;
    static inline var PROXY = "hxbit._ArrayProxy.ArrayProxy_Impl_";

    /** Sets augments (item ids) in a created item's slots, so the game's tooltip and affixes show them. */
    public static function setSlots(item:Dynamic, ids:Array<Dynamic>):Void {
        try {
            var slots = G.field(item, "slots");
            if (slots == null) {
                if (slotsTemplate == null) { if (ids.length > 0) DebugLog.line("setSlots: no slot list to copy"); return; }
                slots = G.callStatic(PROXY, "copy", [slotsTemplate]);
                G.call("st.item.Gear", "set_slots", [item, slots]);
            }
            G.callStatic(PROXY, "resize", [slots, 0]);
            for (id in ids) G.callStatic(PROXY, "push", [slots, id]);
        } catch (e:Dynamic) DebugLog.error("setSlots " + G.str(G.field(G.field(item, "inf"), "id")), e);
    }
}
