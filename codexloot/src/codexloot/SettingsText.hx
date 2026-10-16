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

    static function tip(text:String):Dynamic return {enabled: true, tooltipText: text};

    public static function build(russian:Bool):Dynamic {
        inline function t(en:String, ru:String):String return russian ? ru : en;
        var configs:Array<Dynamic> = [];
        configs.push({type: "title", label: t("Monster loot in the Codex", "Лут монстров в Кодексе")});
        configs.push({key: "enabled", type: "checkbox", label: t("Enabled", "Включено")});
        configs.push({key: "unitTags", type: "checkbox", label: t("Boss / Elite / Spark tags in the monster list", "Метки Босс / Элита / Искра в списке монстров"),
            tooltip: tip(t("Writes Boss, Elite or Spark at the bottom of the monster's frame in the list.",
                "Пишет Босс, Элита или Искра внизу рамки монстра в списке."))});
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
