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
        return {entries: [], level: level, maxItems: maxItems, weighted: weighted, affinity: affinity, ownedLast: ownedLast, minRarity: "", pool: 0, anyClass: false};

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

        // texts
        SettingsText.russian = false;
        check("english: offer", SettingsText.chestHow(loot(2, false, true)) == "Opening it offers 2 random items of the list (only for your class): you keep one. Item level: 25.", SettingsText.chestHow(loot(2, false, true)));
        check("english: weighted", SettingsText.chestHow(loot(1, true, false, false, 0)) == "Opening it gives one random item of the list.");
        check("english: owned last and rarity", SettingsText.chestHow(loot(2, false, false, true), "Epic").indexOf("Rarity: Epic or better.") > 0);
        check("english: price", SettingsText.chestPrice(100, "Medal of Glory") == "Price: 100 x Medal of Glory.");
        check("english: where", SettingsText.chestWhere(["A", "B"]) == "Where: A, B.");
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
