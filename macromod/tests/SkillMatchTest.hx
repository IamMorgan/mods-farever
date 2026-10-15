import macromod.SkillMatch;

class SkillMatchTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function main():Void {
        var known:Array<SkillRef> = [
            {kind: "Priest_RadiantVerdict", id: "Priest_RadiantVerdict", name: "Сияющий приговор"},
            {kind: "Priest_FaithfulWinds", id: "Priest_FaithfulWinds", name: "Верные ветра"},
            {kind: "Sword_Slash2", id: "Sword_Slash", name: "Рассечение"}
        ];
        var picks = new Map<String, String>();

        check("name -> kind", SkillMatch.kindFor("Верные ветра", picks, known) == "Priest_FaithfulWinds");
        check("spaces around the name are ignored", SkillMatch.kindFor("  Верные ветра ", picks, known) == "Priest_FaithfulWinds");
        check("old config id -> kind", SkillMatch.kindFor("Priest_RadiantVerdict", picks, known) == "Priest_RadiantVerdict");
        check("data id differing from kind -> kind", SkillMatch.kindFor("Sword_Slash", picks, known) == "Sword_Slash2");
        check("case-insensitive name", SkillMatch.kindFor("верные ВЕТРА", picks, known) == "Priest_FaithfulWinds");
        check("empty step -> null", SkillMatch.kindFor("", picks, known) == null && SkillMatch.kindFor(null, picks, known) == null);
        check("unknown text is passed through", SkillMatch.kindFor("Mystery", picks, known) == "Mystery");
        picks.set("Radiant Verdict", "Priest_RadiantVerdict");
        check("picked name in another language still works", SkillMatch.kindFor("Radiant Verdict", picks, known) == "Priest_RadiantVerdict");

        check("id is shown as its name", SkillMatch.nameForId("Priest_FaithfulWinds", known) == "Верные ветра");
        check("a name stays as is", SkillMatch.nameForId("Верные ветра", known) == null);
        check("unknown text stays as is", SkillMatch.nameForId("Mystery", known) == null);

        check("markup removed", SkillMatch.cleanName("<font color='#fff'>Fire</font>  Ball ") == "Fire Ball");
        check("null name", SkillMatch.cleanName(null) == "");

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
    }
}
