package codexloot;

/**
 * The Better Mod Settings page (configFormats.json) and the texts drawn on the Codex window, in the
 * client's language. BMS re-reads that file every time the settings window opens, so the mod writes
 * it once the game's language is known (see CodexLoot.localizeSettings). The English page is also the
 * one shipped in the archive; tests/GenSettings.hx regenerates it.
 */
class SettingsText {
    /** Set by the mod from the game's language option. */
    public static var russian = false;

    public static function isRussian(language:String):Bool
        return language != null && StringTools.startsWith(language.toLowerCase(), "ru");

    public static function heroicCaption():String return russian ? "Героический режим" : "Heroic mode";

    public static function worldCaption():String return russian ? "Экипировка (мировой лут)" : "Equipment (world loot)";

    /** Tag text of a monster class: kind is "Boss", "Elite" or "Spark". */
    public static function tag(kind:String):String {
        if (!russian) return kind;
        return switch (kind) {
            case "Boss": "Босс";
            case "Elite": "Элита";
            case "Spark": "Искра";
            case _: kind;
        }
    }

    // ---- the Chests tab of the Codex ----

    public static function tabCodex():String return russian ? "Кодекс" : "Codex";

    public static function tabChests():String return russian ? "Сундуки" : "Chests";

    public static function chestsHeader():String return russian ? "Содержимое" : "Contents";

    public static function chestsNothing():String return russian ? "Ни в одном сундуке нет предмета с таким названием." : "No chest contains an item with that name.";

    public static function chestNotSold():String
        return russian ? "Ни один торговец его не продаёт: в данных игры не сказано, как его получить." : "No merchant sells it: the game's data does not say how to get it.";

    /** The label of a line of the description in bold (the game's HTML text). */
    static function bold(label:String):String return "<b>" + label + "</b>";

    public static function chestSoldBy(npc:String):String return bold(russian ? "Продаёт:" : "Sold by:") + " " + npc + ".";

    public static function chestWhere(places:Array<String>):String return bold(russian ? "Где:" : "Where:") + " " + places.join(", ") + ".";

    /** The price: every cost is paid together ("100 x Medal of Glory + 20 x Nightblood"). */
    public static function chestPrice(costs:Array<{price:Int, currency:String}>):String
        return bold(russian ? "Цена:" : "Price:") + " " + [for (c in costs) c.price + " x " + c.currency].join(" + ") + ".";

    /** "1 предмет", "2 предмета", "5 предметов". */
    static function ruItems(n:Int):String {
        var m100 = n % 100, m10 = n % 10;
        var word = (m100 >= 11 && m100 <= 14) ? "предметов" : (m10 == 1 ? "предмет" : (m10 >= 2 && m10 <= 4 ? "предмета" : "предметов"));
        return n + " " + word;
    }

    /** How the chest opens: what it gives, at which level, with which rarity (`rarityName` "" = not limited). */
    public static function chestHow(loot:ChestMath.ChestLootResult, rarityName:String = ""):String {
        var parts:Array<String> = [];
        if (loot.weighted)
            parts.push(russian ? "При открытии выдаётся один случайный предмет из списка." : "Opening it gives one random item of the list.");
        else if (loot.maxItems != null)
            parts.push(russian
                ? "При открытии предлагаются " + ruItems(loot.maxItems) + " из списка" + (loot.affinity ? " (только для вашего класса)" : "") + ": вы забираете один."
                : "Opening it offers " + loot.maxItems + " random item" + (loot.maxItems == 1 ? "" : "s") + " of the list" + (loot.affinity ? " (only for your class)" : "") + ": you keep one.");
        else
            parts.push(russian ? "При открытии выдаются все предметы из списка." : "Opening it gives all the items of the list.");
        if (loot.level > 0) parts.push(russian ? "Уровень предметов: " + loot.level + "." : "Item level: " + loot.level + ".");
        if (rarityName != "") parts.push(russian ? "Редкость: " + rarityName + " или выше." : "Rarity: " + rarityName + " or better.");
        if (loot.ownedLast) parts.push(russian ? "Уже имеющиеся у вас предметы предлагаются в последнюю очередь." : "Items you already own are offered last.");
        if (loot.anyClass) parts.push(russian ? "Герой не найден: показаны предметы всех классов (шанс — для героя того класса, которому предмет подходит)." : "No hero found: items of every class are shown (the chance is for a hero of the class that can use the item).");
        else if (loot.hasOthers)
            parts.push(russian ? "Предметы других классов показаны приглушёнными: вам они не выпадут, шанс указан для героя их класса."
                : "Items of other classes are dimmed: you are not offered them, the chance is for a hero of their class.");
        return parts.join(" ");
    }

    static function tip(text:String):Dynamic return {enabled: true, tooltipText: text};

    public static function build(russian:Bool):Dynamic {
        inline function t(en:String, ru:String):String return russian ? ru : en;
        var configs:Array<Dynamic> = [];
        configs.push({type: "title", label: t("Monster loot in the Codex", "Лут монстров в Кодексе")});
        configs.push({key: "enabled", type: "checkbox", label: t("Enabled", "Включено")});
        configs.push({key: "unitTags", type: "checkbox", label: t("Boss / Elite / Spark tags in the monster list", "Метки Босс / Элита / Искра в списке монстров"),
            tooltip: tip(t("Writes Boss, Elite or Spark at the bottom of the monster's frame in the list.",
                "Пишет Босс, Элита или Искра внизу рамки монстра в списке."))});
        configs.push({key: "chestsTab", type: "checkbox", label: t("Chests tab in the Codex", "Вкладка «Сундуки» в Кодексе"),
            tooltip: tip(t("Adds a Chests tab to the Codex window: every chest item (Hero Weapon Cache, Chaotic Gear Cache...) with where to get it, its contents and the chance of each item. The Codex tab is the game's own Codex.",
                "Добавляет в окно Кодекса вкладку «Сундуки»: каждый сундук (Hero Weapon Cache, Chaotic Gear Cache...) с тем, где его взять, содержимым и шансом каждого предмета. Вкладка «Кодекс» — обычный Кодекс игры."))});
        configs.push({key: "lootSearch", type: "checkbox", label: t("Search finds monsters by the name of their loot", "Поиск находит монстров по названию их лута"),
            tooltip: tip(t("Typing in the Codex search keeps the monsters whose name or whose loot (any item, including equipment) contains the text.",
                "При вводе в поиск Кодекса остаются монстры, у которых имя или любой предмет лута (включая экипировку) содержит введённый текст."))});
        configs.push({key: "levelFilter", type: "checkbox", label: t("Hide loot limited to other monster levels", "Скрывать лут, ограниченный другими уровнями монстра"),
            tooltip: tip(t("Off (default) = show all loot of the monster. On = hide entries the game would not drop at the monster's level.",
                "Выкл. (по умолчанию) — показывать весь лут монстра. Вкл. — скрывать то, что игра не выдаёт на уровне монстра."))});
        configs.push({key: "maxItems", type: "slider", label: t("Max extra items", "Макс. добавленных предметов"), min: 10, max: 500, step: 10,
            tooltip: tip(t("Upper bound for the icons the mod adds to the window, most likely drops first.",
                "Предел иконок, которые мод добавляет в окно; сначала самые вероятные."))});
        return {schemaVersion: 1, displayName: t("Codex Loot", "Лут в Кодексе"), configs: configs};
    }

    public static function json(russian:Bool):String return haxe.Json.stringify(build(russian), null, "  ");
}
