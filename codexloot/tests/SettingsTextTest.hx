import codexloot.SettingsText;

class SettingsTextTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function keys(russian:Bool):Array<String> {
        var configs:Array<Dynamic> = SettingsText.build(russian).configs;
        return [for (c in configs) Std.string(Reflect.field(c, "type")) + ":" + Std.string(Reflect.field(c, "key"))];
    }

    static function main():Void {
        check("both languages have the same settings in the same order", keys(false).join(",") == keys(true).join(","));
        check("russian page in russian", SettingsText.json(true).indexOf("Лут монстров в Кодексе") >= 0);
        check("english page has no russian", !~/[А-Яа-я]/.match(SettingsText.json(false)));
        SettingsText.russian = false;
        check("english tags", SettingsText.tag("Boss") == "Boss" && SettingsText.tag("Spark") == "Spark" && SettingsText.heroicCaption() == "Heroic mode");
        SettingsText.russian = true;
        check("russian tags", SettingsText.tag("Boss") == "Босс" && SettingsText.tag("Elite") == "Элита" && SettingsText.tag("Spark") == "Искра");
        check("russian heroic caption", SettingsText.heroicCaption() == "Героический режим");
        check("ru-RU is russian, en is not", SettingsText.isRussian("ru-RU") && !SettingsText.isRussian("en") && !SettingsText.isRussian(null));
        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
