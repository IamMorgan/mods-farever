package farmer;

/** Quality of the gear to recycle, in the order of the checkboxes. */
enum abstract Quality(Int) to Int {
    var Green = 0;
    var Blue = 1;
    var Epic = 2;
    var Legendary = 3;

    /** The rarity ids of the game's item sheet (Data.rarity). */
    public static var RARITY_IDS = ["Uncommon", "Rare", "Epic", "Legendary"];
    public static var NAMES = ["green", "blue", "epic", "legendary"];
    /** Frame colours of the checkboxes (the game's rarity colours). */
    public static var COLORS = [0x4FBF3F, 0x4F8FEF, 0xB45FEF, 0xF2A32E];
}

/**
 * What the player asked the bot to do, and how much of it is left: the resources to gather (ore, plants) and to hunt
 * (drops of monsters) with the amount wanted of each, the gear to recycle when the bag is full, whether to empty the
 * bag into the bank at the end, and the level to reach. Saved as JSON between sessions.
 */
class FarmPlan {
    public static inline var MAX_COUNT = 99999;
    public static inline var DEFAULT_COUNT = 20;

    /** Item id -> amount still to get. */
    public var gather:Map<String, Int> = new Map();
    public var hunt:Map<String, Int> = new Map();
    public var recycle = false;
    public var recycleQualities:Array<Bool> = [false, false, false, false];
    public var clearBag = false;
    /** While leveling, out of combat, the better gear of the bag is put on (Equip). */
    public var replaceGear = false;
    /** 0: no leveling. */
    public var targetLevel = 0;

    public function new() {}

    public function wanted(hunting:Bool):Map<String, Int> return hunting ? hunt : gather;

    public function isPicked(hunting:Bool, id:String):Bool return wanted(hunting).exists(id);

    public function toggle(hunting:Bool, id:String):Void {
        var m = wanted(hunting);
        if (m.exists(id)) m.remove(id);
        else m.set(id, DEFAULT_COUNT);
    }

    public function setCount(hunting:Bool, id:String, count:Int):Void {
        if (count < 0) count = 0;
        if (count > MAX_COUNT) count = MAX_COUNT;
        wanted(hunting).set(id, count);
    }

    public function count(hunting:Bool, id:String):Int {
        var v = wanted(hunting).get(id);
        return v == null ? 0 : v;
    }

    /** Something is still to be gathered or hunted. */
    public function resourcesLeft():Bool {
        for (v in gather) if (v > 0) return true;
        for (v in hunt) if (v > 0) return true;
        return false;
    }

    public function hasResources():Bool {
        for (k in gather.keys()) return true;
        for (k in hunt.keys()) return true;
        return false;
    }

    public function hasWork():Bool return hasResources() || targetLevel > 0;

    /** Items taken into the bag: the counters go down. Returns true if a counter reached zero. */
    public function credit(id:String, amount:Int):Bool {
        var reached = false;
        for (hunting in [false, true]) {
            var m = wanted(hunting);
            var v = m.get(id);
            if (v == null || v <= 0 || amount <= 0) continue;
            var left = v - amount;
            if (left <= 0) { left = 0; reached = true; }
            m.set(id, left);
        }
        return reached;
    }

    /** The ids of the gathered / hunted items that still count. */
    public function active(hunting:Bool):Array<String> {
        var out = [];
        for (k => v in wanted(hunting)) if (v > 0) out.push(k);
        out.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
        return out;
    }

    public function recyclesRarity(rarityId:String):Bool {
        if (!recycle) return false;
        for (i in 0...Quality.RARITY_IDS.length) if (Quality.RARITY_IDS[i] == rarityId) return recycleQualities[i];
        return false;
    }

    // ---- saving ----

    public function toJson():String {
        var g:Dynamic = {}, h:Dynamic = {};
        for (k => v in gather) Reflect.setField(g, k, v);
        for (k => v in hunt) Reflect.setField(h, k, v);
        return haxe.Json.stringify({gather: g, hunt: h, recycle: recycle, qualities: recycleQualities, clearBag: clearBag, replaceGear: replaceGear, targetLevel: targetLevel}, null, "  ");
    }

    public static function fromJson(text:String):FarmPlan {
        var plan = new FarmPlan();
        try {
            var d:Dynamic = haxe.Json.parse(text);
            var g:Dynamic = Reflect.field(d, "gather"), h:Dynamic = Reflect.field(d, "hunt");
            if (g != null) for (k in Reflect.fields(g)) plan.gather.set(k, Std.int(Reflect.field(g, k)));
            if (h != null) for (k in Reflect.fields(h)) plan.hunt.set(k, Std.int(Reflect.field(h, k)));
            plan.recycle = Reflect.field(d, "recycle") == true;
            var q:Array<Dynamic> = Reflect.field(d, "qualities");
            if (q != null) for (i in 0...Std.int(Math.min(q.length, 4))) plan.recycleQualities[i] = q[i] == true;
            plan.clearBag = Reflect.field(d, "clearBag") == true;
            plan.replaceGear = Reflect.field(d, "replaceGear") == true;
            var level = Reflect.field(d, "targetLevel");
            plan.targetLevel = level == null ? 0 : Std.int(level);
        } catch (_:Dynamic) {}
        return plan;
    }
}
