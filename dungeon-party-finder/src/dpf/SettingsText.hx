package dpf;

/**
 * The Better Mod Settings page (configFormats.json) in the client's language. BMS re-reads the file every time its window
 * opens, so the mod writes it once the game's language is known (see DpfMod.localizeSettings). The English page is also the
 * one shipped in the archive; tests/GenSettings.hx regenerates it.
 */
class SettingsText {
    public static function build(russian:Bool):Dynamic {
        inline function t(en:String, ru:String):String return russian ? ru : en;
        var configs:Array<Dynamic> = [];
        configs.push({key: "showButton", type: "checkbox", label: t("Show the DPF button", "Показывать кнопку DPF")});
        configs.push({key: "unpinned", type: "checkbox",
            label: t("Unpin (drag the DPF button with the left mouse button)", "Открепить (переносить кнопку DPF зажатием левой кнопки мыши)")});
        configs.push({key: "buttonScalePercent", type: "slider", label: t("Button size %", "Размер кнопки, %"), min: 50, max: 200, step: 10});
        return {schemaVersion: 1, displayName: t("Dungeon Party Finder", "Поиск группы в данжи"), configs: configs};
    }

    public static function json(russian:Bool):String return haxe.Json.stringify(build(russian), null, "  ");
}
