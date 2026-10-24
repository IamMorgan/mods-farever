import dpf.Codec;
import dpf.LevelBrackets;
import dpf.SearchKey;

class CodecTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function main():Void {
        for (text in ["", "a", "ab", "abc", "p_5f3a9c01-77de-4b1a-9e0f-123456789abc", "Привет", "x".substr(0, 1)])
            check("text '" + text + "' survives packing", Codec.unpack(Codec.pack(text)) == text);
        check("long text is cut", Codec.unpack(Codec.pack([for (i in 0...100) "z"].join(""))).length == Codec.MAX_TEXT);
        check("packed numbers are whole numbers", Codec.pack("hello").length == 3);

        var keys = [for (a in ["Z1_POI_Dungeon_A", "Z1_POI_Dungeon_B", "Z2_POI_Dungeon_C"]) for (d in 0...3) for (b in 0...8) SearchKey.make(a, d, b)];
        var seen = new Map<String, Bool>();
        var distinct = true, whole = true, below = true;
        for (k in keys) {
            var h = Codec.hash(k);
            if (seen.exists(Std.string(h))) distinct = false;
            seen.set(Std.string(h), true);
            if (h % 1 != 0) whole = false;
            if (h < 0 || h >= 1e15) below = false;
        }
        check("keys hash apart", distinct);
        check("hash is a whole number", whole);
        check("hash stays below 10^15", below);
        check("hash is repeatable", Codec.hash(keys[3]) == Codec.hash(keys[3]));

        var key = SearchKey.make("Z1_POI_Dungeon_A", 2, 5);
        var parsed = SearchKey.parse(key);
        check("key parses back", parsed != null && parsed.activity == "Z1_POI_Dungeon_A" && parsed.difficulty == 2 && parsed.bracket == 5);
        check("foreign text is not a key", SearchKey.parse("hello") == null && SearchKey.parse(null) == null && SearchKey.parse("dpf1||d0|b0") == null);

        // brackets
        var r = LevelBrackets.ranges(25);
        check("eight brackets for max level 25", r.length == 8 && r[0][0] == 1 && r[6][1] == 24 && r[7][0] == 25 && r[7][1] == 25);
        var same = true;
        for (level in 1...26) {
            var i = LevelBrackets.index(level, 25);
            if (level < r[i][0] || level > r[i][1]) same = false;
        }
        check("every level is inside its bracket", same);
        check("1-3 together", LevelBrackets.index(1, 25) == LevelBrackets.index(3, 25) && LevelBrackets.index(3, 25) != LevelBrackets.index(4, 25));
        check("7 and 8 are apart, 10 and 11 are apart", LevelBrackets.index(7, 25) != LevelBrackets.index(8, 25) && LevelBrackets.index(10, 25) != LevelBrackets.index(11, 25));
        check("18 and 19 are apart, 20 and 21 are apart", LevelBrackets.index(18, 25) != LevelBrackets.index(19, 25) && LevelBrackets.index(20, 25) != LevelBrackets.index(21, 25));
        check("24 and 25 are apart: level 25 meets only level 25", LevelBrackets.index(24, 25) != LevelBrackets.index(25, 25));
        check("level above the cap counts as the cap", LevelBrackets.index(99, 25) == 7 && LevelBrackets.index(0, 25) == 0);
        check("labels", LevelBrackets.label(0, 25) == "1-3" && LevelBrackets.label(7, 25) == "25" && LevelBrackets.label(9, 25) == "");
        var raised = LevelBrackets.ranges(30);
        check("a raised cap keeps the lower brackets and fills the gap", raised.length == 9 && raised[7][0] == 25 && raised[7][1] == 29 && raised[8][0] == 30);

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
