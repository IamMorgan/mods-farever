package farmer;

import farmer.GameAccess as G;

/**
 * Picks up the player's loot (ent.interactible.LootDrop, not attributed to somebody else) the moment the game lets it be taken:
 * the very request a key press makes (Unit.requestInteractAction), for every drop within the server's pick-up range, a few per
 * frame, so a pile is gone in a handful of frames. The hero never has to stop or press anything. Drops out of the server's reach
 * are left to the bot, which walks up to them (see Loot.nearest).
 */
class Loot {
    static inline var RETRY_GAP = 0.2;
    static inline var MAX_TRIES = 8;
    static inline var GIVE_UP_SECONDS = 20.0;
    static inline var PER_FRAME = 3;

    static var tries:Map<String, Int> = new Map();
    static var retryAt:Map<String, Float> = new Map();
    static var giveUpUntil:Map<String, Float> = new Map();
    static var nextClean = 0.0;

    public static function key(e:Dynamic):String return Std.string(G.field(e, "__uid"));

    /** Every drop of the layer that belongs to the player (landed or not yet). */
    public static function drops(hero:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var player = G.field(hero, "player");
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
            if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.LootDrop")) continue;
            var owner = G.field(e, "attributedPlayer");
            if (owner != null && owner != player) continue; // somebody else's personal drop
            out.push(e);
        }
        return out;
    }

    static function given(e:Dynamic, now:Float):Bool {
        var until = giveUpUntil.get(key(e));
        return until != null && now < until;
    }

    /** Leaves a drop alone for `seconds`. */
    public static function skip(e:Dynamic, now:Float, seconds:Float):Void giveUpUntil.set(key(e), now + seconds);

    /** The nearest drop that has not been given up, within `range` metres of the hero; null when there is none. */
    public static function nearest(hero:Dynamic, range:Float, now:Float):Dynamic {
        var best:Dynamic = null;
        var bestD = range;
        for (e in drops(hero)) {
            if (given(e, now)) continue;
            var d = Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")));
            if (d < bestD) { bestD = d; best = e; }
        }
        return best;
    }

    static var lastErrAt = -100.0;

    /** Called every frame: sends the pick-up requests of the drops in reach. */
    public static function update(hero:Dynamic, now:Float):Void {
        try {
            if (G.call("ent.GameObject", "isDead", hero) == true || G.call("ent.GameObject", "isUnderAnyCC", hero) == true) return;
            var sent = 0;
            for (e in drops(hero)) {
                var k = key(e);
                if (given(e, now) || now < (retryAt.exists(k) ? retryAt.get(k) : 0)) continue;
                if (G.call("ent.Interactible", "isInRange", e, [hero]) != true) continue;
                if (G.call("ent.interactible.LootDrop", "canInteract", e, [hero]) != true) continue; // still flying out of the enemy
                var n = (tries.exists(k) ? tries.get(k) : 0) + 1;
                tries.set(k, n);
                retryAt.set(k, now + RETRY_GAP);
                if (n >= MAX_TRIES) { giveUpUntil.set(k, now + GIVE_UP_SECONDS); Log.t("loot", "drop " + G.typeName(e) + " given up after " + n + " tries"); }
                Log.t("loot", "pick-up request " + n + " for " + G.typeName(e) + " at d=" + Math.round(Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy"))) * 10) / 10);
                G.call("ent.Unit", "requestInteractAction", hero, [e]);
                if (++sent >= PER_FRAME) break;
            }
            if (now >= nextClean) clean(now);
        } catch (error:Dynamic) { if (now - lastErrAt > 30) { lastErrAt = now; Log.err("loot", error); } }
    }

    /** Forgets the drops that are gone. */
    static function clean(now:Float):Void {
        nextClean = now + 30;
        for (k in [for (k in tries.keys()) k]) {
            if ((retryAt.exists(k) ? retryAt.get(k) : 0) + 60 > now) continue;
            tries.remove(k);
            retryAt.remove(k);
            giveUpUntil.remove(k);
        }
    }
}
