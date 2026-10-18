package buildcalc;

/**
 * The pictures of the calculator, drawn from the game's data and icons (not the game's own widgets:
 * those act on the real hero when clicked):
 *  - the talent tree: root on top, the three branches as separate panels, points chosen / maximum;
 *  - the class skills with their runes (skill masteries) under each one;
 *  - the equipment slots and the weapons.
 * Every icon is a ui.UIElement with the game's own tooltip on hover. Until the calculation exists the
 * pictures show the hero's current choices.
 */
class Views {
    static inline var FRAME = 0xC9B3A3;
    static inline var FRAME_ON = 0xB0814F;
    static inline var FRAME_EMPTY = 0xD8C8BC;
    static inline var BRANCH_BG = 0xEFE3DA;
    static inline var FRAME_SIGIL = 0x8E5BB5;
    static inline var TEXT = 0x4A3A30;

    static function tile(color:Int, alpha:Float = 1.0):Dynamic return G.callStatic("h2d.Tile", "fromColor", [color, 1, 1, alpha]);

    static function middle():Dynamic return HlxRuntime.constructEnum(G.type("h2d.FlowAlign"), "Middle", []);

    /** A panel: a flow with a background colour and padding. */
    public static function panel(parent:Dynamic, vertical:Bool, spacing:Int, width:Int, color:Int, padding:Int):Dynamic {
        var f = Ui.flow(parent, vertical, spacing, width);
        G.call("h2d.Flow", "set_backgroundTile", [f, tile(color)]);
        G.call("h2d.Flow", "set_padding", [f, padding]);
        return f;
    }

    /**
     * An icon from a game gfx record, `size` pixels, on a coloured square; `tip` returns the game's
     * tooltip (ui.BaseTip) shown on hover, `textTip` a plain text one.
     */
    public static function icon(parent:Dynamic, gfx:Dynamic, size:Int, frame:Int, alpha:Float = 1.0, ?tip:Void->Dynamic, ?textTip:String, ?badge:String, ?badgeFont:Dynamic):Dynamic {
        var box = HlxRuntime.constructInstanceByName(G.type("ui.UIElement"), 1, [parent]);
        G.call("h2d.Flow", "set_minWidth", [box, size + 4]);
        G.call("h2d.Flow", "set_minHeight", [box, size + 4]);
        G.call("h2d.Flow", "set_padding", [box, 2]);
        G.call("h2d.Flow", "set_backgroundTile", [box, tile(frame)]);
        if (gfx != null) {
            try {
                var t = G.callStatic("lib.ExtensionsUI", "toTile", [gfx]);
                var bmp = HlxRuntime.constructInstanceByName(G.type("h2d.Bitmap"), 2, [t, box]);
                var w = G.num(G.field(t, "width"));
                if (w > 0) G.call("h2d.Object", "setScale", [bmp, size / w]);
                if (alpha < 1) HlxRuntime.setField(bmp, "alpha", alpha);
            } catch (e:Dynamic) DebugLog.error("icon " + G.str(G.field(gfx, "file")), e);
        }
        if (badge != null && badge != "" && badgeFont != null) DebugLog.guard("badge", () -> Ui.badge(box, badgeFont, badge, size + 4));
        if (tip != null) {
            var getTip = function():Dynamic {
                try return tip() catch (e:Dynamic) { DebugLog.error("tooltip", e); return null; }
            };
            try G.call("ui.UIElement", "set_getTip", [box, getTip]) catch (e:Dynamic) DebugLog.error("set_getTip", e);
        } else if (textTip != null && textTip != "") {
            try G.call("ui.UIElement", "set_textTip", [box, textTip]) catch (e:Dynamic) DebugLog.error("set_textTip", e);
        }
        return box;
    }

    /** The game's skill tooltip for skill `sk` at `rank` (talents: its points; 0 = shown as rank 1). */
    static function skillTip(sk:Dynamic, hero:Dynamic, rank:Int, maxRank:Null<Int>, masteries:Array<String>):Void->Dynamic {
        var id = G.str(G.field(sk, "id"));
        return () -> {
            // no rune list: the game's tooltip adds the skill's runes itself (a list would break its copy)
            var info = GameData.skillInfo(sk, rank, maxRank, null);
            var tip = G.callStatic("ui.Tooltip", "fromSkill", [info, hero, GameData.skillInstance(hero, id)]);
            if (tip == null) DebugLog.line("tooltip: none for skill " + id);
            return tip;
        };
    }

    // ---------------------------------------------------------------- what is shown

    /** The calculated build (null: none). */
    public static var result:Optimizer.BuildResult = null;
    /** The opened template, shown when there is no fresh result. */
    public static var saved:State.Template = null;

    /** Talent ranks shown: the result's, the template's, or the hero's; and the talents given by a sigil. */
    static function shownTalents(hero:Dynamic):{ranks:Map<String, Int>, sigils:Map<String, Bool>, mine:Bool} {
        var ranks = new Map<String, Int>(), sigils = new Map<String, Bool>();
        if (result != null) {
            for (id => r in result.build.talents) ranks.set(id, r);
            var augs = result.build.augs.get(3);
            if (augs != null) for (a in augs) for (id in a.skills) {
                var d = SkillData.get(id);
                if (d != null && d.maxPoints > 0) sigils.set(id, true);
            }
            return {ranks: ranks, sigils: sigils, mine: false};
        }
        if (saved != null && saved.talents != null) {
            for (t in saved.talents) ranks.set(t.id, t.rank);
            if (saved.sigils != null) for (id in saved.sigils) sigils.set(id, true);
            return {ranks: ranks, sigils: sigils, mine: false};
        }
        var trees = G.field(G.field(hero, "inf"), "talentTrees");
        if (G.len(trees) > 0) {
            var talents = G.field(G.at(trees, 0), "talents");
            for (i in 0...G.len(talents)) {
                var id = GameData.idOf(G.field(G.at(talents, i), "skill"));
                var r = GameData.talentRank(hero, id);
                if (r > 0) ranks.set(id, r);
                else if (GameData.skillInstance(hero, id) != null) sigils.set(id, true);
            }
        }
        return {ranks: ranks, sigils: sigils, mine: true};
    }

    // ---------------------------------------------------------------- talents

    public static function talentTree(parent:Dynamic, hero:Dynamic, font:Dynamic, width:Int):Void {
        var trees = G.field(G.field(hero, "inf"), "talentTrees");
        if (G.len(trees) == 0) { Ui.text(parent, font, Texts.noTalents(), TEXT, 14, width); return; }
        var shown = shownTalents(hero);
        var tree = G.at(trees, 0);
        var talents = G.field(tree, "talents");
        var byBranch = new Map<Int, Map<Int, Array<Dynamic>>>(); // branch -> tier -> talents
        var maxTier = 0;
        for (i in 0...G.len(talents)) {
            var t = G.at(talents, i);
            var tier = Std.int(G.num(G.field(t, "tier"))), branch = Std.int(G.num(G.field(t, "branch")));
            if (tier > maxTier) maxTier = tier;
            if (!byBranch.exists(branch)) byBranch.set(branch, new Map());
            var b = byBranch.get(branch);
            if (!b.exists(tier)) b.set(tier, []);
            b.get(tier).push(t);
        }
        var iconSize = 32;
        var spent = 0;

        function talent(parentRow:Dynamic, t:Dynamic):Void {
            var id = GameData.idOf(G.field(t, "skill"));
            var sk = GameData.skill(id);
            // the game's rule (HSkill.getTalentMaxPoints): a talent without props.talent.maxPoints has 1 point (it showed 0/0)
            var max = 1;
            try max = Std.int(G.num(G.callStatic("HSkill", "getTalentMaxPoints", [sk]))) catch (_:Dynamic) {}
            var rank = shown.ranks.exists(id) ? shown.ranks.get(id) : 0;
            var mine = GameData.talentRank(hero, id);
            spent += rank;
            var sigil = shown.sigils.exists(id);
            var box = Ui.flow(parentRow, true, 1);
            G.call("h2d.Flow", "set_horizontalAlign", [box, middle()]);
            // a talent the calculation changes: green frame and text
            var changed = !shown.mine && rank != mine;
            // green: points to add; red: points to take away
            var color = sigil ? 0x7A4FA0 : (changed ? (rank > mine ? 0x3F7A2A : 0xA8402F) : (rank > 0 ? 0x5A3E2B : 0x9A8A7E));
            icon(box, G.field(sk, "gfx"), iconSize, sigil ? FRAME_SIGIL : (changed && rank > mine ? FRAME_NEW : (rank > 0 ? FRAME_ON : FRAME)),
                rank > 0 || sigil ? 1.0 : 0.45, skillTip(sk, hero, sigil ? max : rank, max, []));
            // a sigil node also shows the change of its points (a point taken out: the sigil gives the talent instead)
            var points = changed ? mine + "→" + rank : (rank > 0 ? rank + "/" + max : "");
            Ui.text(box, font, sigil ? Texts.sigil() + (points != "" ? " " + points : "") : (changed ? mine + "→" + rank : rank + "/" + max), color, 13);
        }

        var rootRow = Ui.flow(parent, false, 8, width);
        G.call("h2d.Flow", "set_horizontalAlign", [rootRow, middle()]);
        var root = byBranch.get(0);
        if (root != null) for (tier in 0...maxTier + 1) if (root.exists(tier)) for (t in root.get(tier)) talent(rootRow, t);

        var gap = 10;
        var branchW = Std.int((width - 2 * gap) / 3);
        var branches = Ui.flow(parent, false, gap, width);
        for (branch in [1, 2, 3]) {
            var b = byBranch.get(branch);
            var col = panel(branches, true, 10, branchW, BRANCH_BG, 8);
            G.call("h2d.Flow", "set_horizontalAlign", [col, middle()]);
            G.call("h2d.Flow", "set_minHeight", [col, maxTier * (iconSize + 32)]);
            if (b == null) continue;
            for (tier in 1...maxTier + 1) {
                var list = b.get(tier);
                if (list == null) continue;
                var row = Ui.flow(col, false, 6, branchW - 16);
                G.call("h2d.Flow", "set_horizontalAlign", [row, middle()]);
                for (t in list) talent(row, t);
            }
        }
        var total = result != null ? result.talentPoints : talentPoints(hero);
        // under the tree: the points on the left, the weapons (main, off-hand, arsenal) on the right, in the free space
        // next to the equipment column (the equipment column keeps its height)
        var bottom = Ui.flow(parent, false, 0, width);
        var weaponsW = 300;
        var pts = Ui.flow(bottom, true, 0, width - weaponsW);
        Ui.text(pts, font, Texts.pointsSpent(spent, total), TEXT, 14, width - weaponsW);
        var w = Ui.flow(bottom, false, 12, weaponsW);
        G.call("h2d.Flow", "set_horizontalAlign", [w, HlxRuntime.constructEnum(G.type("h2d.FlowAlign"), "Right", [])]);
        DebugLog.guard("draw: weapons", () -> weapons(w, hero, font));
    }

    static function talentPoints(hero:Dynamic):Int {
        // negative below the level the talents open at (level - UnlockLevel_Talents + 1): none then
        try return Std.int(Math.max(0, G.num(G.call("st.player.HeroSpecialization", "getTotalTalentPoints", [G.field(hero, "specialization")])))) catch (_:Dynamic) return 0;
    }

    // ---------------------------------------------------------------- skills and runes

    /** Class skills shown with their runes: the result's, the template's, or the hero's. */
    static function shownSkills(hero:Dynamic):{skills:Array<String>, runes:Map<String, Array<String>>, mine:Bool} {
        if (result != null) return {skills: result.build.skills, runes: result.build.runes, mine: false};
        if (saved != null && saved.skills != null)
            return {skills: [for (s in saved.skills) s.id], runes: [for (s in saved.skills) s.id => s.runes], mine: false};
        var active = GameData.activeMasteries(hero);
        var skills = [], runes = new Map<String, Array<String>>();
        var list = G.field(hero, "skills");
        for (i in 0...G.len(list)) {
            var d = SkillData.get(G.str(G.field(G.field(G.at(list, i), "inf"), "id")));
            if (d == null || d.type != "ClassSkill" || skills.indexOf(d.id) >= 0) continue;
            skills.push(d.id);
            runes.set(d.id, GameData.skillMasteries(d.inf, active));
        }
        return {skills: skills, runes: runes, mine: true};
    }

    public static function skills(parent:Dynamic, hero:Dynamic, font:Dynamic, width:Int):Void {
        var shown = shownSkills(hero);
        var active = GameData.activeMasteries(hero);
        var outer = Ui.flow(parent, false, 12, width);
        var row = Ui.flow(outer, false, 6);
        for (id in shown.skills) {
            var sk = GameData.skill(id);
            if (sk == null || G.field(sk, "gfx") == null) continue;
            var masteries = G.field(sk, "mastery");
            var col = Ui.flow(row, true, 3);
            G.call("h2d.Flow", "set_horizontalAlign", [col, middle()]);
            var mine = shown.runes.exists(id) ? shown.runes.get(id) : [];
            var heroHas = GameData.skillInstance(hero, id) != null;
            icon(col, G.field(sk, "gfx"), 30, !shown.mine && !heroHas ? FRAME_NEW : FRAME_ON, 1.0, skillTip(sk, hero, 1, null, mine));
            for (m in 0...G.len(masteries)) {
                var rune = G.at(masteries, m);
                var rid = G.str(G.field(rune, "id"));
                var on = mine.indexOf(rid) >= 0;
                var changed = !shown.mine && on && active.indexOf(rid) < 0;
                icon(col, G.field(rune, "gfx"), 22, changed ? FRAME_NEW : (on ? FRAME_ON : FRAME), on ? 1.0 : 0.4, null, runeText(sk, rune, hero));
            }
        }
        DebugLog.line("skills: shown " + shown.skills.join(",") + (shown.mine ? " (the hero's)" : ""));
        DebugLog.guard("weapon skills", () -> weaponSkills(outer, hero, font));
    }

    /** The weapon skills in the hero's slots of the main weapon and of the arsenal weapon: the result's, else the hero's. */
    static function weaponSkills(parent:Dynamic, hero:Dynamic, font:Dynamic):Void {
        var col = Ui.flow(parent, true, 3);
        for (slot in [0, 1]) {
            var ids:Array<String> = [];
            if (result != null) {
                if (result.eval.weaponSkills.exists(slot)) ids = result.eval.weaponSkills.get(slot);
            } else if (saved != null && saved.build != null) {
                ids = templateWeaponSkills(hero, slot);
            } else {
                var item = GameData.equipped(hero, slot);
                if (slot == 1) {
                    for (id in GameData.arsenalSkills(hero, G.field(G.field(item, "inf"), "id"))) ids.push(id);
                } else {
                    var sk = G.field(G.field(item, "inf"), "skills");
                    for (i in 0...G.len(sk)) {
                        var d = SkillData.get(GameData.idOf(G.field(G.at(sk, i), "skill")));
                        if (d != null && d.type == "WeaponSkill" && GameData.skillInstance(hero, d.id) != null) ids.push(d.id);
                    }
                }
            }
            Ui.text(col, font, slot == 0 ? Texts.weaponTitle() : Texts.arsenalTitle(), 0x7A4E2E, 12);
            var row = Ui.flow(col, false, 4);
            // the weapon whose skills these are: the result's, the template's (made again), else the worn one
            var weapon:Dynamic = null;
            var ideal = State.settings.ideal;
            if (result != null) {
                var c = result.build.items.get(slot);
                weapon = c == null ? null : c.item;
            } else if (saved != null && saved.build != null) {
                ideal = saved.settings.ideal;
                for (e in saved.build) if (e.slot == slot) weapon = templateItem(e, hero);
            } else weapon = GameData.equipped(hero, slot);
            for (id in ids) {
                var sk = GameData.skill(id);
                if (sk == null) continue;
                var inst = GameData.skillInstance(hero, id);
                var tip = inst != null && weapon != null && G.str(G.field(G.field(weapon, "inf"), "id")) == G.str(G.field(G.field(GameData.equipped(hero, slot), "inf"), "id"))
                    ? skillTip(sk, hero, 1, null, []) : weaponSkillTip(sk, hero, weapon, ideal);
                icon(row, G.field(sk, "gfx"), 28, result != null && inst == null ? FRAME_NEW : FRAME_ON, 1.0, tip);
            }
        }
    }

    /**
     * The game's tooltip of a weapon skill the hero does not have (ui.TipSkill built with the weapon itself): without a
     * skill instance Tooltip.fromSkill knows no weapon (BaseSkill.getSourceItem), so the numbers from the weapon's power
     * were missing. Rank: the one the calculation valued (ideal: Const.Hero.WeaponSkill_MaxRank; else the hero's).
     */
    static function weaponSkillTip(sk:Dynamic, hero:Dynamic, weapon:Dynamic, ideal:Bool):Void->Dynamic {
        var id = G.str(G.field(sk, "id"));
        return () -> {
            var rank = 1;
            try {
                var progress = G.field(G.call("st.player.HeroSpecialization", "get_player", [G.field(hero, "specialization")]), "progress");
                rank = Std.int(G.num(G.call("st.player.Progress", "getSkillRank", [progress, sk])));
            } catch (_:Dynamic) {}
            if (ideal) try rank = Std.int(Math.max(rank, G.num(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "WeaponSkill_MaxRank")))) catch (_:Dynamic) {}
            var info = GameData.skillInfo(sk, rank, null, null);
            var tip:Dynamic = null;
            try tip = HlxRuntime.constructInstanceByName(G.type("ui.TipSkill"), 6, [info, hero, null, weapon == null ? null : G.field(weapon, "inf"), weapon, null])
            catch (e:Dynamic) DebugLog.error("weapon skill tooltip " + id, e);
            if (tip == null) tip = G.callStatic("ui.Tooltip", "fromSkill", [info, hero, null]);
            return tip;
        };
    }

    /** Name and description of a rune, with its numbers filled in by the game (HText.skillMastery). */
    static function runeText(sk:Dynamic, rune:Dynamic, hero:Dynamic):String {
        var text = G.field(rune, "text");
        var name = G.str(G.field(text, "name"));
        var id = G.str(G.field(rune, "id"));
        var desc = "";
        var info = GameData.skillInfo(sk, 1, null, null); // the game puts the rune in itself
        var inst = GameData.skillInstance(hero, G.str(G.field(sk, "id")));
        try desc = G.str(G.callStatic("HText", "skillMastery", [info, id, inst, null])) catch (e:Dynamic) {
            DebugLog.error("runeText " + G.str(G.field(rune, "id")), e);
            desc = G.str(G.field(text, "desc"));
        }
        return name + (desc != "" ? "\n" + desc : "");
    }

    // ---------------------------------------------------------------- attributes

    static var MAIN = ["Vitality", "Strength", "Dexterity", "Faith", "Intellect"];
    static var OTHER = ["MaxHealth", "Armor", "MagicArmor", "CritChance", "CritDamage", "ArmorPenetration", "SpellPenetration", "Fervor",
        "PhysicalMastery", "MagicMastery", "CooldownReduction", "BlockMitigation", "DodgeChance", "HealthRegen", "HealGivenMultiplier",
        "DamageTakenModifier"];

    static function attrName(id:String):String {
        try {
            var n = G.str(G.callStatic("HText", "attributeById", [id, HlxRuntime.constructEnum(G.type("ETextKind"), "Name", [])]));
            if (n != "") return n;
        } catch (_:Dynamic) {}
        return id;
    }

    static function attrValue(id:String, hero:Dynamic):Float {
        if (result != null && result.stats.exists(id)) return result.stats.get(id);
        var all = G.field(GameData.data("attribute"), "byId");
        try return G.num(G.call("ent.GameObject", "atbVal", [hero, G.num(G.field(G.call("haxe.ds.StringMap", "get", [all, id]), "index")), null])) catch (_:Dynamic) return 0;
    }

    static function isPercent(id:String):Bool {
        try return (Std.int(G.num(G.field(G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("attribute"), "byId"), id]), "flags"))) & 4) != 0 catch (_:Dynamic) return false;
    }

    static function format(id:String, v:Float):String {
        if (isPercent(id)) return Std.string(Math.round(v * 1000) / 10) + "%";
        return Std.string(Math.round(v * 10) / 10);
    }

    /** Damage per second and heals per second of the build (and of the hero now), and its infusion sets. */
    public static function totals(parent:Dynamic, hero:Dynamic, font:Dynamic, width:Int):Void {
        if (result != null) {
            var e = result.eval, n = result.now;
            Ui.text(parent, font, Texts.totalsLine(e.dps, n.dps, e.selfHeal, n.selfHeal, e.allyHeal, n.allyHeal), 0x3F6A2A, 12, width);
        }
    }

    /** The infusions of the build (or of the worn items): each set, the bonuses it gives, how many items are infused. */
    public static function infusions(parent:Dynamic, hero:Dynamic, font:Dynamic, headFont:Dynamic, width:Int):Void {
        // infusion sets: of the result, else of the worn items
        var counts = new Map<String, Int>();
        var fromTemplate = result == null && saved != null && saved.infusions != null;
        if (result != null) counts = result.infusions;
        else if (fromTemplate) for (e in saved.infusions) counts.set(e.id, e.count);
        else for (s in Items.SLOTS) {
            var item = GameData.equipped(hero, s);
            var inf = G.str(G.field(item, "infusion"));
            if (inf != "") counts.set(inf, (counts.exists(inf) ? counts.get(inf) : 0) + 1);
        }
        // the set thresholds of the game (Const.Items.Item_InfusionCaps: 2, 4, 6 items)
        var caps:Array<Int> = [];
        try {
            var c = G.field(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Items"), "Item_InfusionCaps"), "");
            var arr = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Items"), "Item_InfusionCaps");
            for (i in 0...G.len(arr)) caps.push(Std.int(G.num(G.at(arr, i))));
        } catch (_:Dynamic) {}
        var parts = [];
        for (id => n in counts) {
            var name = G.str(G.field(G.field(GameData.skill(id), "texts"), "name"));
            parts.push(Texts.infusionItems(name != "" ? name : id, n));
        }
        Ui.text(parent, headFont, result != null || fromTemplate ? Texts.infusionRecommended() : Texts.infusionNow(), 0x7A4E2E, 16, width);
        if (parts.length == 0) Ui.text(parent, font, Texts.noInfusions(), 0x5A3E2B, 12, width);
        else for (p in parts) Ui.text(parent, font, p, 0x5A3E2B, 12, width);
        // a template: its sets only (it was returned before the list: the template's infusions were not shown)
        if (fromTemplate) return;
        // how many items could carry one
        var can = 0, done = 0;
        for (s in Items.SLOTS) {
            var inf:Dynamic = null, infused = false;
            if (result != null) {
                var c = result.build.items.get(s);
                if (c == null) continue;
                inf = c.inf;
                infused = c.real ? c.infusion != "" : result.build.infusion.exists(s);
            } else {
                var item = GameData.equipped(hero, s);
                if (item == null) continue;
                inf = G.field(item, "inf");
                infused = G.str(G.field(item, "infusion")) != "";
            }
            var ok = false;
            try ok = G.callStatic("HInfusion", "canBeInfused", [inf]) == true catch (_:Dynamic) {}
            if (ok) { can++; if (infused) done++; }
        }
    }

    static function itemName(inf:Dynamic):String {
        var name = "";
        try name = G.str(G.callStatic("HText", "item", [inf, HlxRuntime.constructEnum(G.type("ETextKind"), "Name", []), null])) catch (_:Dynamic) {}
        return name != "" ? name : G.str(G.field(inf, "id"));
    }

    /**
     * Three columns, one line per attribute, never wrapped: the main attributes, then the others split over
     * two columns. The text size is the largest (12 px at most) at which the three columns fit the width.
     */
    public static function attributes(parent:Dynamic, hero:Dynamic, font:Dynamic, headFont:Dynamic, width:Int):Void {
        var gap = 12;
        var half = Math.ceil(OTHER.length / 2);
        var colA = [for (id in MAIN) attrName(id) + ": " + format(id, attrValue(id, hero))];
        var colB = [for (k in 0...half) attrName(OTHER[k]) + ": " + format(OTHER[k], attrValue(OTHER[k], hero))];
        var colC = [for (k in half...OTHER.length) attrName(OTHER[k]) + ": " + format(OTHER[k], attrValue(OTHER[k], hero))];
        var px = 12.0;
        while (px > 8) {
            var w = Ui.textWidth(font, colA, px) + Ui.textWidth(font, colB, px) + Ui.textWidth(font, colC, px) + 2 * gap;
            if (w <= width) break;
            px -= 0.5;
        }
        var cols = Ui.flow(parent, false, gap);
        var a = Ui.flow(cols, true, 3);
        var b = Ui.flow(cols, true, 3);
        var c = Ui.flow(cols, true, 3);
        Ui.text(a, headFont, Texts.mainStats(), 0x7A4E2E, 14);
        Ui.text(b, headFont, Texts.otherStats(), 0x7A4E2E, 14);
        Ui.text(c, headFont, " ", 0x7A4E2E, 14);
        for (t in colA) Ui.text(a, font, t, TEXT, px);
        for (t in colB) Ui.text(b, font, t, TEXT, px);
        for (t in colC) Ui.text(c, font, t, TEXT, px);
        DebugLog.line("attributes: text " + px + " px for width " + width);
    }

    // ---------------------------------------------------------------- equipment

    /** Slots of st.Equipment.content, as the hero profile shows them. */
    static var LEFT = [3, 4, 5, 6, 7, 12];
    static var RIGHT = [8, 9, 10, 11, 13, 14];

    static inline var FRAME_NEW = 0x7FA36B;

    /**
     * Items shown in the arsenal cell that the hero does not wear there. The game's item tooltip (ui.TipItem.init) gives
     * an item its slot's share of the attributes (st.Equipment.getAffixFactor) only when the hero's equipment says it is
     * worn (st.Equipment.isEquipped, getEquipSlot): for these items the mod answers "worn in the arsenal" to those two
     * questions (BuildCalc hooks), so the game's own tooltip shows 40% and its arsenal line, as for the worn arsenal
     * weapon. Only the mod's own copies are listed (a real item of the bag is shown by a copy, st.Item.clone), so no
     * real item of the hero is ever taken for worn.
     */
    static var arsenalShown:Array<Dynamic> = [];
    /** The item cells drawn last, by equipment slot (the test mode shows their tooltips). */
    public static var cells = new Map<Int, Dynamic>();
    static var arsenalCopies:Array<{of:Dynamic, copy:Dynamic}> = [];

    static function asArsenal(item:Dynamic, worn:Dynamic):Dynamic {
        if (item == null || item == worn) return item;
        var shown = item;
        if (isHeroItem(item)) {
            shown = null;
            for (x in arsenalCopies) if (x.of == item) shown = x.copy;
            if (shown == null) {
                try shown = G.call("st.Item", "clone", [item, null]) catch (e:Dynamic) DebugLog.error("arsenal tooltip copy", e);
                if (shown == null) return item;
                arsenalCopies.push({of: item, copy: shown});
            }
        }
        if (arsenalShown.indexOf(shown) < 0) arsenalShown.push(shown);
        return shown;
    }

    /** An item of the hero's inventories (equipment, bag, mail, bank): never answered for. */
    static function isHeroItem(item:Dynamic):Bool {
        for (x in Sources.ownItems) if (x == item) return true;
        if (lastHero != null) for (sl in Items.SLOTS) if (GameData.equipped(lastHero, sl) == item) return true;
        return false;
    }

    /** For the hooks: is this one of the arsenal items shown (taken as worn in the arsenal by the game's tooltip)? */
    public static function shownInArsenal(item:Dynamic):Bool return item != null && arsenalShown.indexOf(item) >= 0;

    static function ownItem(e:State.TemplateItem, hero:Dynamic):Dynamic {
        function fits(it:Dynamic):Bool {
            if (it == null || G.str(G.field(G.field(it, "inf"), "id")) != e.id) return false;
            return e.upgrade == null || Std.int(G.num(G.field(it, "upgradeLevel"))) == e.upgrade;
        }
        var worn = GameData.equipped(hero, e.slot);
        if (fits(worn)) return worn;
        for (s in Items.SLOTS) { var w = GameData.equipped(hero, s); if (fits(w)) return w; }
        if (Sources.ownItems.length == 0) Sources.build(hero);
        for (it in Sources.ownItems) if (fits(it)) return it;
        return null;
    }

    /** A saved id as the game's own string (its record's id in Data.<sheet>), else as saved. */
    static function gameId(sheet:String, id:String):Dynamic {
        try {
            var rec = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data(sheet), "byId"), id]);
            var gid:Dynamic = rec == null ? null : G.field(rec, "id");
            if (gid != null) return gid;
        } catch (_:Dynamic) {}
        return id;
    }

    /** The hero of the window being drawn (for texts made without it at hand). */
    static var lastHero:Dynamic = null;

    static function slot(parent:Dynamic, hero:Dynamic, index:Int, size:Int):Void {
        lastHero = hero;
        var worn = GameData.equipped(hero, index);
        var wornId = worn == null ? "" : G.str(G.field(G.field(worn, "inf"), "id"));
        if (result == null && saved != null && saved.build != null) {
            // a saved template: its items made again as they were calculated (level, rarity, upgrade, augments, infusion)
            var entry:State.TemplateItem = null;
            for (e in saved.build) if (e.slot == index) entry = e;
            var id = entry == null ? "" : entry.id;
            var inf = id == "" ? null : G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("item"), "byId"), id]);
            if (inf == null) { icon(parent, null, size, FRAME_EMPTY); return; }
            var shown = templateItem(entry, hero);
            var f = slotFactor(index);
            var tip = f != 1 && shown != null ? arsenalText(shown, f) : null;
            if (f != 1) arsenalTip = tip;
            // the game's own tooltip; an arsenal weapon the hero does not wear there is shown as worn in the arsenal
            if (f != 1 && shown != null && index == 1) shown = asArsenal(shown, GameData.equipped(hero, index));
            var tipItem = shown;
            var cell = icon(parent, G.field(inf, "gfx"), size, wornId != id ? FRAME_NEW : FRAME_ON, 1.0, () -> G.callStatic("ui.Tooltip", "fromItem", [inf, tipItem]),
                null, wornId != id ? Sources.label(id) : null, labelFont);
            cells.set(index, cell);
            if (entry.infusion != null && entry.infusion != "") DebugLog.guard("infusion mark", () -> infusionMark(cell, entry.infusion, entry.infusion, size + 4));
            return;
        }
        var item = worn;
        var changed = false;
        var wornInfusion = worn == null ? "" : G.str(G.field(worn, "infusion"));
        var infusion = wornInfusion;
        if (result != null) {
            var c = result.build.items.get(index);
            item = c == null ? null : c.item;
            changed = c != result.worn.items.get(index);
            infusion = c == null ? "" : (result.build.infusion.exists(index) ? result.build.infusion.get(index) : (c.real ? c.infusion : ""));
            if (infusion == null) infusion = "";
        }
        if (item == null) { icon(parent, null, size, FRAME_EMPTY); return; }
        var infusionChanged = result != null && infusion != wornInfusion;
        var inf = G.field(item, "inf");
        var id = G.str(G.field(inf, "id"));
        // the game's tooltip shows the item with its upgrade, slot augments and infusion; the arsenal slot
        // gives only a share of the item's attributes, which the game's tooltip does not show: our own text
        // the bottom label tells where to get the item; a changed infusion shows in the corner mark (and the tooltip)
        var owned = result != null && result.build.items.get(index) != null && result.build.items.get(index).source == "owned";
        var label = !changed ? null : (id == wornId ? Texts.improveLabel() : (owned ? Texts.ownLabel() : Sources.label(id)));
        if (result != null && result.display != null && result.display.exists(index)) item = result.display.get(index);
        var frame = changed || infusionChanged ? FRAME_NEW : FRAME_ON;
        var f = slotFactor(index);
        // every item, the arsenal weapon too, shows the game's own tooltip; what the arsenal gives (its share of the
        // attributes, its skills) is on the caption above the arsenal cell
        if (f != 1) arsenalTip = arsenalText(item, f);
        // the cell always shows the game's own item tooltip (a weapon the hero does not have too: our plain text there
        // looked broken); the arsenal share (40%) and its skills are on the caption above the cell
        // an arsenal weapon the hero does not wear there: the game's tooltip shows it as worn in the arsenal (40%)
        if (f != 1 && index == 1) item = asArsenal(item, worn);
        var tipItem = item;
        var cell = icon(parent, G.field(inf, "gfx"), size, frame, 1.0, () -> G.callStatic("ui.Tooltip", "fromItem", [inf, tipItem]), null, label, labelFont);
        cells.set(index, cell);
        if (infusion != "" || infusionChanged) DebugLog.guard("infusion mark", () -> infusionMark(cell, infusion, wornInfusion, size + 4));
    }

    /** A template entry of the build's item in slot `s`: what is needed to show it again as calculated. */
    public static function templateEntry(b:Model.Build, s:Int, c:Items.Candidate):State.TemplateItem {
        var level:Null<Int> = null, rarity:String = null;
        // the level the item dropped at (st.item.Gear.level, given to st.Item.create), not st.Item.getLevel: that is the item
        // level / 9 with the upgrades in it, an item created at it came out stronger than the one calculated
        try level = Std.int(G.num(G.field(c.item, "level"))) catch (_:Dynamic) {}
        if (level != null && level <= 0) level = null;
        try rarity = G.str(G.field(c.item, "rarity")) catch (_:Dynamic) {}
        var inf = b.infusion.exists(s) ? b.infusion.get(s) : (c.real ? c.infusion : "");
        return {slot: s, id: c.id, lootLevel: level, own: c.real, rarity: rarity == "" ? null : rarity, upgrade: c.upgrade,
            augs: b.augs.exists(s) ? [for (a in b.augs.get(s)) Std.string(a.raw)] : [], infusion: inf == null ? "" : inf,
            bonus: b.bonus.exists(s) ? b.bonus.get(s) : null};
    }

    static var templateItems = new Map<String, Dynamic>();

    /** The item of a template entry, created by the game (st.Item.create) with the saved level, rarity, upgrade, augments and infusion. */
    static function templateItem(e:State.TemplateItem, hero:Dynamic):Dynamic {
        if (e == null) return null;
        // one of the hero's own items: the real item itself when the hero still has it (worn first, then the bag, mail,
        // bank), not one made again from the data at the hero's level
        if (e.own == true) {
            var real = ownItem(e, hero);
            if (real != null) {
                var inf = e.infusion == null ? "" : e.infusion;
                if (inf == G.str(G.field(real, "infusion"))) return real;
                // the template infuses it again: a copy with the new infusion (the real item is not touched)
                var k = "own|" + haxe.Json.stringify(e);
                if (templateItems.exists(k)) return templateItems.get(k);
                var copy:Dynamic = null;
                try {
                    copy = G.call("st.Item", "clone", [real, null]);
                    G.call("st.item.Gear", "set_infusion", [copy, inf == "" ? null : gameId("skill", inf)]);
                    if (e.bonus != null && e.bonus != "") G.call("st.item.Gear", "set_infusionBonusStat", [copy, gameId("attribute", e.bonus)]);
                } catch (err:Dynamic) DebugLog.error("template own item " + e.id, err);
                templateItems.set(k, copy != null ? copy : real);
                return copy != null ? copy : real;
            }
        }
        var key = haxe.Json.stringify(e);
        if (templateItems.exists(key)) return templateItems.get(key);
        var item:Dynamic = null;
        try {
            var level = e.lootLevel != null ? e.lootLevel : Std.int(G.num(G.field(hero, "_level")));
            var drop = {count: 1, flags: null, item: e.id, itemFlags: null, lootLevel: level, lootTableFlags: null, maxRarity: null, minRarity: null,
                rarity: e.rarity != null ? e.rarity : Items.bestRarity(level)};
            item = G.callStatic("st.Item", "create", [e.id, drop]);
            if (item != null && Items.isGear(item)) {
                if (e.upgrade != null && e.upgrade > 0) G.call("st.item.Gear", "set_upgradeLevel", [item, e.upgrade]);
                // the augments by the game's own id strings (its records' ids): with the saved strings the game's tooltip
                // found the augment but not its attributes ("Cursed Gift" without its -16 / +16)
                // the slot list is copied from a worn item's (taken during a calculation; a template opened before any
                // calculation had none and its augments were dropped)
                if (Items.slotsTemplate == null) for (sl in Items.SLOTS) {
                    var w = GameData.equipped(hero, sl);
                    if (w != null && G.field(w, "slots") != null) { Items.slotsTemplate = G.field(w, "slots"); break; }
                }
                if (e.augs != null) {
                    var byId = G.field(GameData.data("item"), "byId");
                    Items.setSlots(item, [for (a in e.augs) {
                        var rec = G.call("haxe.ds.StringMap", "get", [byId, a]);
                        var gid:Dynamic = rec == null ? null : G.field(rec, "id");
                        gid != null ? gid : a;
                    }]);
                }
                if (e.infusion != null && e.infusion != "") G.call("st.item.Gear", "set_infusion", [item, gameId("skill", e.infusion)]);
                if (e.bonus != null && e.bonus != "") G.call("st.item.Gear", "set_infusionBonusStat", [item, gameId("attribute", e.bonus)]);
            }
        } catch (err:Dynamic) DebugLog.error("template item " + e.id, err);
        templateItems.set(key, item);
        return item;
    }

    static function skillName(id:String):String {
        var n = G.str(G.field(G.field(GameData.skill(id), "texts"), "name"));
        return n != "" ? n : id;
    }

    /** The item's (recommended) infusion: its icon in the cell's corner, the name (and the one it has now) on hover. */
    static function infusionMark(cell:Dynamic, infusion:String, now:String, cellSize:Int):Void {
        var mark = 16;
        var gfx = infusion != "" ? G.field(GameData.skill(infusion), "gfx") : null;
        var tip = infusion != "" ? Texts.infusionOf(skillName(infusion)) : Texts.infusionNone();
        if (infusion != now) tip += "
" + Texts.infusionNowWas(now != "" ? skillName(now) : Texts.infusionNoneShort());
        var m = icon(cell, gfx, mark, infusion != now ? FRAME_NEW : FRAME_ON, 1.0, null, tip);
        HlxRuntime.setField(G.call("h2d.Flow", "getProperties", [cell, m]), "isAbsolute", true);
        G.call("h2d.Object", "setPosition", [m, cellSize - mark - 4, 0]);
    }

    static var labelFont:Dynamic;
    /**
     * The weapon skills of a template's weapon in this slot (0 main, 1 arsenal): as saved; a template saved before kept
     * none, so the weapon's own (main: its weapon skills; arsenal: the ones it may give there, Weapon.isValidArsenalSkill),
     * as many as the hero has slots for — never the skills of the weapon the hero wears now.
     */
    static function templateWeaponSkills(hero:Dynamic, slot:Int):Array<String> {
        if (saved.weaponSkills != null && saved.weaponSkills.length > slot) return saved.weaponSkills[slot];
        var entry:State.TemplateItem = null;
        for (e in saved.build) if (e.slot == slot) entry = e;
        if (entry == null) return [];
        var inf = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("item"), "byId"), entry.id]);
        if (inf == null) return [];
        // the hero's slots: arsenal (ent.Hero.getNbArsenalSkillSlots), main weapon (Const.Hero.UnlockLevel_WeaponSkillSlots)
        var max = 0;
        try {
            var h = hero != null ? hero : lastHero;
            if (slot == 1) max = Std.int(G.num(G.call("ent.Hero", "getNbArsenalSkillSlots", [h])));
            else {
                var levels = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "UnlockLevel_WeaponSkillSlots");
                var level = G.num(G.field(h, "_level"));
                for (i in 0...G.len(levels)) if (G.num(G.at(levels, i)) <= level) max++;
            }
        } catch (e:Dynamic) DebugLog.error("template weapon skill slots", e);
        var out = [];
        var sk = G.field(inf, "skills");
        for (i in 0...G.len(sk)) {
            var id = GameData.idOf(G.field(G.at(sk, i), "skill"));
            var d = SkillData.get(id);
            if (d == null) continue;
            var ok = false;
            if (slot == 1) try ok = G.callStatic("st.item.Weapon", "isValidArsenalSkill", [inf, id]) == true catch (_:Dynamic) {}
            else ok = d.type == "WeaponSkill";
            if (ok && (max <= 0 || out.length < max)) out.push(id);
        }
        return out;
    }

    /** The text of the arsenal caption's tooltip, made by slot() for the arsenal weapon. */
    static var arsenalTip:String = null;

    /** The arsenal weapon: its name, the attributes it gives in the arsenal (× factor) and its arsenal skills. */
    static function arsenalText(item:Dynamic, f:Float):String {
        var inf = G.field(item, "inf");
        var lines = [];
        var name = "";
        try name = G.str(G.callStatic("HText", "item", [inf, HlxRuntime.constructEnum(G.type("ETextKind"), "Name", []), null])) catch (_:Dynamic) {}
        lines.push(name != "" ? name : G.str(G.field(inf, "id")));
        lines.push(Texts.arsenalShare(Math.round(f * 100)));
        var sums = new Map<String, Float>(), order = [];
        for (a in Items.affixes(item)) if (a.kind == "TAttribute_Flat") {
            if (!sums.exists(a.attr)) { sums.set(a.attr, 0); order.push(a.attr); }
            sums.set(a.attr, sums.get(a.attr) + a.val * f);
        }
        for (attr in order) {
            var v = Math.round(sums.get(attr) * 10) / 10;
            lines.push((v >= 0 ? "+" : "") + v + " " + attrName(attr));
        }
        var skills = result != null ? (result.eval.weaponSkills.exists(1) ? result.eval.weaponSkills.get(1) : [])
            : (saved != null && saved.build != null ? templateWeaponSkills(null, 1) : []);
        if (skills.length > 0) {
            lines.push(Texts.arsenalTitle() + ":");
            for (id in skills) lines.push("  " + G.str(G.field(G.field(GameData.skill(id), "texts"), "name")));
        }
        return lines.join("\n");
    }

    /** Share of an item's attributes a slot gives (itemType.slot.affixFactor of the slot: the arsenal). */
    static function slotFactor(s:Int):Float {
        try {
            var name = G.str(G.at(HlxRuntime.resolveStaticField(G.type("DataCache"), "EQUIPMENT_SLOTS"), s));
            var v = G.field(G.field(Items.typeRecord(name), "slot"), "affixFactor");
            if (v != null) return G.num(v);
        } catch (_:Dynamic) {}
        return 1;
    }

    /** The two columns of equipment slots; the row is as wide as they are (BuildTab measures it for the column width). */
    public static function equipment(parent:Dynamic, hero:Dynamic, font:Dynamic, width:Int):Dynamic {
        labelFont = font;
        var size = 44;
        var row = Ui.flow(parent, false, 12);
        var left = Ui.flow(row, true, 8);
        for (i in LEFT) slot(left, hero, i, size);
        var right = Ui.flow(row, true, 8);
        for (i in RIGHT) slot(right, hero, i, size);
        return row;
    }

    /** The weapon cells: main, off-hand (when worn or chosen), arsenal; each with its caption above. */
    static function weapons(parent:Dynamic, hero:Dynamic, font:Dynamic):Void {
        labelFont = font;
        var size = 44;
        var offhand = GameData.equipped(hero, Items.OFFHAND) != null || (result != null && result.build.items.get(Items.OFFHAND) != null)
            || (result == null && saved != null && saved.build != null && Lambda.exists(saved.build, e -> e.slot == Items.OFFHAND));
        for (i in (offhand ? [0, Items.OFFHAND, 1] : [0, 1])) {
            var col = Ui.flow(parent, true, 2);
            G.call("h2d.Flow", "set_horizontalAlign", [col, middle()]);
            var caption = HlxRuntime.constructInstanceByName(G.type("ui.UIElement"), 1, [col]);
            Ui.text(caption, font, i == 0 ? Texts.mainWeapon() : (i == Items.OFFHAND ? Texts.offhandWeapon() : Texts.arsenalWeapon(slotFactor(i))), 0x7A4E2E, 11);
            arsenalTip = null;
            slot(col, hero, i, size + 8);
            if (arsenalTip != null) try G.call("ui.UIElement", "set_textTip", [caption, arsenalTip]) catch (e:Dynamic) DebugLog.error("arsenal caption tip", e);
        }
    }
}
