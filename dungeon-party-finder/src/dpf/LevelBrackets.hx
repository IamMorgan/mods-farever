package dpf;

/**
 * Level brackets players are matched in: 1-3, 4-7, 8-10, 11-14, 15-18, 19-20, 21-24, and the maximum level on its own
 * (level-25 players only meet level-25 players). The maximum level is read from the game, so a raised cap keeps the
 * brackets below it and just moves the last one.
 */
class LevelBrackets {
    static var BASE:Array<Array<Int>> = [[1, 3], [4, 7], [8, 10], [11, 14], [15, 18], [19, 20], [21, 24]];

    /** Every bracket as [from, to], ending with [maxLevel, maxLevel]. */
    public static function ranges(maxLevel:Int):Array<Array<Int>> {
        var out:Array<Array<Int>> = [];
        for (r in BASE) {
            if (r[0] >= maxLevel) break;
            out.push([r[0], Std.int(Math.min(r[1], maxLevel - 1))]);
        }
        if (out.length > 0 && out[out.length - 1][1] < maxLevel - 1) out.push([out[out.length - 1][1] + 1, maxLevel - 1]);
        out.push([maxLevel, maxLevel]);
        return out;
    }

    /** Index of the bracket a level falls into (levels below 1 count as 1, above the cap as the cap). */
    public static function index(level:Int, maxLevel:Int):Int {
        var all = ranges(maxLevel);
        if (level < 1) level = 1;
        for (i in 0...all.length) if (level >= all[i][0] && level <= all[i][1]) return i;
        return all.length - 1;
    }

    public static function label(index:Int, maxLevel:Int):String {
        var all = ranges(maxLevel);
        if (index < 0 || index >= all.length) return "";
        var r = all[index];
        return r[0] == r[1] ? Std.string(r[0]) : r[0] + "-" + r[1];
    }
}
