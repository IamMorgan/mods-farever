import dpf.Locale;
import dpf.SettingsText;

class SettingsTextTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function keys(code:String):String {
        Locale.setLanguage(code);
        return [for (c in (SettingsText.build().configs : Array<Dynamic>)) Std.string(Reflect.field(c, "type")) + ":" + Std.string(Reflect.field(c, "key"))].join(",");
    }

    static function texts():Array<String>
        return [Locale.listTitle(), Locale.listEmpty(), Locale.level(5), Locale.search(), Locale.searching(), Locale.cancel(), Locale.inParty(),
            Locale.platformDown(), Locale.noHero(), Locale.partyLost(), Locale.f("showButton"), Locale.f("unpinned"), Locale.f("buttonScale")];

    static function main():Void {
        var english = keys("en");
        var all = true;
        for (code in Locale.LANGS) all = all && keys(code) == english;
        check("every language has the same settings in the same order", all);
        check("the unpin checkbox is there", english.indexOf("checkbox:unpinned") >= 0);
        check("no player-count or log setting", english.indexOf("minPlayers") < 0 && english.indexOf("debugLog") < 0);

        Locale.setLanguage("ru");
        check("russian page in russian", SettingsText.json().indexOf("Открепить") >= 0);
        check("ru, ru-RU, RU and ru_RU are russian", ["ru", "ru-RU", "RU", "ru_RU"].map(c -> Locale.setLanguage(c)).join(",") == "ru,ru,ru,ru");
        check("pt and pt-BR are pt-BR, zh-TW stays zh-TW, zh is zh",
            [Locale.setLanguage("pt"), Locale.setLanguage("pt-BR"), Locale.setLanguage("zh-TW"), Locale.setLanguage("zh-CN"), Locale.setLanguage("zh")].join(",") == "pt-BR,pt-BR,zh-TW,zh,zh");
        check("unknown, empty and null are english", [Locale.setLanguage("xx"), Locale.setLanguage(""), Locale.setLanguage(null)].join(",") == "en,en,en");

        Locale.setLanguage("en");
        var base = texts();
        var cyrillic = ~/[А-Яа-я]/;
        check("english texts are english", base.filter(s -> cyrillic.match(s)).length == 0);
        check("english page has no russian", !cyrillic.match(SettingsText.json()));
        for (code in Locale.LANGS) {
            Locale.setLanguage(code);
            var own = texts();
            check(code + ": every text is there", own.filter(s -> s == "").length == 0 && own.length == base.length);
        }
        Locale.setLanguage("ru");
        check("russian texts are russian", texts().filter(s -> !cyrillic.match(s)).length == 0, texts().filter(s -> !cyrillic.match(s)).join("|"));
        check("search/cancel as the spec names them", Locale.search() == "Поиск" && Locale.searching() == "Поиск..." && Locale.cancel() == "Отмена");
        check("level fills the number", Locale.level(7) == "Ур. 7");
        Locale.setLanguage("en");

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
