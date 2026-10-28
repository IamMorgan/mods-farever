package farmer;

import farmer.GameAccess as G;

/**
 * The bag services, run from anywhere: the recycler (a ScrapStation of the hero's layer) and the bank. Like the Rift portal's
 * and the dungeon portal's dialogs, the game's own window is opened without walking to the station; the items are moved by the
 * game's own transfer request (st.Inventory.requestTransfer), one per frame step, and the recycler's own "scrap" request ends it.
 */
class Services {
    /** The hero's bag. */
    public static function bag(hero:Dynamic):Dynamic return G.field(G.field(hero, "loadout"), "inventory");

    public static function freeSlots(hero:Dynamic):Int {
        var inv = bag(hero);
        return inv == null ? 99 : G.integer(G.call("st.Inventory", "getFreeSize", inv));
    }

    public static function isOk(reason:Dynamic):Bool {
        if (reason == null) return false;
        try return Type.enumConstructor(reason) == "Ok" catch (_:Dynamic) return false;
    }

    public static function stacks(inv:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        if (inv == null) return out;
        var list = G.field(inv, "content");
        for (i in 0...G.len(list)) {
            var stack = G.at(list, i);
            if (stack != null && G.field(stack, "item") != null) out.push(stack);
        }
        return out;
    }

    public static function itemId(item:Dynamic):String return G.s(G.field(G.field(item, "inf"), "id"));

    public static function itemRarity(item:Dynamic):String {
        var r = G.s(G.field(item, "rarity"));
        if (r == "") r = G.s(G.field(G.field(item, "inf"), "rarity"));
        return r;
    }

    static var gearCache:Map<String, Bool> = new Map();

    /** Equipment (armor, weapons, rings, necklaces, trinkets), not tools, gliders or collectibles. */
    public static function isGear(item:Dynamic):Bool {
        var typeId = G.s(G.field(G.field(item, "inf"), "type"));
        var known = gearCache.get(typeId);
        if (known != null) return known;
        var types = new Map<String, Dynamic>();
        for (rec in G.sheet("itemType")) types.set(G.s(G.field(rec, "id")), rec);
        var gear = false;
        var current = typeId;
        var guard = 0;
        while (current != "" && guard++ < 12) {
            if (current == "GearTool" || current == "GearGlider" || current == "Collection") { gear = false; break; }
            if (current == "Gear") gear = true;
            current = G.s(G.field(types.get(current), "inherit"));
        }
        gearCache.set(typeId, gear);
        return gear;
    }

    // ---- the recycler ----

    static inline var STATION_FILE = "hlx/config/farmer/stations.json";
    /** Where a recycler was seen (the layer holds only the loaded chunks' stations, so a far hero finds none): kept between sessions. The home city's one is the first guess. */
    static var stationAt:Null<{x:Float, y:Float}> = null;
    static var stationRead = false;
    static var stationScanAt = -100.0;
    /** The last recycler entity seen: its window is tried from afar with it (the player's recycler inventory is in the loadout). */
    public static var cachedStation:Dynamic = null;
    public static var remoteBad = false;

    /** The recycler's place, remembered from an earlier sighting (or the home city's), null when none is known. */
    public static function stationSpot():Null<{x:Float, y:Float}> {
        if (!stationRead) {
            stationRead = true;
            stationAt = {x: -340.0, y: 1430.0}; // (the home city's recycler, seen in the 25.10 log)
            try {
                if (sys.FileSystem.exists(STATION_FILE)) {
                    var d:Dynamic = haxe.Json.parse(sys.io.File.getContent(STATION_FILE));
                    if (Reflect.field(d, "x") != null && Reflect.field(d, "y") != null) stationAt = {x: Reflect.field(d, "x"), y: Reflect.field(d, "y")};
                }
            } catch (_:Dynamic) {}
        }
        return stationAt;
    }

    /** Every few seconds: a recycler in the loaded world is remembered (and written down when its place is new). */
    public static function noteStation(hero:Dynamic, now:Float):Void {
        if (now - stationScanAt < 5) return;
        stationScanAt = now;
        try {
            var st = scrapStation(hero);
            if (st != null) cachedStation = st;
            if (st == null) return;
            var x = G.number(G.field(st, "posx")), y = G.number(G.field(st, "posy"));
            var known = stationSpot();
            if (known != null && Math.abs(known.x - x) < 3 && Math.abs(known.y - y) < 3) return;
            stationAt = {x: x, y: y};
            Log.t("svc", "recycler seen at " + Math.round(x) + "," + Math.round(y) + ": remembered");
            sys.io.File.saveContent(STATION_FILE, haxe.Json.stringify({x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10}));
        } catch (_:Dynamic) {}
    }

    /** The recycler of the hero's layer, or null when none is loaded (it stands in the city, far from the hunting grounds). */
    public static function scrapStation(hero:Dynamic):Dynamic {
        var layer = G.field(hero, "layer");
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        var best:Dynamic = null;
        var bestDistance = Math.POSITIVE_INFINITY;
        for (e in G.fastArray(G.field(layer, "interactibles"))) {
            if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.ScrapStation")) continue;
            var dx = G.number(G.field(e, "posx")) - hx, dy = G.number(G.field(e, "posy")) - hy;
            var d = dx * dx + dy * dy;
            if (d < bestDistance) { bestDistance = d; best = e; }
        }
        return best;
    }

    /** Stacks of the bag that the plan wants recycled and the recycler accepts. */
    public static function scrapCandidates(hero:Dynamic, plan:FarmPlan, stationInv:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var inv = bag(hero);
        for (stack in stacks(inv)) {
            var item = G.field(stack, "item");
            if (!isGear(item) || !plan.recyclesRarity(itemRarity(item))) continue;
            var reason:Dynamic = null;
            try reason = G.call("st.Inventory", "getNoTransferReason", inv, [item, stationInv, null]) catch (_:Dynamic) {}
            if (!isOk(reason)) continue;
            out.push(stack);
        }
        return out;
    }

    /** Is there any gear in the bag the plan wants recycled (so a trip to the recycler is worth it)? */
    public static function hasScrapGear(hero:Dynamic, plan:FarmPlan):Bool {
        for (stack in stacks(bag(hero))) {
            var item = G.field(stack, "item");
            if (isGear(item) && plan.recyclesRarity(itemRarity(item))) return true;
        }
        return false;
    }

    public static function transfer(from:Dynamic, stack:Dynamic, to:Dynamic):Bool {
        var item = G.field(stack, "item");
        var fromIndex = G.integer(G.call("st.Inventory", "getStackIndex", from, [stack]), -1);
        var toIndex = G.integer(G.call("st.Inventory", "getNextFreeIndex", to, [item]), -1);
        if (fromIndex < 0 || toIndex < 0 || toIndex >= G.integer(G.call("st.Inventory", "getSize", to))) return false;
        var reason = G.call("st.Inventory", "requestTransfer", from, [fromIndex, to, toIndex, null, null, (ok:Bool) -> Log.t("svc", "transfer result " + ok)]);
        var check:Dynamic = null;
        try check = G.call("st.Inventory", "getNoTransferReason", from, [item, to, null]) catch (_:Dynamic) {}
        Log.t("svc", "transfer " + itemId(item) + " " + fromIndex + " -> " + toIndex + ": request " + (reason == null ? "null" : Std.string(Type.enumConstructor(reason)) + Std.string(Type.enumParameters(reason)))
            + ", check " + (check == null ? "null" : Std.string(Type.enumConstructor(check)) + Std.string(Type.enumParameters(check))));
        return isOk(reason);
    }

    // ---- selling jewelry ----

    /** Rings, necklaces and the like. */
    public static function isJewelry(item:Dynamic):Bool {
        var id = itemId(item);
        var type = G.s(G.field(G.field(item, "inf"), "type"));
        for (w in ["Finger", "Necklace", "Neck", "Ring", "Amulet", "Trinket"]) if (StringTools.startsWith(id, w + "_") || type.indexOf(w) >= 0) return true;
        return false;
    }

    /** Jewelry of the bag the game lets be sold (to any merchant; the sale needs none near): common and uncommon, and any rarity the plan recycles. */
    public static function sellCandidates(hero:Dynamic, plan:FarmPlan, skip:Map<String, Int>):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var loadout = G.field(hero, "loadout");
        for (stack in stacks(bag(hero))) {
            var item = G.field(stack, "item");
            if (!isGear(item) || !isJewelry(item)) continue;
            var rarity = itemRarity(item);
            if (rarity != "Common" && rarity != "Uncommon" && !plan.recyclesRarity(rarity)) continue;
            var k = itemId(item) + "#" + G.integer(G.call("st.Inventory", "getStackIndex", bag(hero), [stack]), -1);
            if (skip.exists(k) && skip.get(k) >= 3) continue;
            var ok = false;
            try ok = G.call("st.Loadout", "canSellItem", loadout, [item]) == true catch (_:Dynamic) {}
            if (ok) out.push(stack);
        }
        return out;
    }

    // ---- the bank ----

    /** Bank tabs of the hero (st.Inventory each). */
    public static function bankTabs(hero:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var banks = G.field(G.field(hero, "loadout"), "banks");
        if (banks == null) return out;
        return G.array(banks, true);
    }

    /** Stacks of the bag that the bank takes: the resources. */
    public static function bankCandidates(hero:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        for (stack in stacks(bag(hero))) if (Catalog.isResource(itemId(G.field(stack, "item")))) out.push(stack);
        return out;
    }

    /** The bank tab that has room for the item, or null. */
    public static function bankTabFor(hero:Dynamic, item:Dynamic):Dynamic {
        for (tab in bankTabs(hero)) {
            if (tab == null) continue;
            try {
                var index = G.integer(G.call("st.Inventory", "getNextFreeIndex", tab, [item]), -1);
                if (index >= 0 && index < G.integer(G.call("st.Inventory", "getSize", tab))) return tab;
            } catch (_:Dynamic) {}
        }
        return null;
    }
}

/**
 * One run of a service: opens its window, moves items a step at a time and closes the window. `step` is called every frame;
 * it returns "run" while working, "done" when finished and "fail:<why>" when it could not.
 */
class ServiceJob {
    public var kind:String;
    /** Developer hold: the job keeps its window open until this time. */
    public var hold = 0.0;
    var window:Dynamic;
    var stage = 0;
    var nextAt = 0.0;
    var startedAt = 0.0;
    var moved = 0;
    var failures = 0;
    var scrapSent = false;
    var scrapAt = 0.0;
    var rounds = 0;
    var stationInv:Dynamic;
    var station:Dynamic;

    public function new(kind:String) this.kind = kind;

    function gui(app:Dynamic):Dynamic return G.field(app, "gui");

    public function close(app:Dynamic):Void {
        if (window != null && G.field(window, "parent") != null) {
            try G.call("ui.BaseUI", "closeWindow", gui(app), [window, null]) catch (_:Dynamic) {}
        }
        window = null;
    }

    public function step(app:Dynamic, hero:Dynamic, plan:FarmPlan, now:Float):String {
        if (startedAt == 0) startedAt = now;
        if (now - startedAt > (walkTo != null ? 600 : 90)) { close(app); return "fail:timeout"; }
        if (now < nextAt || (stage >= 1 && now < hold)) return "run";
        return kind == "scrap" ? stepScrap(app, hero, plan, now) : kind == "sell" ? stepSell(hero, plan, now) : stepBank(app, hero, plan, now);
    }

    /** Set while the recycler is too far for the server to open it: where the bot has to walk first. */
    public var walkTo:Null<{x:Float, y:Float}> = null;
    /** How near the walk to the recycler has to come (the station itself: a few metres; its remembered place: near enough for it to load). */
    public var walkArrive = 2.2;
    var requestedAt = 0.0;
    var remote = false;
    var attempts = 0;

    public function retry():Void {
        walkTo = null;
        walkArrive = 2.2;
        stage = 0;
        attempts = 1;
    }

    function openedScrapWindow(app:Dynamic):Dynamic {
        for (w in G.array(G.field(gui(app), "windows"))) {
            if (w != null && G.isA(w, "ui.win.Scrap") && G.field(w, "parent") != null && G.field(w, "removed") != true) return w;
        }
        return null;
    }

    /**
     * The recycler's own activation (the request a press of the interact key sends): the server makes the player's recycler
     * inventory and the game opens its window. If the server refuses from afar, the bot walks up to the station first.
     */
    function stepScrap(app:Dynamic, hero:Dynamic, plan:FarmPlan, now:Float):String {
        if (stage == 0) {
            station = Services.scrapStation(hero);
            remote = false;
            // from afar: the player's recycler inventory sits in the loadout once the station was used, so the window is opened with the last station seen
            if (station == null && Services.cachedStation != null && !Services.remoteBad && G.call("st.Loadout", "getElementInventory", G.field(hero, "loadout"), ["ScrapStation"]) != null) {
                station = Services.cachedStation;
                remote = true;
                Log.t("svc", "recycler: opened from afar with the station seen earlier");
            }
            if (station == null) {
                // not loaded here: the remembered place is walked (or flown) to, the station loads as the hero comes near
                var spot = Services.stationSpot();
                if (spot == null || attempts > 0 || !Hunt.onWorld(hero)) return "fail:no recycler in this zone";
                if (Nav.distance(hero, spot.x, spot.y) > 25) { walkTo = {x: spot.x, y: spot.y}; walkArrive = 20; return "run"; }
                return "fail:no recycler at the remembered place";
            }
            var existing = openedScrapWindow(app);
            if (existing != null) { window = existing; stationInv = G.call("ui.win.Scrap", "get_inventory", window); stage = 2; return "run"; }
            // The server makes the player's recycler inventory when the station is first used within reach; once it exists
            // (the hero's loadout holds it) the window can be opened from anywhere, like a portal's.
            var known = G.call("st.Loadout", "getElementInventory", G.field(hero, "loadout"), ["ScrapStation"]);
            if (known != null) {
                window = G.create("ui.win.Scrap", [station, null]);
                stationInv = known;
                stage = 2;
                nextAt = now + 0.4;
                return "run";
            }
            var inRange = false;
            try inRange = G.call("ent.Interactible", "isInRange", station, [hero]) == true catch (_:Dynamic) {}
            // (the last metres to the station may be unwalkable - it stands on a platform: near enough, the request is sent all the same)
            if (!inRange && Nav.distance(hero, G.number(G.field(station, "posx")), G.number(G.field(station, "posy"))) <= 7) inRange = true;
            if (!inRange) {
                walkTo ={x: G.number(G.field(station, "posx")), y: G.number(G.field(station, "posy"))};
                return "run";
            }
            try G.call("ent.Unit", "requestInteractAction", hero, [station]) catch (e:Dynamic) return "fail:activate " + Std.string(e);
            requestedAt = now;
            stage = 1;
            return "run";
        }
        if (stage == 1) {
            var w = openedScrapWindow(app);
            if (w != null) {
                window = w;
                stationInv = G.call("ui.win.Scrap", "get_inventory", window);
                if (stationInv == null) { close(app); return "fail:recycler inventory"; }
                stage = 2;
                nextAt = now + 0.4;
                return "run";
            }
            if (now - requestedAt > 2.5) {
                if (attempts++ < 2) { stage = 0; return "run"; }
                return "fail:the recycler did not open";
            }
            return "run";
        }
        var stationStacks = Services.stacks(stationInv);
        if (stage == 2) {
            var candidates = Services.scrapCandidates(hero, plan, stationInv);
            if (candidates.length == 0 || G.integer(G.call("st.Inventory", "getFreeSize", stationInv)) <= 0) {
                if (stationStacks.length == 0) { close(app); return "done"; }
                stage = 3;
                return "run";
            }
            var sent = false;
            for (c in candidates) if (Services.transfer(Services.bag(hero), c, stationInv)) { sent = true; break; } // locked items refuse: the next one
            if (!sent) { stage = 3; return "run"; }
            nextAt = now + 0.25;
            return "run";
        }
        if (stage == 3) {
            if (stationStacks.length == 0) { // the recycler is empty again: another round, or done
                if (rounds++ > 40) { close(app); return "fail:too many rounds"; }
                stage = 2;
                scrapSent = false;
                return "run";
            }
            if (!scrapSent) {
                scrapSent = true;
                scrapAt = now;
                try G.call("ent.interactible.ScrapStation", "scrap", station, [G.field(hero, "player"), (_:Bool) -> {}]) catch (e:Dynamic) { close(app); return "fail:scrap " + Std.string(e); }
            } else if (now - scrapAt > 6) {
                close(app);
                if (remote) Services.remoteBad = true; // (the server wants the hero by the station: walked to from now on)
                return "fail:the recycler did not take the items";
            }
            nextAt = now + 0.3;
        }
        return "run";
    }

    var sellTries:Map<String, Int> = new Map();
    var sold = 0;

    /** Sells the jewelry of the bag one piece at a time (the game's own sale request, Loadout.sellItem: it needs no merchant in reach). */
    function stepSell(hero:Dynamic, plan:FarmPlan, now:Float):String {
        var candidates = Services.sellCandidates(hero, plan, sellTries);
        if (candidates.length == 0) return "done";
        if (sold++ > 80) return "fail:too many sales";
        var stack = candidates[0];
        var item = G.field(stack, "item");
        var k = Services.itemId(item) + "#" + G.integer(G.call("st.Inventory", "getStackIndex", Services.bag(hero), [stack]), -1);
        sellTries.set(k, (sellTries.exists(k) ? sellTries.get(k) : 0) + 1);
        var reason:Dynamic = null;
        try reason = G.call("st.Loadout", "sellItem", G.field(hero, "loadout"), [item, (ok:Bool) -> Log.t("svc", "sale result " + ok)]) catch (e:Dynamic) return "fail:sell " + Std.string(e);
        Log.t("svc", "sell " + k + " (" + Services.itemRarity(item) + "): " + (reason == null ? "null" : Std.string(Type.enumConstructor(reason))));
        nextAt = now + 0.4;
        return "run";
    }

    function stepBank(app:Dynamic, hero:Dynamic, plan:FarmPlan, now:Float):String {
        if (stage == 0) {
            window = G.create("ui.win.BankWindow", [null]);
            stage = 1;
            nextAt = now + 0.4;
            return "run";
        }
        var candidates = Services.bankCandidates(hero);
        if (candidates.length == 0) { close(app); return "done"; }
        var sent = false, full = false;
        for (stack in candidates) {
            var tab = Services.bankTabFor(hero, G.field(stack, "item"));
            if (tab == null) { full = true; continue; }
            if (Services.transfer(Services.bag(hero), stack, tab)) { sent = true; break; } // locked items refuse: the next one
        }
        if (!sent) { close(app); return full ? "fail:the bank is full" : "done"; }
        nextAt = now + 0.2;
        return "run";
    }
}
