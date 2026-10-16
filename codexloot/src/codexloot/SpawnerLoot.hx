package codexloot;

/**
 * Loot tables of spawn points. A spawner may carry `props.overrideLootTable`, which replaces all loot
 * tables of the monsters it spawns (Unit.getLootFromUnit). The game keeps only the monster -> zone link
 * of a spawner (HSpawner.add), so the mod records the spawners itself while the game loads its data.
 */
class SpawnerLoot {
    /** unit id -> override tables of its spawners ("" = a spawner without an override). */
    static var byUnit = new Map<String, Array<String>>();
    /** unit group id -> override tables of its spawners. */
    static var byGroup = new Map<String, Array<String>>();
    public static var count = 0;

    public static function clear():Void {
        byUnit = new Map();
        byGroup = new Map();
        count = 0;
    }

    static function push(m:Map<String, Array<String>>, key:String, table:String):Void {
        if (key == "") return;
        var list = m.get(key);
        if (list == null) m.set(key, list = []);
        if (list.indexOf(table) < 0) list.push(table);
    }

    /** Called with every spawner prefab the game loads. */
    public static function record(prefab:Dynamic):Void {
        var spawner = G.field(prefab, "props");
        if (spawner == null) return;
        var table = G.str(G.field(G.field(spawner, "props"), "overrideLootTable"));
        push(byUnit, G.str(G.field(spawner, "unit")), table);
        push(byGroup, G.str(G.field(spawner, "unitGroup")), table);
        count++;
    }

    static var groupsOfUnit:Map<String, Array<String>>;

    /** unit id -> the unit groups it belongs to (Data.unitGroup composition). */
    static function groups(unitId:String):Array<String> {
        if (groupsOfUnit == null) {
            groupsOfUnit = new Map();
            try {
                var all = G.field(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Data"), "unitGroup"), "all");
                for (i in 0...G.len(all)) {
                    var g = G.at(all, i);
                    var gid = G.str(G.field(g, "id"));
                    var comp = G.field(g, "composition");
                    for (j in 0...G.len(comp)) {
                        var members = G.field(G.at(comp, j), "group");
                        for (k in 0...G.len(members)) push(groupsOfUnit, G.str(G.field(G.at(members, k), "unit")), gid);
                    }
                }
            } catch (_:Dynamic) {}
        }
        var g = groupsOfUnit.get(unitId);
        return g == null ? [] : g;
    }

    /** The override tables of every spawner of the unit ("" = a spawner using the unit's own tables). Empty = no spawner known. */
    public static function tablesFor(unitId:String):Array<String> {
        var out:Array<String> = [];
        function add(list:Array<String>) if (list != null) for (t in list) if (out.indexOf(t) < 0) out.push(t);
        add(byUnit.get(unitId));
        for (g in groups(unitId)) add(byGroup.get(g));
        return out;
    }
}
