package codexloot;

/** Where a chest item is sold: the NPC (a unit of the game's data), the hub towns he/she stands in, the price in a currency item. */
typedef Seller = {unit:String, hubs:Array<String>, currency:String, price:Int}

/**
 * The chests of the Codex "Chests" tab: items that open into loot (item data props.gainItem, e.g. Hero Weapon Cache,
 * Chaotic Gear Cache), found in the game's data at run time, so chests added by a game update are listed without an update
 * of the mod. Chests of the world (part of the map) and of dungeons (the end-of-dungeon rewards) are not items and are not listed.
 *
 * The game's data does not say who sells an item: that is in the NPC prefabs of the hubs (shop lists), read from the game's
 * files once and written down in SELLERS. A chest nobody sells has no entry.
 */
class ChestData {
    /** The hub towns of the three regions (zones of the game's data: Navelin, Tyrna, Lower Ramburg). */
    static var HUBS = ["Z1_Primevalley_Hub", "Z2_Azuram_Hub", "Z3_CrimsonIsland_South"];

    /** chest item id -> its sellers (NPC shop lists of the hub prefabs: Glory_Merchant, Riftstalker_Intendant, DemonHuntMira_NPC_*). */
    public static var SELLERS:Map<String, Array<Seller>> = [
        "HM_Weapon_Cache_25" => [{unit: "MedalogGloryTrader", hubs: HUBS, currency: "BadgeOfGlory", price: 100}],
        "HM_Gear_Cache_25" => [{unit: "MedalogGloryTrader", hubs: HUBS, currency: "BadgeOfGlory", price: 100}],
        "HM_Demon_Cache_25" => [{unit: "DemonHunterRumi", hubs: HUBS, currency: "BadgeOfGlory", price: 100}],
        "Rift_Gear_Cache" => [{unit: "DemonHunterMira", hubs: HUBS, currency: "Nightblood", price: 10}],
        "Rift_Weapon_Cache" => [{unit: "DemonHunterMira", hubs: HUBS, currency: "Nightblood", price: 10}],
        "Rift_Gift_Cache" => [{unit: "DemonHunterMira", hubs: HUBS, currency: "Nightblood", price: 5}]
    ];

    static var list:Array<Dynamic>;

    /** Forget the list (new game data or language). */
    public static function clear():Void list = null;

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
            var sa = SELLERS.exists(ia), sb = SELLERS.exists(ib);
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
        var sellers = SELLERS.get(idOf(chest));
        if (sellers == null) {
            lines.push(SettingsText.chestNotSold());
        } else {
            for (s in sellers) {
                lines.push(SettingsText.chestSoldBy(Sheets.name("unit", s.unit)));
                lines.push(SettingsText.chestWhere([for (h in s.hubs) Sheets.name("zone", h)]));
                lines.push(SettingsText.chestPrice(s.price, Sheets.name("item", s.currency)));
            }
        }
        lines.push(SettingsText.chestHow(loot, loot.minRarity == "" ? "" : Sheets.name("rarity", loot.minRarity)));
        return lines;
    }
}
