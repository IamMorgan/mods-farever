import codexloot.ChestMath;
import codexloot.ChestMath.ChestLootResult;
import codexloot.LootMath.Row;
import codexloot.SettingsText;

/** The rules of a chest's loot that need no game data, and the texts of the Chests tab. */
class ChestMathTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function row(item:String, ?minLvl:Int, ?maxLvl:Int, ?flags:Int):Row
        return {item: item, lootTable: "", proba: 1.0, itemMin: null, itemMax: null, minLvl: minLvl, maxLvl: maxLvl, flags: flags};

    static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 1e-9;

    static function loot(?maxItems:Int, weighted = false, affinity = false, ownedLast = false, level = 25):ChestLootResult
        return {entries: [], level: level, maxItems: maxItems, weighted: weighted, affinity: affinity, ownedLast: ownedLast, minRarity: "", pool: 0, anyClass: false, hasOthers: false, legendary: 0, legendaryMax: 0};

    static function main():Void {
        // the level a chest is rolled at
        check("no range: item level / 10", ChestMath.sourceLevel(50, null, null, 40) == 5);
        check("hero level inside the range", ChestMath.sourceLevel(null, 1, 25, 13) == 13);
        check("hero level above the range", ChestMath.sourceLevel(null, 1, 25, 40) == 25);
        check("hero level below the range", ChestMath.sourceLevel(null, 25, 25, 7) == 25);
        check("no hero: the lowest level of the range", ChestMath.sourceLevel(null, 1, 25, null) == 1);

        // level rules of a row
        check("minLvl above the level", !ChestMath.levelPasses(row("A", 3), null, 2));
        check("minLvl equal to the level", ChestMath.levelPasses(row("A", 3), null, 3));
        check("maxLvl below the level", !ChestMath.levelPasses(row("A", null, 4), null, 5));
        check("UseItemLevel: the item's level is the minimum", !ChestMath.levelPasses(row("A", null, null, 4), 4, 3) && ChestMath.levelPasses(row("A", null, null, 4), 4, 4));
        check("without UseItemLevel the item's level is ignored", ChestMath.levelPasses(row("A"), 40, 1));
        check("an explicit minLvl beats the item's level", ChestMath.levelPasses(row("A", 1, null, 4), 40, 1));

        // the offer is a random cut of the rolled items
        var rolled = new Map<String, Float>();
        for (i in 0...25) rolled.set("I" + i, 1.0);
        var cut = ChestMath.offered(rolled, 2, false);
        check("25 sure items, 2 offered: 8% each", near(cut.get("I0"), 0.08) && near(cut.get("I24"), 0.08));
        var four = new Map<String, Float>();
        for (i in 0...4) four.set("I" + i, 1.0);
        check("4 sure items, 2 offered: 50% each", near(ChestMath.offered(four, 2, false).get("I1"), 0.5));
        var two = new Map<String, Float>();
        two.set("A", 1.0);
        two.set("B", 1.0);
        check("2 sure items, 2 offered: 100% each", near(ChestMath.offered(two, 2, false).get("A"), 1.0));
        check("a weighted pick is never cut", near(ChestMath.offered(four, 1, true).get("I0"), 1.0));
        check("no limit, no cut", near(ChestMath.offered(four, null, false).get("I0"), 1.0));
        var half = new Map<String, Float>();
        half.set("A", 0.5);
        half.set("B", 0.5);
        check("few expected items are not cut", near(ChestMath.offered(half, 2, false).get("A"), 0.5));

        // the rarity of a dropped weapon (the data of the game, level 25)
        function band(id:String, index:Int, c:Null<Float>):codexloot.ChestMath.RarityGen
            return {id: id, index: index, bands: c == null ? null : [{minLevel: 1, maxLevel: 10, chance: 0.0}, {minLevel: 11, maxLevel: 30, chance: c}, {minLevel: 31, maxLevel: 10000, chance: 0.5}]};
        var all = [band("Common", 0, null), band("Uncommon", 1, 0.3), band("Rare", 2, 0.5), band("Epic", 3, 0.19), band("Legendary", 4, 0.01)];
        var epicUp = ChestMath.rarityWeights(all, 25, 3, null);
        check("min Epic: Epic and Legendary remain", epicUp.length == 2 && epicUp[0].id == "Epic" && epicUp[1].id == "Legendary");
        check("Common is never rolled", ChestMath.rarityWeights(all, 25, null, null).length == 4);
        check("max Epic drops Legendary", ChestMath.rarityWeights(all, 25, null, 3).length == 3);
        check("level out of every band: no rarity", ChestMath.rarityWeights(all, 0, null, null).length == 0);
        check("Hero Weapon Cache: 0.01 / 0.20 + 1% luck = 6%", near(ChestMath.legendaryChance(epicUp, 0.01, 0.005, 0.25), 0.06));
        check("after 10 failures: 5% + 6% = 11%", near(ChestMath.legendaryChance(epicUp, 0.01, 0.005, 0.25, 10), 0.11));
        check("the luck is capped: 5% + 25%", near(ChestMath.legendaryChance(epicUp, 0.01, 0.005, 0.25, 100000), 0.30));
        check("without Legendary among the rarities: 0", ChestMath.legendaryChance(ChestMath.rarityWeights(all, 25, null, 3), 0.01, 0.005, 0.25) == 0);

        // texts
        SettingsText.russian = false;
        check("english: offer", SettingsText.chestHow(loot(2, false, true)) == "Opening it offers 2 random items of the list (only for your class): you keep one. Item level: 25.", SettingsText.chestHow(loot(2, false, true)));
        check("english: weighted", SettingsText.chestHow(loot(1, true, false, false, 0)) == "Opening it gives one random item of the list.");
        check("english: owned last and rarity", SettingsText.chestHow(loot(2, false, false, true), "Epic").indexOf("Rarity: Epic or better.") > 0);
        check("english: price", SettingsText.chestPrice([{price: 100, currency: "Medal of Glory"}]) == "<b>Price:</b> 100 x Medal of Glory.");
        check("english: two costs", SettingsText.chestPrice([{price: 100, currency: "Medal of Glory"}, {price: 20, currency: "Nightblood"}]) == "<b>Price:</b> 100 x Medal of Glory + 20 x Nightblood.");
        check("english: where", SettingsText.chestWhere(["A", "B"]) == "<b>Where:</b> A, B.");
        check("english: sold by", SettingsText.chestSoldBy("Mira") == "<b>Sold by:</b> Mira.");
        var withLegendary = loot(2);
        withLegendary.legendary = 0.06;
        withLegendary.legendaryMax = 0.3;
        check("english: Legendary share", SettingsText.chestHow(withLegendary).indexOf("chance of a Legendary one is 6% (it grows by 0.5% with every non-Legendary weapon dropped, up to 30%)") > 0, SettingsText.chestHow(withLegendary));
        SettingsText.russian = true;
        check("russian: Legendary share", SettingsText.chestHow(withLegendary).indexOf("шанс легендарного — 6% (растёт") > 0 && SettingsText.chestHow(withLegendary).indexOf("до 30%)") > 0, SettingsText.chestHow(withLegendary));
        SettingsText.russian = true;
        check("russian: offer", SettingsText.chestHow(loot(2, false, true)).indexOf("предлагаются 2 предмета из списка (только для вашего класса)") > 0, SettingsText.chestHow(loot(2, false, true)));
        check("russian: 5 and 21 and 12 items", [5, 21, 12, 1].map(n -> SettingsText.chestHow(loot(n))).join("|").indexOf("5 предметов") > 0
            && SettingsText.chestHow(loot(21)).indexOf("21 предмет ") > 0 && SettingsText.chestHow(loot(12)).indexOf("12 предметов") > 0 && SettingsText.chestHow(loot(1)).indexOf("1 предмет ") > 0);
        check("russian tabs", SettingsText.tabCodex() == "Кодекс" && SettingsText.tabChests() == "Сундуки");
        SettingsText.russian = false;
        check("english tabs", SettingsText.tabCodex() == "Codex" && SettingsText.tabChests() == "Chests");

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
