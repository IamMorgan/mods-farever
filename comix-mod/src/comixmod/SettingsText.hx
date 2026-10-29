package comixmod;

/** The Better Mod Settings page in the client's language (the English one is also shipped in the archive). */
class SettingsText {
    public static function isRussian(language:String):Bool
        return language != null && StringTools.startsWith(language.toLowerCase(), "ru");

    public static function json(russian:Bool):String {
        var rows = russian
            ? ["Комикс", "Включить мод", "Включить диалоговые облака (сообщения чата над головой персонажа)",
                "Включить эффект урона (голубой магический урон, комикс-взрыв при крите)", "Размер изображений, %"]
            : ["Comix", "Enable the mod", "Enable speech bubbles (chat messages above the character's head)",
                "Enable damage effects (blue magic numbers, comic burst on a critical hit)", "Image size, %"];
        return haxe.Json.stringify({configs: [
            {type: "title", label: rows[0]},
            {type: "checkbox", label: rows[1], key: "enabled"},
            {type: "checkbox", label: rows[2], key: "bubbleEnabled"},
            {type: "checkbox", label: rows[3], key: "damageEnabled"},
            {type: "slider", label: rows[4], key: "sizePercent", min: 30, max: 200, step: 5}
        ]}, null, "  ");
    }
}
