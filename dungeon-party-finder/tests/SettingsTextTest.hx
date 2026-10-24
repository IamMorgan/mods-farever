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

        var english = [Locale.listTitle(false), Locale.listHint(false), Locale.listEmpty(false), Locale.level(false, 5), Locale.chooseDifficulty(false),
            Locale.requiredLevel(false, 25), Locale.recommendedLevel(false, 10), Locale.matching(false, 2, "25"), Locale.search(false), Locale.searching(false),
            Locale.cancel(false), Locale.start(false), Locale.ready(false), Locale.waitPlayers(false), Locale.loading(false), Locale.waitLobby(false),
            Locale.found(false, 2, 4), Locale.inviting(false), Locale.partyFormed(false), Locale.inParty(false), Locale.platformDown(false),
            Locale.noHero(false), Locale.locked(false), Locale.partyLost(false), Locale.leaderMark(false), Locale.lobbyRefused(false)];
        var russian = [Locale.listTitle(true), Locale.listHint(true), Locale.listEmpty(true), Locale.level(true, 5), Locale.chooseDifficulty(true),
            Locale.requiredLevel(true, 25), Locale.recommendedLevel(true, 10), Locale.matching(true, 2, "25"), Locale.search(true), Locale.searching(true),
            Locale.cancel(true), Locale.start(true), Locale.ready(true), Locale.waitPlayers(true), Locale.loading(true), Locale.waitLobby(true),
            Locale.found(true, 2, 4), Locale.inviting(true), Locale.partyFormed(true), Locale.inParty(true), Locale.platformDown(true),
            Locale.noHero(true), Locale.locked(true), Locale.partyLost(true), Locale.leaderMark(true), Locale.lobbyRefused(true)];
        var cyrillic = ~/[А-Яа-я]/;
        check("english texts are english", english.filter(s -> cyrillic.match(s)).length == 0);
        check("russian texts are russian", russian.filter(s -> !cyrillic.match(s) && s.indexOf("Lv") < 0).length == 0, russian.filter(s -> !cyrillic.match(s)).join("|"));
        check("search/cancel/start/ready as the spec names them", Locale.search(true) == "Поиск" && Locale.searching(true) == "Поиск..." && Locale.cancel(true) == "Отмена"
            && Locale.start(true) == "Начать" && Locale.ready(true) == "Готов");

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
