package codexloot;

/** One loot table row, already read from the game's data. Null = the field is not set. */
typedef Row = {
    var item:String;        // "" = none
    var lootTable:String;   // "" = none
    var proba:Float;
    var itemMin:Null<Int>;
    var itemMax:Null<Int>;
    var minLvl:Null<Int>;
    var maxLvl:Null<Int>;
    var flags:Null<Int>;
}

typedef Table = {flags:Int, rows:Array<Row>};

/**
 * The chance of every item to drop at least once from one roll of a loot table, following
 * HItem.generateLootTable:
 *  - table flag 1 (weighted): the table is picked from N times (N = the count of the row that led to
 *    it, 1 at the top); each pick takes one row with the chance proba / sum of proba;
 *  - other tables: every row is rolled on its own (Math.random() < proba), once;
 *  - the count of a row is a random integer itemMin..itemMax (default 1..itemMin); with row flag 1
 *    (inherited by sub-tables) it is fixed by the level between minLvl and maxLvl. A row whose count
 *    comes out 0 drops nothing. In a non-weighted table the count is multiplied by the count passed in;
 *  - a row with a sub-table rolls that table, passing its count.
 * Rows must already be filtered (conditions, levels).
 */
class LootMath {
    /** Biggest count followed exactly; anything above behaves the same for the chance. */
    static inline var MAX_COUNT = 50;

    /** `level`: the level the loot is rolled at, null = unknown (level-scaled counts use their maximum). */
    public var level:Null<Float>;
    var tableOf:String -> Table;

    public function new(tableOf:String -> Table, level:Null<Float>) {
        this.tableOf = tableOf;
        this.level = level;
    }

    static function single(n:Int):Map<Int, Float> {
        var m = new Map<Int, Float>();
        m.set(n, 1.0);
        return m;
    }

    /** Distribution of a row's count (before any multiplication). */
    public function countOf(row:Row, inherited:Int):Map<Int, Float> {
        var flags = (row.flags == null ? 0 : row.flags) | inherited;
        var min = row.itemMin == null ? 1 : row.itemMin;
        var max = row.itemMax == null ? min : row.itemMax;
        if ((flags & 1) != 0) {
            var minL = row.minLvl == null ? 1 : row.minLvl;
            var maxL = row.maxLvl == null ? 1 : row.maxLvl;
            if (minL < maxL) {
                var t = level == null ? 1.0 : Math.max(0.0, Math.min(1.0, (level - minL) / (maxL - minL)));
                min = Math.round(min + t * (max - min));
                max = min;
            }
        }
        var out = new Map<Int, Float>();
        if (max < min) { out.set(min, 1.0); return out; }
        var p = 1.0 / (max - min + 1);
        for (c in min...max + 1) out.set(c, (out.exists(c) ? out.get(c) : 0.0) + p);
        return out;
    }

    static function positive(d:Map<Int, Float>):Float {
        var p = 0.0;
        for (c => w in d) if (c > 0) p += w;
        return p;
    }

    /** The positive part of a count distribution times `by` (each value of `by` with its weight), normalised. */
    static function scaledPositive(d:Map<Int, Float>, by:Map<Int, Float>):Map<Int, Float> {
        var out = new Map<Int, Float>();
        var total = 0.0;
        for (c => w in d) {
            if (c <= 0) continue;
            for (n => v in by) {
                var k = Std.int(Math.min(c * n, MAX_COUNT));
                if (k <= 0) continue;
                out.set(k, (out.exists(k) ? out.get(k) : 0.0) + w * v);
                total += w * v;
            }
        }
        if (total > 0) for (k in out.keys()) out.set(k, out.get(k) / total);
        return out;
    }

    static function combine(m:Map<String, Float>, id:String, p:Float):Void {
        if (p <= 0) return;
        var old = m.exists(id) ? m.get(id) : 0.0;
        m.set(id, 1.0 - (1.0 - old) * (1.0 - Math.min(1.0, p)));
    }

    /** Chance per item for one call of the table, `counts` = distribution of the count passed in. */
    public function roll(table:Table, counts:Map<Int, Float>, inherited:Int, depth:Int = 0):Map<String, Float> {
        var out = new Map<String, Float>();
        if (table == null || depth > 8) return out;
        if ((table.flags & 1) != 0) {
            var total = 0.0;
            for (r in table.rows) total += r.proba;
            if (total <= 0) return out;
            // one pick: the rows are exclusive, so their chances add up
            var pick = new Map<String, Float>();
            for (r in table.rows) {
                if (r.proba <= 0) continue;
                var flags = (r.flags == null ? 0 : r.flags) | inherited;
                var count = countOf(r, inherited);
                var chance = r.proba / total * positive(count);
                if (chance <= 0) continue;
                if (r.item != "") pick.set(r.item, (pick.exists(r.item) ? pick.get(r.item) : 0.0) + chance);
                if (r.lootTable != "") {
                    var sub = roll(tableOf(r.lootTable), scaledPositive(count, single(1)), flags, depth + 1);
                    for (id => p in sub) pick.set(id, (pick.exists(id) ? pick.get(id) : 0.0) + chance * p);
                }
            }
            // N picks, N from `counts`
            for (id => x in pick) {
                var p = 0.0;
                for (n => w in counts) if (n > 0) p += w * (1.0 - Math.pow(1.0 - Math.min(1.0, x), n));
                if (p > 0) out.set(id, p);
            }
        } else {
            for (r in table.rows) {
                var flags = (r.flags == null ? 0 : r.flags) | inherited;
                var count = countOf(r, inherited);
                var chance = Math.max(0.0, Math.min(1.0, r.proba)) * positive(count);
                if (chance <= 0) continue;
                if (r.item != "") combine(out, r.item, chance);
                if (r.lootTable != "") {
                    var sub = roll(tableOf(r.lootTable), scaledPositive(count, counts), flags, depth + 1);
                    for (id => p in sub) combine(out, id, chance * p);
                }
            }
        }
        return out;
    }

    /** One call from the top (count 1), as Unit.getLootFromUnit does for each of its tables. */
    public function rollTop(table:Table):Map<String, Float> return roll(table, single(1), 0);
}
