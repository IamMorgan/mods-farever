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
        if (now - startedAt > (walkTo != null ? 240 : 90)) { close(app); return "fail:timeout"; }
        if (now < nextAt || (stage >= 1 && now < hold)) return "run";
        return kind == "scrap" ? stepScrap(app, hero, plan, now) : stepBank(app, hero, plan, now);
    }

    /** Set while the recycler is too far for the server to open it: where the bot has to walk first. */
    public var walkTo:Null<{x:Float, y:Float}> = null;
    var requestedAt = 0.0;
    var attempts = 0;

    public function retry():Void {
        walkTo = null;
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
            if (station == null) return "fail:no recycler in this zone";
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
            if (!inRange) {
                walkTo = {x: G.number(G.field(station, "posx")), y: G.number(G.field(station, "posy"))};
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
                return "fail:the recycler did not take the items";
            }
            nextAt = now + 0.3;
        }
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
