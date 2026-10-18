package codexloot;

/** One part of a price: an amount of a currency item. */
typedef Cost = {currency:String, price:Int}

/** Where a chest item is sold: the NPC (a unit of the game's data), the hub towns he/she stands in, the price (all the costs are paid together). */
typedef Seller = {unit:String, hubs:Array<String>, costs:Array<Cost>}

/**
 * The chests of the Codex "Chests" tab: items that open into loot (item data props.gainItem, e.g. Hero Weapon Cache,
 * Chaotic Gear Cache), found in the game's data at run time, so chests added by a game update are listed without an update
 * of the mod. Chests of the world (part of the map) and of dungeons (the end-of-dungeon rewards) are not items and are not listed.
 *
 * The game's data does not say who sells an item: that is in the NPC prefabs of the hubs (shop lists), read from the game's
 * files once and written down in sellers.json. A chest that is not in that file has no seller line.
 */
class ChestData {
    

    /** The file with the sellers (next to the mod), see `sellers`. */
    static inline var SELLERS_FILE = "hlx/mods/codexloot/sellers.json";

    static var sellerMap:Map<String, Array<Seller>>;

    /**
     * chest item id -> its sellers. The game's data does not hold this, so it is read from `sellers.json` (a list of
     * {item, unit, hubs, costs: [{currency, price}]}, ids of the game's data); the file is data, not code, and a chest that is not
     * in it is still listed with its complete contents.
     */
    public static function sellers():Map<String, Array<Seller>> {
        if (sellerMap != null) return sellerMap;
        var m = new Map<String, Array<Seller>>();
        try {
            var rows:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(SELLERS_FILE));
            for (r in rows) {
                var costs:Array<Cost> = [for (c in (r.costs : Array<Dynamic>)) {currency: Std.string(c.currency), price: Std.int(c.price)}];
                var seller:Seller = {unit: Std.string(r.unit), hubs: [for (h in (r.hubs : Array<Dynamic>)) Std.string(h)], costs: costs};
                var id = Std.string(r.item);
                if (!m.exists(id)) m.set(id, []);
                m.get(id).push(seller);
            }
        } catch (_:Dynamic) {}
        sellerMap = m;
        return m;
    }

    static var list:Array<Dynamic>;

    /** Forget the list (new game data or language). */
    public static function clear():Void { list = null; sellerMap = null; }

    static function rarityRank(item:Dynamic):Int {
        var r = G.str(G.field(item, "rarity"));
        var all = Sheets.get("rarity");
        var rec = all.get(r);
        var idx = rec == null ? null : G.field(rec, "index");
        return idx == null ? 0 : Std.int(G.num(idx));
    }

    /** All chest items of the game, the sold ones first, then by rarity (best first) and id. */
    public static function chests():Array<Dynamic> {
        if (list != null) return list;
        var out:Array<Dynamic> = [];
        for (id => item in Sheets.get("item"))
            if (ChestLoot.gainOf(item) != null && G.field(item, "gfx") != null) out.push(item);
        out.sort((a, b) -> {
            var ia = G.str(G.field(a, "id")), ib = G.str(G.field(b, "id"));
            var sa = sellers().exists(ia), sb = sellers().exists(ib);
            if (sa != sb) return sa ? -1 : 1;
            var ra = rarityRank(a), rb = rarityRank(b);
            if (ra != rb) return ra > rb ? -1 : 1;
            return Reflect.compare(ia, ib);
        });
        if (out.length > 0) list = out; // empty = data not loaded yet
        return out;
    }

    public static function idOf(chest:Dynamic):String return G.str(G.field(chest, "id"));

    /** The chest's name in the client's language. */
    public static function nameOf(chest:Dynamic):String {
        try {
            var n = G.str(G.callStatic("HItem", "getName", [chest]));
            if (n != "") return n;
        } catch (_:Dynamic) {}
        return Sheets.name("item", idOf(chest));
    }

    /** The game's own description of the chest (item data texts.flavorDesc). */
    public static function flavorOf(chest:Dynamic):String return G.str(G.field(G.field(chest, "texts"), "flavorDesc"));

    /** "Where to get it" and "how it opens" as lines of text in the client's language. */
    public static function describe(chest:Dynamic, loot:ChestMath.ChestLootResult):Array<String> {
        var lines:Array<String> = [];
        var flavor = flavorOf(chest);
        if (flavor != "") lines.push(flavor);
        var sellers = sellers().get(idOf(chest));
        if (sellers == null) {
            lines.push(SettingsText.chestNotSold());
        } else {
            for (s in sellers) {
                lines.push(SettingsText.chestSoldBy(Sheets.name("unit", s.unit)));
                lines.push(SettingsText.chestWhere([for (h in s.hubs) Sheets.name("zone", h)]));
                lines.push(SettingsText.chestPrice([for (c in s.costs) {price: c.price, currency: Sheets.name("item", c.currency)}]));
            }
        }
        lines.push(SettingsText.chestHow(loot, loot.minRarity == "" ? "" : Sheets.name("rarity", loot.minRarity)));
        return lines;
    }
}
