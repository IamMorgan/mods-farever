import dpf.Locale;
import dpf.SettingsText;

class SettingsTextTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function keys(russian:Bool):String
        return [for (c in (SettingsText.build(russian).configs : Array<Dynamic>)) Std.string(Reflect.field(c, "type")) + ":" + Std.string(Reflect.field(c, "key"))].join(",");

    static function main():Void {
        check("both languages have the same settings in the same order", keys(false) == keys(true));
        check("the unpin checkbox is there", keys(false).indexOf("checkbox:unpinned") >= 0);
        check("russian page in russian", SettingsText.json(true).indexOf("Открепить") >= 0);
        check("english page has no russian", ~/[А-Яа-я]/.match(SettingsText.json(false)) == false);
        check("ru, ru-RU and RU are russian", Locale.isRussian("ru") && Locale.isRussian("ru-RU") && Locale.isRussian("RU"));
        check("en and empty are not", !Locale.isRussian("en") && !Locale.isRussian("") && !Locale.isRussian(null));

        var english = [Locale.listTitle(false), Locale.listEmpty(false), Locale.level(false, 5), Locale.search(false), Locale.searching(false),
            Locale.cancel(false), Locale.inParty(false), Locale.platformDown(false), Locale.noHero(false), Locale.partyLost(false)];
        var russian = [Locale.listTitle(true), Locale.listEmpty(true), Locale.level(true, 5), Locale.search(true), Locale.searching(true),
            Locale.cancel(true), Locale.inParty(true), Locale.platformDown(true), Locale.noHero(true), Locale.partyLost(true)];
        var cyrillic = ~/[А-Яа-я]/;
        check("english texts are english", english.filter(s -> cyrillic.match(s)).length == 0);
        check("russian texts are russian", russian.filter(s -> !cyrillic.match(s)).length == 0, russian.filter(s -> !cyrillic.match(s)).join("|"));
        check("search/cancel as the spec names them", Locale.search(true) == "Поиск" && Locale.searching(true) == "Поиск..." && Locale.cancel(true) == "Отмена");
        check("no player-count or log setting", keys(false).indexOf("minPlayers") < 0 && keys(false).indexOf("debugLog") < 0);

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
