import macromod.MacroDefs;
import macromod.SettingsText;

class SettingsTextTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function configs(russian:Bool):Array<Dynamic> return SettingsText.build(russian, MacroDefs.MACROS, MacroDefs.STEPS).configs;

    static function keys(russian:Bool):Array<String>
        return [for (c in configs(russian)) Std.string(Reflect.field(c, "type")) + ":" + Std.string(Reflect.field(c, "key"))];

    static function labels(russian:Bool):Array<String> return [for (c in configs(russian)) Std.string(Reflect.field(c, "label"))];

    static function main():Void {
        check("both languages have the same settings in the same order", keys(false).join(",") == keys(true).join(","));
        check("combat-only checkbox is there", keys(false).indexOf("checkbox:combatOnly") >= 0);
        check("russian labels in russian", SettingsText.json(true, 3, 10).indexOf("Активно только в бою") >= 0);
        check("english labels in english", SettingsText.json(false, 3, 10).indexOf("Active only in combat") >= 0
            && ~/[А-Яа-я]/.match(SettingsText.json(false, 3, 10)) == false);

        for (russian in [false, true]) {
            var all = labels(russian);
            var lang = russian ? "ru" : "en";
            check(lang + ": key rows found by their label", all.indexOf(SettingsText.keyLabel(2, russian)) >= 0);
            check(lang + ": step rows found by their label", all.indexOf(SettingsText.stepLabel(3, 10, russian)) >= 0);
            var rowLabels = [for (m in 1...4) SettingsText.keyLabel(m, russian)].concat([for (m in 1...4) for (s in 1...11) SettingsText.stepLabel(m, s, russian)]);
            var unique = true;
            for (l in rowLabels) if (all.filter(x -> x == l).length != 1) unique = false;
            check(lang + ": every key and step label is unique on the page", unique);
        }

        check("mode read from english", SettingsText.modeIndex("Hold") == 1 && SettingsText.modeIndex("Press (Toggle)") == 0);
        check("mode read from russian", SettingsText.modeIndex("Удержание") == 1 && SettingsText.modeIndex("Нажатие (вкл/выкл)") == 0);
        check("unknown mode falls back to toggle", SettingsText.modeIndex(null) == 0 && SettingsText.modeIndex("x") == 0);
        check("russian hold mode is a hold macro", MacroDefs.fromConfig({m1_mode: "Удержание"})[0].hold);

        check("ru, ru-RU and RU are russian", SettingsText.isRussian("ru") && SettingsText.isRussian("ru-RU") && SettingsText.isRussian("RU"));
        check("en and empty are not", !SettingsText.isRussian("en") && !SettingsText.isRussian("") && !SettingsText.isRussian(null));

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
