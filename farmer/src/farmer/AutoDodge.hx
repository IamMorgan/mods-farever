package farmer;

import farmer.GameAccess as G;
import farmer.DodgeMath.Point2;

/** Where to go: `target`, possibly by way of `via` first (out of a corner); `exit` is how far
    the hero walks to be safe, `jumpAt` how far along the first leg to jump (-1: no jump). */
typedef Spot = {exit:Float, target:Point2, jumpAt:Float, ?via:Point2, ?open:Bool};

/** One danger the hero could step out of. */
private class Threat {
    public var shapes:Array<Dynamic> = [];      // area hit shapes (now and where a moving area will be)
    public var line:Null<DodgeMath.Line> = null; // a straight projectile path
    public var shot:Null<{ox:Float, oy:Float, launch:Float, speed:Float, radius:Float, range:Float}> = null; // a shot still to leave: aimed at the hero as they are then
    public var source:Dynamic = null;           // the projectile (diagnostics)
    public var guessed = false;                 // its timing is a guess (UNKNOWN_DELAY): not worth the dash
    // A train on rails: where its head is over time (t from now, s), how long the cars behind it
    // take to pass a point, and how wide they are. A spot is hit while the train occupies it.
    public var train:Null<{pts:Array<{t:Float, x:Float, y:Float}>, tail:Float, radius:Float}> = null;
    public var hazardName:String = null;        // a moving hazard's kind, for its learnt extra size
    public var mover = false;                   // a moving object's measured way (train-like check)
    public var timed = true;                    // its timing comes from the game, not a default
    public var melee = false;                   // a direct hit on its target (no area): out of the monster's reach
    public var bx = 0.0;                        // a circle the danger's shapes all fit in (br < 0: unknown)
    public var by = 0.0;
    public var br = -1.0;
    public var hitCache:Null<Map<Int, Bool>> = null; // game shape checks this think, by 25 cm cell
    public var swingShape:Dynamic = null;        // an aimed swing's hit shape, built once
    public var swing:Null<{step:Dynamic, x:Float, y:Float, z:Float, range:Float, rotation:Float,
        ownerX:Float, ownerY:Float, turns:Bool, advance:Float, reach:Float}> = null; // a monster's area swing, built when it lands
    public var timeLeft = 0.0;                  // seconds until it hits
    public var lasting = false;                 // keeps hitting while the hero stays in it (ground effects)
    public var projectile = false;              // a projectile: walking must make it with time to spare
    public var fromX = 0.0;                     // where the danger comes from (monster, area, projectile)
    public var fromY = 0.0;
    public function new() {}
}

/**
 * Auto-dodge: steps the hero out of everything that can be stepped out of, before it hits.
 *
 * What is dodged (anything not belonging to a player - monsters, traps, the environment):
 *  - Areas (st.skill.SkillArea in the layer's `areas`): telegraphed AoE, cone/line swings, ground
 *    effects, carts and blades (their skills hit through areas tied to the moving object). The
 *    hit shape is built exactly as the game builds it when it hits (AreaStep.getCollisionShape),
 *    and also where a moving area will be over the next second (its measured speed).
 *    An area still following the hero (aimed attack being lined up) is ignored until the server
 *    lets go of it and it stays put - dodging earlier is pointless, it would just follow.
 *  - Monster swings (basic attacks and the like): an area step that isn't placed in the world
 *    beforehand - the game checks who it catches the moment it lands (AreaStep.doApply), at the
 *    position its props.position.origin names. Read from the monster's running skill: the
 *    not-yet-started area steps, their delay, and their shape (as the game builds it).
 *      - from the monster itself (Owner / OwnerOrigin): it turns with the monster, so a spot
 *        only counts as safe if the swing can't reach it facing that way - out of its reach.
 *        The monster may also close in before it lands: its own dash / gap-close / jump /
 *        teleport steps still to come (their range), plus how far it walks at its measured
 *        speed until the hit. A spot is safe only if the swing misses it even after the monster
 *        came that much closer, straight towards it;
 *      - at an aimed point: stays put;
 *      - at the target (the hero), the instigator, a projectile or an area: it lands wherever the
 *        hero is at that moment - can't be stepped out of, so it is ignored.
 *  - Straight projectiles (ent.Projectile flying forward / to a point / boomerang), once launched:
 *    their path ahead is a line of the projectile's radius. Homing ones can't be dodged: ignored.
 *  - Direct hits on the target with no area of their own (bites, claws): out of the monster's
 *    reach (skill range + body + lunge/steps) before they land, for reaches up to MELEE_MAX.
 *
 * Where to: the nearest spot outside every danger (16 directions, growing distance, straight
 * away from the dangers first), + MARGIN, reached in a straight line that doesn't cross any
 * damaging ground area (puddles and the like) the hero isn't already standing in.
 * How (setting):
 *  - Dash + run: run there if that is fast enough (move speed vs time left before the hit); only
 *    if it isn't, dash first (the game's own dash, if it's ready). If neither makes it in time,
 *    nothing is done - except for lasting ground effects, which are always walked out of.
 *    The run direction replaces the keyboard's in UnitController.getMoveDirection.
 *  - Teleport: moved there at once.
 * The player always wins: while they move the character themselves, auto-dodge does nothing.
 */
class AutoDodge {
    public static inline var MODE_DASH_RUN = 0;
    public static inline var MODE_TELEPORT = 1;

    static inline var MARGIN = 2.0;            // the "+2 m" beyond the danger's edge
    static inline var STEP = 1.0;              // search resolution, in world units (about metres)
    static inline var MAX_SEARCH = 16.0;       // farther than this: no spot worth going to
    static inline var DIRECTIONS = 16;
    static inline var ARRIVED = 0.35;
    static inline var RUN_TIMEOUT = 3.0;
    static inline var TELEPORT_COOLDOWN = 0.3;
    static inline var HERO_RADIUS = 0.6;       // used when the hero's own shape can't be read
    static inline var PREDICT = 1.0;           // how far ahead (s) a moving area's path is checked
    static inline var USER_GRACE = 0.25;       // player input this recent: hands off
    static inline var UNKNOWN_DELAY = 0.5;     // time left assumed when the game doesn't tell
    static inline var REACTION = 0.1;          // safety margin when comparing walk time to time left
    static inline var SWING_REACH = 20.0;      // monsters farther than this can't swing at the hero
    static inline var SHOT_REACH = 45.0;
    static inline var MELEE_DEFAULT = 2.5;     // reach of a direct-hit attack that gives none
    static inline var FAST_ATTACK = 0.6;       // a monster whose attack lands this soon after it starts is kept at a distance
    static inline var MOVER_HORIZON = 1.5;     // a moving object's way is followed this far ahead (s)
    static inline var MOVER_NOTICE = 25.0;     // moving objects this close are watched
    static inline var MOVER_MIN_SPEED = 2.0;   // m/s: slower than this, not a hazard by moving
    static inline var MOVER_MAX_SPEED = 60.0;  // faster: a jump (teleport, respawn), not motion
    static inline var MOVER_MIN_RADIUS = 2.0;  // a moving hazard is at least this wide (half)
    static inline var TRAIN_HORIZON = 3.5;     // a train's way is looked at this far ahead (s)
    static inline var TRAIN_STEP = 0.1;
    static inline var TRAIN_NOTICE = 25.0;     // trains whose way passes this close to the hero are watched
    static inline var HAZARD_LEARN_MAX = 6.0;  // a moving hazard this close (beyond its size) when the hero is hit is taken as the cause
    static inline var TRAIN_WIDTH = 5.0;       // half-width of a car (when its own shape says less)
    static inline var TRAIN_PAD = 0.35;        // seconds of margin before and after a train passes a spot
    static inline var DASH_WINDOW = 0.3;       // a leap or shot is dashed away from only this close to its start
    static inline var LUNGE_SAFETY = 1.5;      // extra distance kept beyond a leap's reach
    static inline var LUNGE_TIME = 0.35;       // a lunge with no timing of its own is assumed to leap this long before it bites
    static inline var BITE_REACH = 2.0;        // what a lunge's bite reaches around where it lands
    static inline var MELEE_WINDUP = 0.3;      // a direct-hit attack with no timing of its own is assumed to land this soon
    static inline var MELEE_LONGEST = 2.5;     // ... and to be over after this long into its skill
    static inline var MELEE_MAX = 6.0;         // direct-hit attacks reaching farther (ranged spells on the target) can't be outrun       // ... but archers this far can still shoot it
    // _Data.Skill_steps_props_position_origin: where an area step lands
    static inline var ORIGIN_OWNER = 0;
    static inline var ORIGIN_TARGET = 1;
    static inline var ORIGIN_PROJECTILE = 2;
    static inline var ORIGIN_INSTIGATOR = 3;
    static inline var ORIGIN_AREA = 6;
    // _Data.Skill_steps_type: steps that move the monster before its swing lands
    static inline var STEP_DASH = 8;
    static inline var STEP_GAP_CLOSE = 9;
    static inline var STEP_TELEPORT = 17;
    static inline var STEP_JUMP = 21;
    static inline var STEP_PROJECTILE = 7;
    static inline var MAX_ADVANCE = 15.0;      // the most a monster is assumed to close in
    static inline var MAX_WALK_ADVANCE = 4.0;  // the most it walks during a swing it can move in
    static inline var MOVING = 0.5;            // m/s: slower than this, the monster stands still
    static inline var DASH_KIND = "Dash_Base";
    static inline var DASH_INPUT = "Dash";
    static inline var AREA_FOLLOW_TARGET = 0;  // areaProps.follow values (SkillArea's follow object)
    static inline var AREA_FOLLOW_OWNER = 1;
    static inline var PROJECTILE_MARGIN = 0.25; // a projectile is dodged by walking only with this much time to spare
    static inline var BODY_HALF_WIDTH = 0.5;  // the way is checked this far either side of the middle line
    static inline var PATH_STEP = 0.5;         // surface height sampled every this many metres along a way
    static inline var UNKNOWN_RETRIES = 2;     // thinks a search may wait for heights to be read
    static inline var RETRY_TIME_LEFT = 0.6;   // ... only with this much time left before the hit
    static inline var SETTLE_TIME = 5.0;       // after the hero appears, auto-dodge waits this long...
    static inline var SETTLE_STILL = 0.5;      // ... and until it has kept its height this long
    static inline var BAD_REPLAN = 0.1;        // with no clean way, ways are looked for again this often
    static inline var INTERRUPT_GRACE = 0.45;  // after the hero's own cast is cut, not "stuck" for this long (cast recovery)
    static inline var SKILL_HOLD = 0.3;        // the hero's own skills wait this long after an attack was last coming
    static inline var GROUND_LOG_TIME = 20.0;
    static inline var AWAY_COST = 2.0;         // score: running straight into the danger instead of away from it
    static inline var TURN_COST = 2.0;         // score: turning right around from the way just run
    static inline var KEEP_HEADING_TIME = 0.6;
    static inline var HEIGHT_BUDGET = 300;     // new surface heights read per think, at most
    static inline var BOUND_PAD = 0.5;         // margin on a danger's bounding circle
    static inline var SHAPE_BUDGET = 2000;     // danger-shape checks through the game per think, at most
    static inline var THINK_INTERVAL = 0.033;  // dangers are looked at and ways planned at most 30 times a second
    static inline var SCAN_BUDGET = 80;        // heights read ahead per think around the hero in a fight
    static inline var SCAN_RADIUS = 14.0;      // ... this far around
    static inline var MAP_RADIUS = 32;         // the open-space map: cells (OpenMap.CELL) either side of the hero
    static inline var MAP_REFRESH = 0.25;      // the map is rebuilt at most this often
    static inline var CACHE_MAX = 200000;      // cached heights kept at most
    static inline var LEVEL_TOLERANCE = 1.0;   // a cached height is reused while the hero's height changed less than this
    static inline var CLEAR_COST = 1.5;        // score: per metre a spot is closer than OPEN_RANGE to a wall, edge or obstacle
    static inline var DIR_COST = 0.6;          // score: per closed direction (of OPEN_DIRECTIONS) around a spot
    static inline var CROWD_COST = 1.5;        // score: per monster within CROWD_RANGE of a spot
    static inline var CROWD_RANGE = 4.0;
    static inline var MAX_TRIED = 40;          // best-scored ways checked against every attack, at most per search
    static inline var SEARCH_RETRY = 0.15;     // after a search found nothing, wait this long before the next
    static inline var HEIGHT_CACHE_TIME = 30.0; // seconds a read height is reused (the world doesn't move)
    static inline var MAX_LUNGE = 6.0;         // a monster leaping further than this lands on the hero: distance can't dodge it
    static inline var STEP_UP = 0.45;          // a rise the hero just walks up
    static inline var JUMP_HEIGHT = 1.2;       // a rise up to this is jumped over; higher blocks the way
    static inline var SURFACE_TOP = 2.2;       // surface height looked for from this far above the hero's feet
    static inline var TALL_TOP = 9.0;          // ... and from this high, for things taller than the hero
    static inline var TALL_HEIGHT = 2.2;
    static inline var PASS_MARGIN = 0.15;      // crossing a danger is fine if it fires this much after the hero is through
    static inline var JUMP_AHEAD = 1.2;        // jump this far before a low obstacle
    static inline var STUCK_TIME = 0.2;        // moved less than STUCK_SHARE of the expected way in this long: blocked
    static inline var STUCK_SHARE = 0.35;
    static inline var MEMORY_CELL = 0.4;       // learnt obstacles: grid size
    static inline var MEMORY_MAX = 4000;       // learnt cells kept at most
    static inline var COMMIT = 0.25;           // a chosen way is kept at least this long before re-planning
    static inline var DASH_DISTANCE = 5.0;     // what the dash covers, and how fast (the plan's estimate)
    static inline var DASH_TIME = 0.25;
    static inline var HIT_EARLY = 0.05;        // an attack is checked a little before and after it lands
    static inline var HIT_LATE = 0.12;
    static inline var MEMORY_TIME = 20.0;      // a learnt obstacle is forgotten after this long
    static inline var BODY_PAD = 0.35;         // monsters' bodies: kept this much further away
    static inline var SHOT_NOTICE = 0.4;       // an archer's shot is dodged from this long before it leaves (earlier is useless: it aims at the hero as they are then)
    static inline var FACING_AIM = 0.5;        // an archer without a target facing the hero this closely (rad) aims at them
    static inline var LATE_SHOT = 0.45;        // a flying projectile first dodged with less time than this was seen late
    static inline var HEIGHT_TRUST = 1.5;      // the height data is used only where it reads this close to the hero's feet
    static inline var OPEN_DIRECTIONS = 16;
    static inline var OPEN_RANGE = 6.0;
    static inline var OPEN_CLEAR = 2.5;        // open ground: the nearest wall at least this far...
    static inline var OPEN_FREE = 10;          // ... and at least this many of the 16 directions free for 6 m
    static inline var REPOSITION_EVERY = 1.0;  // in a fight, a hero against a wall or in a corner moves to the open this often at most        // walls, edges and corners closer than this make a spot worse
    static inline var AVOID_TIME = 1.5;        // how long a blocked direction is avoided
    static inline var PARTIAL_RUN = 6.0;       // no fully safe spot in reach: get at least this far away
    static inline var CORNER_LEG = 3.0;        // first leg out of a corner (and twice that)
    static inline var MAX_DROP = 1.7;          // a drop deeper than this is a cliff: never run off it
    static inline var GROUND_PROBE = 8.0;      // how far down the ground is looked for
    static final MOVE_INPUTS = ["MoveForward", "MoveBack", "MoveLeft", "MoveRight"];

    public static var enabled = false;
    public static var mode = MODE_DASH_RUN;
    /** The teleport mod's own move (chunk preload + teleportPosition, with fallbacks). */
    public static var teleport:(hero:Dynamic, pos:{x:Float, y:Float, z:Float}) -> String;

    static var runTarget:Null<Point2> = null;
    static var runNext:Null<Point2> = null;      // the safe spot, while the first leg (out of a corner) is run
    static var runUntil = 0.0;
    static var runFrom:Null<Point2> = null;      // where the run started (for the jump distance)
    static var runJumpAt = -1.0;                 // jump once this far along the run (-1: no jump)
    static var stuckCheck:Null<{x:Float, y:Float, t:Float}> = null;
    static var avoided:Array<{angle:Float, until:Float}> = [];
    static var lastTeleport = -10.0;
    static var lastUserInput = -10.0;
    static var seen = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>();
    static var unitsSeen = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, speed:Float}>();

    /** Every frame, before the game's own update. */
    static var loggedState = "";

    static var currentHero:Dynamic;
    static var relax = 0;              // 0: everything; 1: learnt obstacles ignored; 2: only monsters' bodies
    static var unknownSeen = false;    // a way couldn't be judged: its heights aren't read yet
    static var unknownRetries = 0;
    static var shapeChecksLeft = 0;
    static var lastThink = -10.0;
    static var holdUntil = -10.0;
    static var lastInterrupt = -10.0;
    static var lastBadPlan = -10.0;
    static var budgetOut = false;
    static var budgetLogged = -10.0;
    static var lastGroundLog = -100.0;
    static var lastRunAngle = 0.0;
    static var lastRunAt = -10.0;
    static var nextSearch = 0.0;

    static var settledHero:Dynamic = null;
    static var settleUntil = 0.0;
    static var settleZ = 0.0;
    static var settleZAt = 0.0;

    /**
     * Nothing at all is done for SETTLE_TIME after the hero appears (logging in, a new zone,
     * a respawn) and until it has stood at the same height for a moment: the world is still
     * being loaded and synced then, and reading its physics (or moving the hero) would only
     * get in the way.
     */
    static function settled(hero:Dynamic, now:Float):Bool {
        var z = G.number(G.field(hero, "posz"));
        if (hero != settledHero) {
            settledHero = hero;
            settleUntil = now + SETTLE_TIME;
            settleZ = z; settleZAt = now;
            resetHeights();
            remembered = new Map(); rememberedCount = 0;
            return false;
        }
        if (settleUntil == 0) return true; // settled already: jumps and falls later don't count
        if (Math.abs(z - settleZ) > 0.3) { settleZ = z; settleZAt = now; } // still falling in / being placed
        if (now < settleUntil || now - settleZAt < SETTLE_STILL) return false;
        settleUntil = 0;
        DodgeLog.write(now, "hero settled in the world: auto-dodge active");
        return true;
    }

    public static function update(hero:Dynamic, now:Float):Void {
        currentHero = hero;
        DodgeLog.tick(now);
        forgetIfMoved(G.number(G.field(hero, "posx")), G.number(G.field(hero, "posy")));
        var state = enabled ? (mode == MODE_TELEPORT ? "on, teleport" : "on, dash + run") : "off";
        if (state != loggedState) { loggedState = state; DodgeLog.write(now, "auto-dodge " + state); }
        if (enabled && hero != null) try logDamage(hero, lastThreats, now) catch (_:Dynamic) {} // before the death check: a fatal hit is logged too
        if (!enabled || hero == null || G.field(hero, "removed") == true
            || G.call("ent.GameObject", "isDead", hero) == true) { stop(); return; }
        if (!settled(hero, now)) { stop(); return; } // entering the game or a new zone: hands off until the world is up
        if (userMoving()) lastUserInput = now;
        if (now - lastUserInput < USER_GRACE) { stop(); return; } // the player is steering
        if (runTarget != null && now > runUntil) stop();
        if (runTarget != null) followRun(hero, now);
        if (now - lastThink < THINK_INTERVAL) return; // the game's own frame rate doesn't matter: dangers don't need more
        lastThink = now;

        frame++;
        world = null;
        shapeChecksLeft = SHAPE_BUDGET;
        budgetOut = false;
        var threats = collect(hero, now);
        lastThreats = threats;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        think(hero, now, threats, hx, hy, hz);
        // In a fight: learn the ground around before it's needed (after planning, which reads first).
        if (threats.length > 0 || bodies.length > 0) scan(hx, hy, hz);
    }

    static var lastHealth = -1.0;
    static var lastThreats:Array<Threat> = [];
    static var healthLogged = -1.0;

    /** Diagnostics: each time the hero loses health, what was around and whether it was being dodged. */
    static function logDamage(hero:Dynamic, threats:Array<Threat>, now:Float):Void {
        var health = try G.number(G.call("ent.Unit", "get_health", hero), -1) catch (_:Dynamic) -1.0;
        if (health < 0) return;
        var max = try G.number(G.call("ent.Unit", "get_maxHealth", hero), 0) catch (_:Dynamic) 0.0;
        var threshold = max > 0 ? max * 0.005 : 0.0001;
        if (healthLogged < 0) { healthLogged = now; DodgeLog.write(now, "health readable: " + round(health) + " / " + round(max)); }
        if (lastHealth > 0 && health < lastHealth - threshold) {
            var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
            // How far each danger was from the hero, nearest first (what most likely hit).
            var scored = [for (t in threats) {t: t, d: threatDistance(t, hx, hy)}];
            scored.sort((a, b) -> a.d < b.d ? -1 : a.d > b.d ? 1 : 0);
            var near = [for (i in 0...Std.int(Math.min(6, scored.length))) kind(scored[i].t) + " " + round(scored[i].d) + " m" + (hits(hero, scored[i].t, hx, hy, hz) ? "*" : "")];
            near.push("hero at " + round(hx) + "," + round(hy));
            // Self-correction: the nearest moving hazard hit the hero from where it was thought
            // harmless - from now on it is that much bigger (for its whole kind).
            for (sc in scored) {
                if (sc.t.hazardName == null) continue;
                if (sc.d > 0 && sc.d < HAZARD_LEARN_MAX) {
                    var extra = (hazardExtra.exists(sc.t.hazardName) ? hazardExtra.get(sc.t.hazardName) : 0.0) + sc.d + 0.5;
                    hazardExtra.set(sc.t.hazardName, extra);
                    near.push("learnt: " + sc.t.hazardName + " reaches " + round(extra) + " m further");
                }
                break;
            }
            DodgeLog.write(now, "HIT -" + round(lastHealth - health) + " hp; " + (runTarget != null ? "running" : "standing")
                + "; around: " + (near.length == 0 ? "nothing seen" : near.join(",")) + " (* = catching here)");
        }
        lastHealth = health;
    }

    /** Diagnostics: distance from (x, y) to a danger (its way now for trains and movers, its
        bounding circle's edge for areas, its reach for swings). */
    static function threatDistance(t:Threat, x:Float, y:Float):Float {
        if (t.train != null) {
            var best = 1e9;
            for (p in t.train.pts) if (Math.abs(p.t) <= 0.3) best = Math.min(best, Math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)) - t.train.radius);
            return best;
        }
        if (t.swing != null) return Math.sqrt((t.swing.ownerX - x) * (t.swing.ownerX - x) + (t.swing.ownerY - y) * (t.swing.ownerY - y)) - t.swing.reach;
        if (t.line != null) {
            var a = DodgeMath.along(t.line, x, y);
            var cx = t.line.x + t.line.dx * a, cy = t.line.y + t.line.dy * a;
            return Math.sqrt((cx - x) * (cx - x) + (cy - y) * (cy - y)) - t.line.radius;
        }
        if (t.br > 0) return Math.sqrt((t.bx - x) * (t.bx - x) + (t.by - y) * (t.by - y)) - t.br;
        return Math.sqrt((t.fromX - x) * (t.fromX - x) + (t.fromY - y) * (t.fromY - y));
    }

    static function think(hero:Dynamic, now:Float, threats:Array<Threat>, hx:Float, hy:Float, hz:Float):Void {
        if (threats.length == 0) return; // nothing dangerous: a run in progress just finishes
        if (runTarget != null && now - runStarted < COMMIT) return; // keep a chosen way a moment

        // Only what would actually catch the hero where they stand matters.
        var caught = [for (t in threats) if (hits(hero, t, hx, hy, hz)) t];
        if (caught.length == 0) { reposition(hero, threats, hx, hy, hz, now); return; }
        // An attack is coming: the hero's own skills (a macro's too) wait until it's dodged,
        // instead of starting a cast that the dodge would cut a moment later.
        holdUntil = now + SKILL_HOLD;
        var timeLeft = Math.POSITIVE_INFINITY;
        for (t in caught) timeLeft = Math.min(timeLeft, t.timeLeft);
        var speed = Math.max(0.5, G.number(G.call("ent.Unit", "getMoveSpeed", hero, [null]), 5));
        if (now - lastGroundLog > GROUND_LOG_TIME) {
            lastGroundLog = now;
            var terrain = try G.number(G.call("world.World", "getZ", G.current("world.World", "inst"), [hx, hy, hz + SURFACE_TOP, null, null]), Math.NaN) catch (_:Dynamic) Math.NaN;
            DodgeLog.write(now, "ground: hero at " + round(hz) + ", surface read " + round(surfaceZ(hx, hy, hz)) + ", bare terrain " + round(terrain)
                + (physicsHeights ? "" : " (physics failed: " + physicsError + ")"));
        }
        // The bot's own cast is under way: it is let finish while there is time to spare for the walk out. A cast cut at its start never lands,
        // and a fight of cut casts deals no damage at all (the hero ran 4..9 m at every swing seen 1.4 s ahead and never struck).
        if (botDriven && runTarget == null && mode != MODE_TELEPORT && ownSkillRunning()) {
            unknownSeen = false;
            relax = 0;
            var early = plan(hero, threats, hx, hy, hz, speed, false, false);
            if (early != null && timeLeft - runTime(early.spot.exit + MARGIN, speed, false) > CAST_GRACE) {
                if (now - castKeptLogged > 1.0) { castKeptLogged = now; DodgeLog.write(now, "cast kept: the hit is " + round(timeLeft) + " s away, the walk out needs " + round(runTime(early.spot.exit + MARGIN, speed, false)) + " s"); }
                return;
            }
        }
        // The way being run is still clean: keep it - turning around mid-run is what loses the time.
        var currentHits = -1;
        var currentOpen = false;
        if (runTarget != null && mode != MODE_TELEPORT) {
            // A cast started meanwhile (a macro's, a key) holds the hero still: stop it.
            if (ownSkillRunning() && now - lastInterrupt > 0.15) interruptOwnSkill();
            var path:Array<Point2> = [{x: hx, y: hy}, runTarget];
            if (runNext != null) path.push(runNext);
            currentHits = hitsAlong(hero, threats, caught, path, hz, speed, false);
            var end = path[path.length - 1];
            ensureMap(hx, hy, hz);
            currentOpen = isOpen(end.x, end.y);
            if (currentHits == 0 && currentOpen) return; // clean and into the open: keep it
            if (now - lastBadPlan < BAD_REPLAN) return; // no clean way last time: look again a little later
            lastBadPlan = now;
        } else if (ownSkillRunning() && now - lastInterrupt > 0.15) interruptOwnSkill(); // caught while casting: the dodge comes first

        avoided = [for (a in avoided) if (a.until > now) a];
        if (now < nextSearch) return; // the last search found nothing: don't redo it every frame
        var what = [for (t in caught) kind(t)].join("+");
        for (t in caught) if (t.source != null && t.timeLeft < LATE_SHOT) reportLateShot(t.source, hero, now);
        if (mode == MODE_TELEPORT) {
            if (now - lastTeleport < TELEPORT_COOLDOWN || teleport == null) return;
            var jump = plan(hero, threats, hx, hy, hz, 1000, false, true);
            if (jump == null) { nextSearch = now + SEARCH_RETRY; return; }
            lastTeleport = now;
            stop();
            var result = teleport(hero, {x: jump.spot.target.x, y: jump.spot.target.y, z: groundZ(jump.spot.target.x, jump.spot.target.y, hz)});
            DodgeLog.write(now, "TELEPORT " + what + " -> " + result);
            return;
        }
        // Walking out cleanly first (keeps the dash); then dashing; then the way caught least.
        var dashOk = dashReady(hero);
        var allGuessed = true;
        for (t in caught) if (!t.guessed) allGuessed = false;
        if (allGuessed) dashOk = false; // the timing is only a guess: walk, keep the dash for a known hit
        // A leap or shot still to come is dodged by the dash only right as it leaves: earlier,
        // walk (the dash would be over before it even starts).
        var onlyEarlyShots = true;
        for (t in caught) if (t.shot == null || t.shot.launch <= DASH_WINDOW) onlyEarlyShots = false;
        if (onlyEarlyShots) dashOk = false;
        var chosen:Null<{spot:Spot, hits:Int}> = null;
        var dashing = false;
        unknownSeen = false;
        relax = 0;
        while (relax <= 2 && chosen == null) {
            chosen = plan(hero, threats, hx, hy, hz, speed, false, false);
            if (chosen == null && dashOk) {
                chosen = plan(hero, threats, hx, hy, hz, speed, true, false);
                dashing = chosen != null;
            }
            if (chosen == null) {
                // Nothing clean: the way caught least - dashing only if that saves a hit (the
                // dash is kept for the moment it can make a clean dodge, e.g. as a shot leaves).
                chosen = plan(hero, threats, hx, hy, hz, speed, false, true);
                dashing = false;
                if (dashOk) {
                    var dashed = plan(hero, threats, hx, hy, hz, speed, true, true);
                    if (dashed != null && (chosen == null || dashed.hits < chosen.hits)) { chosen = dashed; dashing = true; }
                }
            }
            if (chosen == null && relax == 0 && unknownSeen && unknownRetries < UNKNOWN_RETRIES && timeLeft > RETRY_TIME_LEFT) {
                unknownRetries++; // heights still being read (cached a little more each frame): try again next frame
                relax = 0;
                return;
            }
            if (chosen == null) relax++;
        }
        var relaxed = relax;
        relax = 0;
        unknownRetries = 0;
        if (chosen == null) {
            nextSearch = now + SEARCH_RETRY;
            DodgeLog.write(now, "caught by " + what + ": no way at all, even through learnt obstacles");
            return;
        }
        // The way being run is clean but ends at a wall: switch only to a clean way into the open.
        if (currentHits == 0 && !(chosen.hits == 0 && chosen.spot.open == true)) return;
        // Not clean either: switching ways every think only makes the hero zigzag on the spot.
        if (chosen.hits > 0 && currentHits >= 0 && chosen.hits >= currentHits && !dashing) return;
        if (budgetOut && now - budgetLogged > 2) { budgetLogged = now; DodgeLog.write(now, "shape checks ran out this think: the way may be poor"); }
        if (relaxed > 0) DodgeLog.write(now, relaxed == 1 ? "way found only past learnt obstacles (they may be wrong)" : "way found only ignoring heights");
        run(chosen.spot, hx, hy, now);
        if (chosen.hits > 0) runStarted = now - COMMIT; // not clean: look again next think (a timed dash may make it)
        if (dashing) dash(hero, chosen.spot.via != null ? chosen.spot.via : chosen.spot.target);
        DodgeLog.write(now, (dashing ? "DASH " : "RUN  ") + what + " timeLeft=" + round(timeLeft) + " way=" + round(chosen.spot.exit)
            + " m" + (chosen.spot.via != null ? " via a corner" : "") + (chosen.hits > 0 ? " (best possible, " + chosen.hits + " still land)" : "")
            + " open: wall " + round(openMap.clearance(chosen.spot.target.x, chosen.spot.target.y, OPEN_RANGE)) + " m, "
            + openMap.openDirections(chosen.spot.target.x, chosen.spot.target.y, OPEN_DIRECTIONS, OPEN_RANGE) + "/" + OPEN_DIRECTIONS + " free, here "
            + round(openMap.clearance(hx, hy, OPEN_RANGE)) + " m");
    }

    /**
     * In place of the game's own movement direction (UnitController.getMoveDirection, the
     * keyboard/pad input turned into a world direction): while a dodge run is going on, its
     * direction. Player input always wins and cancels the run. Null: the game's own direction.
     */
    public static function steer(controller:Dynamic, input:Dynamic):Dynamic {
        if (runTarget == null || !enabled) return null;
        if (userMoving()) { lastUserInput = haxe.Timer.stamp(); stop(); return null; }
        // A skill started while the dodge held the movement key would otherwise wait for the
        // key to be pressed anew before letting the hero move (the game's "re-input to move").
        try G.set(controller, "skillRequiresReinputToMove", false) catch (_:Dynamic) {}
        var hero = G.field(controller, "unit");
        if (hero == null) { stop(); return null; }
        var dx = runTarget.x - G.number(G.field(hero, "posx")), dy = runTarget.y - G.number(G.field(hero, "posy"));
        var distance = Math.sqrt(dx * dx + dy * dy);
        if (distance < ARRIVED) {
            if (runNext == null) { stop(); return null; }
            // First leg done: on to the safe spot.
            runFrom = {x: runTarget.x, y: runTarget.y};
            runTarget = runNext;
            runNext = null;
            stuckCheck = null;
            dx = runTarget.x - G.number(G.field(hero, "posx")); dy = runTarget.y - G.number(G.field(hero, "posy"));
            distance = Math.sqrt(dx * dx + dy * dy);
            if (distance < ARRIVED) { stop(); return null; }
        }
        return G.create("h3d.VectorImpl", [dx / distance, dy / distance, 0.0]);
    }

    static var ccLogged = -10.0;

    static function heldByControl(hero:Dynamic):Bool {
        try {
            if (G.call("ent.GameObject", "isUnderAnyCC", hero) == true) return true;
            if (G.call("ent.GameObject", "isKnocked", hero) == true) return true;
        } catch (_:Dynamic) {}
        return false;
    }

    static function ownSkillRunning():Bool {
        try {
            var skill = G.call("ent.GameObject", "getActiveSkill", currentHero);
            return skill != null && G.text(G.field(skill, "kind")) != DASH_KIND && G.call("st.skill.BaseSkill", "isRunning", skill) == true;
        } catch (_:Dynamic) return false;
    }

    /** The hero's own skill (a macro's cast, an attack) is stopped when a dodge starts: while it
        runs, the game doesn't let the hero walk. The dash is left alone. */
    static function interruptOwnSkill():Void {
        try {
            var skill = G.call("ent.GameObject", "getActiveSkill", currentHero);
            if (skill == null || G.text(G.field(skill, "kind")) == DASH_KIND) return;
            if (G.call("st.skill.BaseSkill", "isRunning", skill) != true) return;
            var stopped = G.call("st.skill.Skill", "requestInterrupt", skill) == true;
            lastInterrupt = haxe.Timer.stamp();
            DodgeLog.write(haxe.Timer.stamp(), "own skill " + G.text(G.field(skill, "kind")) + (stopped ? " interrupted" : " can't be interrupted"));
        } catch (_:Dynamic) {}
    }

    /** True while a dodge run is going on: the run holds the movement input, and the hero's
        own skills and attacks wait (the dodge comes first). */
    public static function dodging():Bool return enabled && runTarget != null;

    /** True while the hero's own skills and attacks must wait: a dodge runs, or an attack is
        coming at the hero (a cast started now would only be cut by the dodge). */
    public static function holdingSkills():Bool return enabled && (runTarget != null || haxe.Timer.stamp() < holdUntil);

    /** The player's own movement keys (read directly: the game's movement input is the dodge's while it runs). */
    static function userMoving():Bool {
        for (name in MOVE_INPUTS)
            try if (G.staticCall("lib.Input", "isDown", [name]) == true) return true catch (_:Dynamic) {}
        return false;
    }

    static function stop():Void {
        runTarget = null;
        runNext = null;
        runFrom = null;
        runJumpAt = -1;
        stuckCheck = null;
    }

    static var runStarted = -10.0;

    static function run(spot:Spot, hx:Float, hy:Float, now:Float):Void {
        if (runTarget == null) interruptOwnSkill();
        runStarted = now;
        holdUntil = now + SKILL_HOLD;
        var first = spot.via != null ? spot.via : spot.target;
        lastRunAngle = Math.atan2(first.y - hy, first.x - hx);
        lastRunAt = now;
        runTarget = spot.via != null ? spot.via : spot.target;
        runNext = spot.via != null ? spot.target : null;
        runFrom = {x: hx, y: hy};
        runJumpAt = spot.jumpAt;
        runUntil = now + RUN_TIMEOUT;
        stuckCheck = {x: hx, y: hy, t: now};
    }

    /** During a run: jump over the low obstacle on the way, and give up a way that turned out blocked. */
    static function followRun(hero:Dynamic, now:Float):Void {
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        if (runJumpAt >= 0 && runFrom != null) {
            var travelled = Math.sqrt((hx - runFrom.x) * (hx - runFrom.x) + (hy - runFrom.y) * (hy - runFrom.y));
            if (travelled >= runJumpAt - JUMP_AHEAD) {
                runJumpAt = -1;
                try {
                    var controller = G.current("client.PlayerController", "inst");
                    var time = G.call("client.UnitController", "get_time", controller);
                    G.set(controller, "requestJumpTime", G.number(G.field(time, "serverNow")));
                    DodgeLog.write(now, "JUMP over an obstacle");
                } catch (_:Dynamic) {}
            }
        }
        if (stuckCheck != null && now - lastInterrupt < INTERRUPT_GRACE) stuckCheck = {x: hx, y: hy, t: now};
        if (stuckCheck != null && now - stuckCheck.t >= STUCK_TIME && heldByControl(hero)) {
            stuckCheck = {x: hx, y: hy, t: now}; // stunned, rooted or knocked about: no wall to learn
            if (now - ccLogged > 2) { ccLogged = now; DodgeLog.write(now, "hero under crowd control: not moving, no obstacle learnt"); }
        }
        if (stuckCheck != null && now - stuckCheck.t >= STUCK_TIME) {
            var moved = Math.sqrt((hx - stuckCheck.x) * (hx - stuckCheck.x) + (hy - stuckCheck.y) * (hy - stuckCheck.y));
            var speed = G.number(G.call("ent.Unit", "getMoveSpeed", hero, [null]), 5);
            var expected = speed * (now - stuckCheck.t);
            if (moved < expected * STUCK_SHARE && runTarget != null && ownSkillRunning()) {
                // Held by the hero's own cast (a macro's), not by a wall: stop the cast, keep the way.
                interruptOwnSkill();
                stuckCheck = {x: hx, y: hy, t: now};
                return;
            }
            if (moved < expected * STUCK_SHARE && runTarget != null) {
                var angle = Math.atan2(runTarget.y - hy, runTarget.x - hx);
                // Stopped by a monster's body: that's not a wall to remember.
                if (!bodyAhead(hx, hy, angle)) remember(hx, hy, angle);
                avoided.push({angle: angle, until: now + AVOID_TIME});
                DodgeLog.write(now, "STUCK: remembered the obstacle, trying another way (" + rememberedCount + " cells known)");
                stop();
                nextSearch = 0;
                return;
            }
            stuckCheck = {x: hx, y: hy, t: now};
        }
    }

    static function jumpNote(jumpAt:Float):String return jumpAt >= 0 ? " (jump at " + round(jumpAt) + " m)" : "";

    // ---- what is dangerous -------------------------------------------------------------

    static var shotsResetAt = 0.0;

    static function collect(hero:Dynamic, now:Float):Array<Threat> {
        var threats:Array<Threat> = [];
        if (now - shotsResetAt > 60) { shotsResetAt = now; shotsForeseen = new haxe.ds.ObjectMap(); meleeTimed = new haxe.ds.ObjectMap(); } // don't keep dead archers
        var layer = G.field(hero, "layer");
        var alive = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>();
        for (area in G.fastArray(G.field(layer, "areas"))) {
            try {
                var threat = areaThreat(hero, area, now, alive);
                if (threat != null) threats.push(threat);
            } catch (_:Dynamic) {}
        }
        seen = alive;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        var unitsAlive = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, speed:Float}>();
        bodies = [];
        for (unit in G.fastArray(G.field(layer, "units"))) {
            try {
                if (unit == null || unit == hero || G.field(unit, "removed") == true || !hostile(unit)) continue;
                var px = G.number(G.field(unit, "posx")), py = G.number(G.field(unit, "posy"));
                var ux = px - hx, uy = py - hy;
                var d2 = ux * ux + uy * uy;
                if (d2 > SHOT_REACH * SHOT_REACH) continue;
                var far = d2 > SWING_REACH * SWING_REACH; // too far to swing, not too far to shoot
                if (G.call("ent.GameObject", "isDead", unit) == true) continue;
                // The monster's own speed right now (it may keep closing in while winding up).
                var speed = 0.0;
                var before = unitsSeen.get(unit);
                if (before != null && now > before.t) {
                    var dt = now - before.t;
                    speed = dt < 0.05 ? before.speed : Math.sqrt((px - before.x) * (px - before.x) + (py - before.y) * (py - before.y)) / dt;
                }
                unitsAlive.set(unit, {x: px, y: py, t: now, speed: speed});
                if (!far) bodies.push({x: px, y: py, r: bodyRadius(unit)});
                var own = swingThreats(hero, unit, speed, far);
                for (threat in own) threats.push(threat);
            } catch (_:Dynamic) {}
        }
        unitsSeen = unitsAlive;
        var trainsSeen = new haxe.ds.ObjectMap<Dynamic, Bool>();
        var moversAlive = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>();
        for (object in G.fastArray(G.field(layer, "gameObjects"))) {
            try {
                if (object == null || object == hero) continue;
                var kind = objectKind(object);
                if (kind == KIND_IGNORE) continue;
                if (kind == KIND_TRAIN && !trainsSeen.exists(object)) {
                    trainsSeen.set(object, true);
                    var threat = trainThreat(hero, object);
                    if (threat != null) threats.push(threat);
                }
                // Carts, blades, rolling things - anything moving that hurts by running into the hero.
                var threat = moverThreat(hero, object, now, moversAlive);
                if (threat != null) threats.push(threat);
            } catch (_:Dynamic) {}
        }
        for (k in projectilesMoving.keys()) moversAlive.set(k, projectilesMoving.get(k));
        moversSeen = moversAlive;
        projectilesMoving = new haxe.ds.ObjectMap();
        for (entity in G.fastArray(G.field(layer, "entities"))) {
            try {
                if (entity == null) continue;
                if (isTrain(entity)) {
                    if (trainsSeen.exists(entity)) continue;
                    trainsSeen.set(entity, true);
                    var threat = trainThreat(hero, entity);
                    if (threat != null) threats.push(threat);
                    continue;
                }
                if (!isProjectile(entity)) continue;
                var threat = projectileThreat(hero, entity);
                if (threat != null) threats.push(threat);
            } catch (_:Dynamic) {}
        }
        return threats;
    }

    /** Not a player's (nor a player's summon's): monsters, traps and the environment are hostile. */
    static function hostile(source:Dynamic):Bool {
        var current = source;
        var guard = 0;
        while (current != null && guard++ < 8) {
            if (friendly(current)) return false;
            current = G.field(current, "summonOwner");
        }
        return true;
    }

    /** A player, or anything a player owns (summons, skill objects, the areas and projectiles
        of their skills): the game marks all of them with ownerPlayer. */
    static function friendly(object:Dynamic):Bool {
        if (object == null) return false;
        if (isA(object, "ent.Hero")) return true;
        return try G.field(object, "ownerPlayer") != null catch (_:Dynamic) false;
    }

    /** What an area is attached to, the same way SkillArea.update picks it (areaProps.follow). */
    static function followed(area:Dynamic):Dynamic {
        var follow:Dynamic = G.field(G.call("st.skill.SkillArea", "get_areaProps", area), "follow");
        if (follow == null) return null;
        return switch G.integer(follow, -1) {
            case AREA_FOLLOW_TARGET: G.field(area, "target");
            case AREA_FOLLOW_OWNER: G.field(G.field(area, "baseSkill"), "owner");
            default: null;
        };
    }

    static function areaThreat(hero:Dynamic, area:Dynamic, now:Float, alive:haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>):Null<Threat> {
        if (area == null || G.field(area, "removed") == true) return null;
        var skill = G.field(area, "baseSkill");
        if (friendly(area) || friendly(skill) || !hostile(G.call("st.skill.SkillArea", "get_owner", area))) return null;
        try if (friendly(G.call("st.skill.BaseSkill", "getSourceObject", skill))) return null catch (_:Dynamic) {}
        var expected = G.integer(G.field(area, "expectedTicks"));
        if (expected > 0 && G.integer(G.field(area, "currentTick")) >= expected) return null; // done hitting
        var attached = followed(area);
        if (attached == hero) return null; // still lining up on the hero: wait until it stays put
        var step = G.call("st.skill.SkillArea", "get_step", area);
        if (step == null) return null;

        var position = G.field(area, "position");
        var x = G.number(G.field(position, "x")), y = G.number(G.field(position, "y")), z = G.number(G.field(position, "z"));
        // Speed of a moving area (carts, blades, anything attached to something that moves).
        var vx = 0.0, vy = 0.0;
        var before = seen.get(area);
        if (before != null && now > before.t) {
            var dt = now - before.t;
            vx = (x - before.x) / dt; vy = (y - before.y) / dt;
            if (dt < 0.05) { vx = before.vx; vy = before.vy; } // same frame twice: keep the last estimate
        }
        alive.set(area, {x: x, y: y, t: now, vx: vx, vy: vy});

        var rotation = G.number(G.field(area, "rotationZ"));
        var range = G.number(G.call("st.skill.SkillArea", "getRange", area));
        var threat = new Threat();
        threat.fromX = x; threat.fromY = y;
        var moving = vx * vx + vy * vy > 0.01;
        var samples = moving ? 5 : 1;
        for (i in 0...samples) {
            var t = moving ? PREDICT * i / (samples - 1) : 0.0;
            var at = G.create("h3d.VectorImpl", [x + vx * t, y + vy * t, z]);
            var shape = G.call("st.skill.AreaStep", "getCollisionShape", step, [at, rotation, range]);
            if (shape != null) threat.shapes.push(shape);
        }
        if (threat.shapes.length == 0) return null;
        learnAreaTiming(area);
        try {
            var r = shapeReach(threat.shapes[0], range);
            if (r > 0) {
                var drift = moving ? Math.sqrt(vx * vx + vy * vy) * PREDICT / 2 : 0.0;
                threat.bx = x + (moving ? vx * PREDICT / 2 : 0.0);
                threat.by = y + (moving ? vy * PREDICT / 2 : 0.0);
                threat.br = r + drift;
            }
        } catch (_:Dynamic) {}

        if (G.number(G.field(area, "startTime"), -1) >= 0) {
            threat.lasting = true; // already hitting (ground effect, moving hazard): get out
            threat.timeLeft = Math.max(0, G.number(G.field(area, "tickInterval"), 0));
        } else if (G.number(G.field(area, "triggerTime"), -1) >= 0) {
            // Triggered: it lands once its travel time (a falling meteor, a wave) has passed.
            threat.timeLeft = 0.1;
            try {
                var travel = G.number(G.field(G.call("st.skill.SkillArea", "get_areaProps", area), "travelTime"), 0);
                var serverNow = G.number(G.field(G.call("st.State", "get_time", area), "serverNow"), -1);
                if (travel > 0 && serverNow >= 0)
                    threat.timeLeft = Math.max(0.05, G.number(G.field(area, "triggerTime")) + travel - serverNow);
            } catch (_:Dynamic) {}
        } else {
            // Still telegraphed: it lands when the monster's cast ends - or, with no cast, after
            // the delay this kind of area was seen to take before.
            var skill = G.field(area, "baseSkill");
            var casting = try G.call("st.skill.Skill", "isCasting", skill) == true catch (_:Dynamic) false;
            threat.timeLeft = casting ? G.number(G.call("st.skill.Skill", "getCastTimeLeft", skill), UNKNOWN_DELAY) : UNKNOWN_DELAY;
            threat.guessed = !casting;
            if (!casting) try {
                var learnt = areaTiming.get(areaKey(area, skill));
                var serverNow = G.number(G.field(G.call("st.State", "get_time", area), "serverNow"), -1);
                var created = G.number(G.field(area, "createTime"), -1);
                if (learnt != null && serverNow >= 0 && created >= 0) { threat.timeLeft = Math.max(0.05, created + learnt - serverNow); threat.guessed = false; }
            } catch (_:Dynamic) {}
        }
        if (moving) threat.lasting = true;
        return threat;
    }

    /** The area swings of a monster's running skill that haven't landed yet. */
    static var fastAttackers = new Map<String, Float>();

    static var meleeTiming = new Map<String, Float>();
    static var meleeReported = new Map<String, Bool>();
    static var lungeTiming = new Map<String, Float>();
    static var lungeTimed = new haxe.ds.ObjectMap<Dynamic, Bool>();
    static var meleeTimed = new haxe.ds.ObjectMap<Dynamic, Bool>();

    static function learnMeleeTiming(kind:String, elapsed:Float):Void {
        if (elapsed < 0.05 || elapsed > 4) return;
        var before = meleeTiming.get(kind);
        if (before != null && Math.abs(before - elapsed) < 0.02) return;
        var learnt = before == null ? elapsed : before * 0.7 + elapsed * 0.3;
        if (before == null) DodgeLog.write(haxe.Timer.stamp(), "melee timing learnt: " + kind + " hits " + round(learnt) + " s into the skill");
        meleeTiming.set(kind, learnt);
    }

    static function unitKind(unit:Dynamic):String {
        var id = try G.text(G.field(G.field(unit, "inf"), "id")) catch (_:Dynamic) "";
        return id != "" ? id : hl.Type.getDynamic(unit).getTypeName();
    }

    static function targetsHero(unit:Dynamic, hero:Dynamic):Bool
        return try G.call("ent.Unit", "get_targetUnit", unit) == hero catch (_:Dynamic) false;

    static function swingThreats(hero:Dynamic, unit:Dynamic, speed:Float, far = false):Array<Threat> {
        var out:Array<Threat> = [];
        var skill = G.call("ent.GameObject", "getActiveSkill", unit);
        if (skill == null || G.call("st.skill.BaseSkill", "isRunning", skill) != true) return out;
        var elapsed = G.number(G.call("st.skill.BaseSkill", "getElapsedTime", skill), 0);
        var casting = try G.call("st.skill.Skill", "isCasting", skill) == true catch (_:Dynamic) false;
        var castLeft = casting ? G.number(G.call("st.skill.Skill", "getCastTimeLeft", skill), -1) : -1;
        var ox = G.number(G.field(unit, "posx")), oy = G.number(G.field(unit, "posy"));
        var steps = G.fastArray(G.field(skill, "steps"));
        var canMove = try G.call("st.skill.BaseSkill", "canMove", skill) == true catch (_:Dynamic) false;
        // How far the skill itself still moves the monster (lunges, gap closers, jumps, blinks).
        var lunge = 0.0;
        for (step in steps) {
            try {
                if (step == null || G.call("st.skill.SkillStep", "hasStarted", step) == true || G.field(step, "cancelled") == true) continue;
                var type = G.integer(G.field(G.field(step, "inf"), "type"), -1);
                if (type == STEP_DASH || type == STEP_GAP_CLOSE || type == STEP_TELEPORT || type == STEP_JUMP)
                    lunge += Math.max(0, G.number(G.call("st.skill.SkillStep", "getRange", step), 0));
            } catch (_:Dynamic) {}
        }
        var hxNow = G.number(G.field(hero, "posx")), hyNow = G.number(G.field(hero, "posy"));
        var aimedAtHero = try G.call("ent.Unit", "get_targetUnit", unit) == hero catch (_:Dynamic) false;
        if (!aimedAtHero) {
            // No target set (or not readable): an archer facing the hero is aiming at them.
            var target:Dynamic = try G.call("ent.Unit", "get_targetUnit", unit) catch (_:Dynamic) null;
            if (target == null) {
                var toHero = Math.atan2(G.number(G.field(hero, "posy")) - oy, G.number(G.field(hero, "posx")) - ox);
                aimedAtHero = Math.abs(DodgeMath.angleDiff(toHero, G.number(G.field(unit, "rotationZ")))) < FACING_AIM;
            }
        }
        for (step in steps) {
            try {
                if (step == null || !aimedAtHero) continue;
                if (G.integer(G.field(G.field(step, "inf"), "type"), -1) != STEP_PROJECTILE) continue;
                if (G.call("st.skill.SkillStep", "hasStarted", step) == true || G.field(step, "cancelled") == true) continue;
                var shot = G.field(G.field(G.field(step, "inf"), "props"), "projectile");
                if (G.number(G.field(shot, "followTime"), 0) > 0) continue;   // homing: can't be dodged
                var delay:Dynamic = G.field(G.field(step, "inf"), "delay");
                var learnt = shotTiming.get(G.text(G.field(skill, "kind")));
                var untilShot = delay != null ? G.number(delay) - elapsed
                    : learnt != null ? learnt - elapsed
                    : castLeft >= 0 ? castLeft : runningStepLeft(steps);
                if (untilShot < -0.1 || untilShot > SHOT_NOTICE) continue;    // gone already, or not yet worth moving for
                var shotSpeed = G.number(G.field(shot, "speed"), 25);
                if (shotSpeed <= 0) shotSpeed = 25;
                var dx = hxNow - ox, dy = hyNow - oy;
                var d = Math.sqrt(dx * dx + dy * dy);
                if (d < 0.5) continue;
                var radius = G.number(G.field(shot, "collisionRadius"), 0.5);
                var threat = new Threat();
                threat.shot = {ox: ox, oy: oy, launch: Math.max(0, untilShot), speed: shotSpeed, radius: radius, range: d + 8};
                threat.line = {x: ox, y: oy, dx: dx / d, dy: dy / d, length: d + 4, radius: radius}; // where it goes if the hero stays
                threat.projectile = true;
                threat.timeLeft = Math.max(0, untilShot) + d / shotSpeed;
                shotsForeseen.set(unit, haxe.Timer.stamp());
                var side = DodgeMath.sideSource(threat.line, hxNow, hyNow);
                threat.fromX = side.x; threat.fromY = side.y;
                out.push(threat);
            } catch (_:Dynamic) {}
        }
        if (far) return out; // only its shots can reach the hero from there
        for (step in steps) {
            try {
                if (step == null || !isA(step, "st.skill.AreaStep")) continue;
                if (G.field(step, "isInstantiated") == true) continue; // placed in the world: handled as an area
                if (G.call("st.skill.SkillStep", "hasStarted", step) == true || G.field(step, "cancelled") == true) continue;
                var origin:Dynamic = G.field(G.field(G.field(G.field(step, "inf"), "props"), "position"), "origin");
                var o = origin == null ? ORIGIN_OWNER : G.integer(origin, ORIGIN_OWNER);
                if (o == ORIGIN_TARGET || o == ORIGIN_INSTIGATOR || o == ORIGIN_PROJECTILE || o == ORIGIN_AREA) continue; // follows the hero
                // No target given: the position is the monster's own, or the aimed point.
                var pos = G.field(G.call("st.skill.SkillStep", "getTargetingInfo", step, [null, null]), "pos");
                if (pos == null) continue;
                var px = G.number(G.field(pos, "x")), py = G.number(G.field(pos, "y")), pz = G.number(G.field(pos, "z"));
                var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
                if ((px - hx) * (px - hx) + (py - hy) * (py - hy) < 1.0 && (px - ox) * (px - ox) + (py - oy) * (py - oy) >= 1.0) continue; // aimed at the hero: follows them
                var threat = new Threat();
                var fromOwner = (px - ox) * (px - ox) + (py - oy) * (py - oy) < 1.0;
                var delay:Dynamic = G.field(G.field(step, "inf"), "delay");
                if (delay != null && elapsed > G.number(delay) + 0.25) continue; // landed already (start not seen here)
                threat.timeLeft = delay != null ? Math.max(0.05, G.number(delay) - elapsed)
                    : castLeft >= 0 ? castLeft : UNKNOWN_DELAY;
                if (fromOwner && lunge > MAX_LUNGE) continue; // it leaps onto the hero: no distance is enough
                // It closes in by its own lunges; by walking only if this skill lets it move meanwhile.
                var walkSpeed = canMove ? speed : 0.0;
                var advance = fromOwner ? DodgeMath.advance(lunge, walkSpeed, MOVING, threat.timeLeft, MAX_WALK_ADVANCE, MAX_ADVANCE) : 0.0;
                var range = G.number(G.call("st.skill.SkillStep", "getRange", step), 0);
                var rotation = G.number(G.field(unit, "rotationZ"));
                // How far the swing reaches from where it's cast, whichever way it faces.
                var reach = range;
                try {
                    var shape = G.call("st.skill.AreaStep", "getCollisionShape", step, [G.create("h3d.VectorImpl", [px, py, pz]), rotation, range]);
                    var r = shapeReach(shape, range);
                    if (r > 0) reach = r;
                } catch (_:Dynamic) {}
                threat.swing = {step: step, x: px, y: py, z: pz, range: range,
                    rotation: rotation, ownerX: ox, ownerY: oy, turns: fromOwner, advance: advance, reach: reach};
                if (!fromOwner) { threat.bx = px; threat.by = py; threat.br = reach; }
                threat.fromX = ox; threat.fromY = oy;
                out.push(threat);
            } catch (_:Dynamic) {}
        }
        // An attack with no area or projectile of its own (a dog's bite, a claw, a direct hit on
        // its target): it lands only if the hero is still within the monster's reach then -
        // so out of reach it goes, like any swing that turns with the monster.
        if (out.length == 0 && aimedAtHero && elapsed < MELEE_LONGEST) {
            try {
                // The hit is the damaging step (its area), at the end of a lunge - not the lunge
                // itself, which starts at once: time it by the area step, else by the last step.
                var reach = 0.0, hitReach = 0.0, hitAt = -1.0, lastAt = -1.0;
                var pending:Dynamic = null;
                var skillKind = G.text(G.field(skill, "kind"));
                var hitStarted = false, lungeStarted = false;
                for (step in steps) {
                    if (step == null || G.field(step, "cancelled") == true) continue;
                    if (isA(step, "st.skill.AreaStep") && G.call("st.skill.SkillStep", "hasStarted", step) == true) hitStarted = true;
                    var stepType = G.integer(G.field(G.field(step, "inf"), "type"), -1);
                    if ((stepType == STEP_DASH || stepType == STEP_GAP_CLOSE || stepType == STEP_JUMP)
                        && G.call("st.skill.SkillStep", "hasStarted", step) == true) lungeStarted = true;
                    var r = G.number(G.call("st.skill.SkillStep", "getRange", step), 0);
                    var type = G.integer(G.field(G.field(step, "inf"), "type"), -1);
                    var moves = type == STEP_DASH || type == STEP_GAP_CLOSE || type == STEP_TELEPORT || type == STEP_JUMP;
                    if (!moves) reach = Math.max(reach, r); // a lunge's range is how far it moves, counted in the advance
                    if (isA(step, "st.skill.AreaStep")) hitReach = Math.max(hitReach, r);
                    if (pending == null) pending = step;
                    if (G.call("st.skill.SkillStep", "hasStarted", step) == true) continue;
                    var delay:Dynamic = G.field(G.field(step, "inf"), "delay");
                    if (delay == null) continue;
                    var t = G.number(delay) - elapsed;
                    if (t <= -0.05) continue;
                    lastAt = Math.max(lastAt, t);
                    if (isA(step, "st.skill.AreaStep") && (hitAt < 0 || t < hitAt)) hitAt = t;
                }
                var when = hitAt >= 0 ? hitAt : lastAt;
                if (hitReach > 0) reach = hitReach;
                // No timing in the data: learn it - the moment its damaging step starts, seconds
                // into the skill - and from then on dodge it from the moment it is being prepared.
                if (hitStarted && !meleeTimed.exists(skill)) { meleeTimed.set(skill, true); learnMeleeTiming(skillKind, elapsed); }
                if (lungeStarted && !lungeTimed.exists(skill)) {
                    lungeTimed.set(skill, true);
                    if (elapsed > 0.02 && elapsed < 4 && !lungeTiming.exists(skillKind)) {
                        lungeTiming.set(skillKind, elapsed);
                        DodgeLog.write(haxe.Timer.stamp(), "lunge timing learnt: " + skillKind + " leaps " + round(elapsed) + " s into the skill");
                    }
                }
                if (!lungeStarted && elapsed < 0.2) lungeTimed.remove(skill);
                if (!hitStarted && elapsed < 0.2) meleeTimed.remove(skill); // a new cast of the same skill: time it again
                var learnt = meleeTiming.get(skillKind);
                if (when < 0 && castLeft < 0 && learnt != null) {
                    if (hitStarted || elapsed > learnt + 0.15) when = -2; // landed already
                    else when = Math.max(0.05, learnt - elapsed);
                }
                if (when == -2) pending = null;
                if (pending != null) {
                    if (reach <= 0) reach = MELEE_DEFAULT;
                    if (reach <= MELEE_MAX) {
                        var threat = new Threat();
                        // A bite or claw comes quickly: with nothing to time it by, assume it is close.
                        threat.timeLeft = when >= 0 ? Math.max(0.05, when) : castLeft >= 0 ? castLeft : MELEE_WINDUP;
                        var walkSpeed = speed; // leaps and charges move the monster even when the skill doesn't say so
                        var advance = DodgeMath.advance(lunge, walkSpeed, MOVING, threat.timeLeft, MAX_WALK_ADVANCE, MAX_ADVANCE);
                        reach += bodyRadius(unit);
                        if (lunge > 0 && when >= 0 && !lungeStarted) {
                            var hit = threat.timeLeft;
                            var leapAt = lungeTiming.get(skillKind);
                            // The leap starts when learnt (often together with the bite), else a moment before the bite.
                            var launch = leapAt != null ? Math.max(0, leapAt - elapsed) : Math.max(0, hit - LUNGE_TIME);
                            hit = Math.max(hit, launch + LUNGE_TIME); // the leap still flies after it starts
                            var bite = Math.min(reach, BITE_REACH) ;
                            var hx0 = G.number(G.field(hero, "posx")), hy0 = G.number(G.field(hero, "posy"));
                            var dx = hx0 - ox, dy = hy0 - oy, d = Math.max(0.5, Math.sqrt(dx * dx + dy * dy));
                            // First choice, like a player does it: be out of the leap's reach (its length + the
                            // bite) before it leaps, by walking away - when there is time for that.
                            // Its reach: the leap + the bite + a margin, plus what it still walks while winding up;
                            // the hero must be beyond that until the bite is over, not just when it leaps.
                            var outOfReach = lunge + bite + bodyRadius(unit) + LUNGE_SAFETY;
                            var approach = Math.min(MAX_WALK_ADVANCE, speed * launch);
                            var heroSpeed = Math.max(0.5, G.number(G.call("ent.Unit", "getMoveSpeed", hero, [null]), 5));
                            if (outOfReach + approach - d + MARGIN <= heroSpeed * Math.max(0, hit - REACTION) * 0.9) {
                                threat.timeLeft = Math.max(0.05, hit + HIT_LATE);
                                threat.swing = {step: pending, x: ox, y: oy, z: G.number(G.field(unit, "posz")), range: outOfReach,
                                    rotation: G.number(G.field(unit, "rotationZ")), ownerX: ox, ownerY: oy, turns: true, advance: approach, reach: outOfReach};
                                threat.melee = true;
                                threat.timed = true;
                                threat.fromX = ox; threat.fromY = oy;
                                out.push(threat);
                                return out;
                            }
                            // No time to get that far: step off its line as it leaps (the dash, at that moment, if needed).
                            var leap = new Threat();
                            leap.timeLeft = hit;
                            leap.shot = {ox: ox, oy: oy, launch: launch, speed: Math.max(4, lunge / Math.max(0.15, hit - launch)), radius: bite, range: lunge + bite};
                            leap.line = {x: ox, y: oy, dx: dx / d, dy: dy / d, length: lunge + bite, radius: bite};
                            leap.melee = true;
                            var side = DodgeMath.sideSource(leap.line, hx0, hy0);
                            leap.fromX = side.x; leap.fromY = side.y;
                            out.push(leap);
                            if (!meleeReported.exists(skillKind + "/leap")) {
                                meleeReported.set(skillKind + "/leap", true);
                                DodgeLog.write(haxe.Timer.stamp(), "lunge attack: " + skillKind + " leaps " + round(lunge) + " m in " + round(launch) + " s, bites " + round(hit) + " s (bite " + round(bite) + " m): dodged sideways off its line");
                            }
                            return out;
                        }
                        threat.swing = {step: pending, x: ox, y: oy, z: G.number(G.field(unit, "posz")), range: reach,
                            rotation: G.number(G.field(unit, "rotationZ")), ownerX: ox, ownerY: oy, turns: true, advance: advance, reach: reach};
                        threat.melee = true;
                        threat.timed = when >= 0 || castLeft >= 0;
                        if (!meleeReported.exists(skillKind)) {
                            meleeReported.set(skillKind, true);
                            DodgeLog.write(haxe.Timer.stamp(), "melee seen: " + skillKind + " reach " + round(reach) + " m, lunge " + round(lunge)
                                + " m, hit in " + round(threat.timeLeft) + " s (" + (when >= 0 ? "from data/learnt" : castLeft >= 0 ? "cast" : "default") + "), "
                                + round(elapsed) + " s into the skill");
                        }
                        threat.fromX = ox; threat.fromY = oy;
                        out.push(threat);
                    }
                }
            } catch (_:Dynamic) {}
        }
        return out;
    }

    // When each archer skill lets its shot go (seconds into the skill), learnt from the shots
    // themselves: some bows give no delay of their own and aren't "casting" while they aim.
    static var shotTiming = new Map<String, Float>();
    static var shotsTimed = new haxe.ds.ObjectMap<Dynamic, Bool>();
    static var shotsTimedAt = 0.0;

    static function learnShotTiming(projectile:Dynamic, speed:Float):Void {
        try {
            if (shotsTimed.exists(projectile)) return;
            var now = haxe.Timer.stamp();
            if (now - shotsTimedAt > 30) { shotsTimedAt = now; shotsTimed = new haxe.ds.ObjectMap(); }
            shotsTimed.set(projectile, true);
            if (G.field(projectile, "launched") != true) return;
            var skill = G.field(projectile, "baseSkill");
            if (skill == null || G.call("st.skill.BaseSkill", "isRunning", skill) != true) return;
            var kind = G.text(G.field(skill, "kind"));
            var flown = Math.max(0, G.number(G.field(projectile, "rangeCrossed"), 0)) / speed;
            var at = G.number(G.call("st.skill.BaseSkill", "getElapsedTime", skill), -1) - flown;
            if (at < 0.05 || at > 6) return;
            var before = shotTiming.get(kind);
            var learnt = before == null ? at : before * 0.7 + at * 0.3;
            if (before == null || Math.abs(learnt - before) > 0.05)
                DodgeLog.write(now, "shot timing learnt: " + kind + " lets go " + round(learnt) + " s into the skill");
            shotTiming.set(kind, learnt);
        } catch (_:Dynamic) {}
    }

    /** Time left of the step running now (a shot without a delay of its own follows it); -1: none. */
    static function runningStepLeft(steps:Array<Dynamic>):Float {
        var left = -1.0;
        for (step in steps) {
            try {
                if (G.call("st.skill.SkillStep", "hasStarted", step) != true) continue;
                var d = G.number(G.call("st.skill.SkillStep", "getDurationLeft", step), -1);
                if (d > 0 && (left < 0 || d < left)) left = d;
            } catch (_:Dynamic) {}
        }
        return left;
    }

    /** How far a hit shape reaches from the point it is cast at. The game's own max radius is
        measured from the shape's centre - for a rectangle that is half its range ahead of the
        cast point - so a rectangle reaches half its range further. -1: unknown. */
    static function shapeReach(shape:Dynamic, range:Float):Float {
        var r = G.number(G.staticCall("HCollision", "getMaxRadius", [shape]), -1);
        if (r <= 0) return -1;
        var name = try Type.enumConstructor(shape) catch (_:Dynamic) "";
        return name == "HBBox" ? r + Math.max(0, range) * 0.5 : name == "OBBox" ? r + Math.max(0, range) : r;
    }

    // How long after it appears each kind of area goes off (server seconds), learnt from the
    // areas themselves: most telegraphs have no cast to read their timing from.
    static var areaTiming = new Map<String, Float>();
    static var areasWaiting = new haxe.ds.ObjectMap<Dynamic, Bool>();
    static var areasWaitingAt = 0.0;

    static function areaKey(area:Dynamic, skill:Dynamic):String {
        var step = try G.call("st.skill.SkillArea", "get_step", area) catch (_:Dynamic) null;
        return G.text(G.field(skill, "kind")) + ":" + (step == null ? "" : G.text(G.field(G.field(step, "inf"), "id")));
    }

    static function learnAreaTiming(area:Dynamic):Void {
        try {
            var now = haxe.Timer.stamp();
            if (now - areasWaitingAt > 30) { areasWaitingAt = now; areasWaiting = new haxe.ds.ObjectMap(); }
            var went = G.number(G.field(area, "triggerTime"), -1);
            if (went < 0) went = G.number(G.field(area, "startTime"), -1);
            if (went < 0) { areasWaiting.set(area, true); return; } // seen before it went off: time it
            if (!areasWaiting.exists(area)) return;
            areasWaiting.remove(area);
            var created = G.number(G.field(area, "createTime"), -1);
            if (created < 0 || went - created <= 0.05 || went - created > 6) return;
            var key = areaKey(area, G.field(area, "baseSkill"));
            var before = areaTiming.get(key);
            var learnt = before == null ? went - created : Math.min(went - created, before * 0.7 + (went - created) * 0.3);
            if (before == null) DodgeLog.write(now, "area timing learnt: " + key + " goes off " + round(learnt) + " s after it appears");
            areaTiming.set(key, learnt);
        } catch (_:Dynamic) {}
    }

    static function projectileThreat(hero:Dynamic, projectile:Dynamic):Null<Threat> {
        if (G.field(projectile, "removed") == true || G.field(projectile, "isAlive") == false) return null;
        if (G.field(projectile, "appeared") != true && G.field(projectile, "launched") != true) return null;
        if (friendly(projectile) || friendly(G.field(projectile, "baseSkill"))
            || !hostile(G.field(G.field(projectile, "baseSkill"), "owner"))) return null;
        var aim = enumName(G.field(projectile, "targettingMode"));
        if (aim != "EForward" && aim != "EDirection" && aim != "EPoint" && aim != "EBoomerang") // orbiting, hovering, homing: by how it moves
            return moverThreat(hero, projectile, haxe.Timer.stamp(), projectilesMoving);
        var direction = G.call("ent.Projectile", "get_direction", projectile);
        var dx = G.number(G.field(direction, "x")), dy = G.number(G.field(direction, "y"));
        var length2d = Math.sqrt(dx * dx + dy * dy);
        if (length2d < 0.01) return null;
        dx /= length2d; dy /= length2d;
        var info = G.field(projectile, "info");
        var speed = G.number(G.field(G.field(info, "step"), "speed"), 0);
        if (speed <= 0) speed = G.number(G.field(G.field(projectile, "inf"), "baseSpeed"), 0);
        if (speed <= 0) return null;
        var radius = G.number(G.field(G.field(G.field(projectile, "inf"), "collision"), "radius"), 0.5);
        var remaining = G.number(G.field(projectile, "maxRange"), 0) - G.number(G.field(projectile, "rangeCrossed"), 0);
        if (remaining <= 0) remaining = 30;
        var px = G.number(G.field(projectile, "posx")), py = G.number(G.field(projectile, "posy"));
        var threat = new Threat();
        threat.line = {x: px, y: py, dx: dx, dy: dy, length: remaining, radius: radius};
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        // Run away from its path - sideways - not from the projectile itself (along its path).
        var side = DodgeMath.sideSource(threat.line, hx, hy);
        threat.fromX = side.x; threat.fromY = side.y;
        threat.projectile = true;
        var wait = G.field(projectile, "launched") == true ? 0.0 : Math.max(0, G.number(G.field(projectile, "activationDelay"), 0));
        threat.timeLeft = wait + Math.max(0, DodgeMath.along(threat.line, hx, hy)) / speed;
        threat.source = projectile;
        learnShotTiming(projectile, speed);
        return threat;
    }

    // ---- where is safe -----------------------------------------------------------------

    // The hero's shape is built once per think around a vector of our own, then moved by
    // setting that vector - not rebuilt (a game object and an enum) for every check.
    static var heroShape:Dynamic = null;
    static var heroShapeVector:Dynamic = null;
    static var heroShapeFrame = -1;

    static function heroShapeAt(hero:Dynamic, x:Float, y:Float, z:Float):Dynamic {
        if (heroShapeFrame != frame || heroShape == null) {
            heroShapeFrame = frame;
            heroShape = buildHeroShape(hero, x, y, z);
        }
        if (heroShapeVector != null) {
            G.set(heroShapeVector, "x", x); G.set(heroShapeVector, "y", y); G.set(heroShapeVector, "z", z);
            return heroShape;
        }
        return buildHeroShape(hero, x, y, z);
    }

    static function buildHeroShape(hero:Dynamic, x:Float, y:Float, z:Float):Dynamic {
        var type = HlxRuntime.resolveType("CollisionShape");
        var vector = G.create("h3d.VectorImpl", [x, y, z]);
        try {
            var own = G.call("ent.Entity", "getColShape", hero);
            var name = Type.enumConstructor(own);
            var parameters:Array<Dynamic> = Type.enumParameters(own).copy();
            if (name != "OBBox" && parameters.length > 0) {
                parameters[0] = vector;
                var moved = HlxRuntime.constructEnum(type, name, parameters);
                if (moved != null) { heroShapeVector = vector; return moved; }
            }
        } catch (_:Dynamic) {}
        heroShapeVector = vector;
        return HlxRuntime.constructEnum(type, "Sphere", [vector, HERO_RADIUS]);
    }

    static function hits(hero:Dynamic, threat:Threat, x:Float, y:Float, z:Float):Bool {
        if (threat.train != null) return threat.mover ? trainArrival(threat, x, y) >= 0 : trainOnWay(threat.train, x, y); // on its way: get off
        if (threat.line != null) return DodgeMath.onLine(threat.line, x, y, HERO_RADIUS);
        if (threat.swing == null || !threat.swing.turns) {
            if (threat.br > 0) { // clearly outside its bounding circle: no game call needed
                var dx = x - threat.bx, dy = y - threat.by, limit = threat.br + HERO_RADIUS + BOUND_PAD;
                if (dx * dx + dy * dy > limit * limit) return false;
            }
            // Already checked this think around here (ways overlap a lot): the same answer.
            if (threat.hitCache == null) threat.hitCache = new Map();
            var key = ((Math.round(x * 4) & 0xFFFF) << 16) | (Math.round(y * 4) & 0xFFFF);
            var known = threat.hitCache.get(key);
            if (known != null) return known;
            // Shape checks go through the game: limited per think. Out of budget: assume the worst.
            if (shapeChecksLeft <= 0) { budgetOut = true; return true; }
            shapeChecksLeft--;
            var hit = shapeHits(hero, threat, x, y, z);
            threat.hitCache.set(key, hit);
            return hit;
        }
        if (threat.swing != null && threat.swing.turns)
            return DodgeMath.inReach(threat.swing.ownerX, threat.swing.ownerY, x, y, threat.swing.reach + threat.swing.advance, HERO_RADIUS);
        return false;
    }

    static function shapeHits(hero:Dynamic, threat:Threat, x:Float, y:Float, z:Float):Bool {
        var at = heroShapeAt(hero, x, y, z);
        if (threat.swing != null) {
            var w = threat.swing;
            if (threat.swingShape == null)
                threat.swingShape = G.call("st.skill.AreaStep", "getCollisionShape", w.step,
                    [G.create("h3d.VectorImpl", [w.x, w.y, w.z]), w.rotation, w.range]);
            return threat.swingShape != null && G.staticCall("HCollision", "checkCollideShapes", [threat.swingShape, at, null]) == true;
        }
        for (shape in threat.shapes)
            if (G.staticCall("HCollision", "checkCollideShapes", [shape, at, null]) == true) return true;
        return false;
    }

    static function safeAt(hero:Dynamic, threats:Array<Threat>, x:Float, y:Float, z:Float):Bool {
        for (threat in threats) if (hits(hero, threat, x, y, z)) return false;
        return true;
    }

    // ---- planning a way out, attack by attack --------------------------------------------------
    // A way is good when, at the moment each attack lands, the hero is somewhere it doesn't
    // reach - even if that means running (or dashing) through it before it fires. Only ground
    // effects that keep hurting are never stepped into.

    static function positionAt(path:Array<Point2>, t:Float, speed:Float, dashing:Bool):Point2
        return DodgeMath.positionAt(path, t - REACTION, speed, dashing ? DASH_DISTANCE : 0, DASH_TIME);

    /** How many attacks would still catch the hero going this way (0: a clean dodge). */
    static function hitsAlong(hero:Dynamic, threats:Array<Threat>, inside:Array<Threat>, path:Array<Point2>, z:Float, speed:Float, dashing:Bool):Int {
        var count = 0;
        var end = path[path.length - 1];
        for (t in threats) {
            if (t.lasting) {
                if (inside.indexOf(t) >= 0) {                 // already in it: only the end must be out
                    if (hits(hero, t, end.x, end.y, z)) count++;
                    continue;
                }
                var crossed = false;                          // never step into one
                for (i in 1...path.length) {
                    for (p in DodgeMath.pathPoints(path[i - 1].x, path[i - 1].y, path[i].x, path[i].y, PATH_STEP * 2))
                        if (hits(hero, t, p.x, p.y, z)) { crossed = true; break; }
                    if (crossed) break;
                }
                if (crossed) count++;
                continue;
            }
            if (t.shot != null) { if (shotHits(t, path, speed, dashing)) count++; continue; }
            if (t.train != null && !t.mover) {
                // A train's rails ahead of it (and under its cars): never stood on nor crossed while it comes -
                // its exact timing isn't trusted (it speeds up and slows down).
                var onRails = false;
                for (i in 1...path.length) {
                    for (p in DodgeMath.pathPoints(path[i - 1].x, path[i - 1].y, path[i].x, path[i].y, PATH_STEP))
                        if (trainOnWay(t.train, p.x, p.y)) { onRails = true; break; }
                    if (onRails) break;
                }
                if (onRails) count++;
                continue;
            }
            if (t.train != null) {
                // Every moment until the horizon: is the hero (running this way, then standing at its end)
                // where the train is? Crossing the rails in front of it is fine only with time to spare.
                var time = 0.0, hit = false;
                while (time <= TRAIN_HORIZON + 0.001) {
                    var at = positionAt(path, time, speed, dashing);
                    if (trainAt(t.train, at.x, at.y, time + TRAIN_PAD) || trainAt(t.train, at.x, at.y, Math.max(0, time - TRAIN_PAD))) { hit = true; break; }
                    time += TRAIN_STEP;
                }
                if (hit) count++;
                continue;
            }
            // Where the hero is when it lands (and just after, the hit isn't a single instant).
            var at = positionAt(path, t.timeLeft - HIT_EARLY, speed, dashing);
            if (hits(hero, t, at.x, at.y, z)) { count++; continue; }
            var after = positionAt(path, t.timeLeft + HIT_LATE, speed, dashing);
            if (hits(hero, t, after.x, after.y, z)) count++;
        }
        return count;
    }

    /** A shot that hasn't left yet goes where the hero is when it leaves: it misses only if the
        hero, moving, is off that line by the time it arrives - so the hero must still be on the
        move when it leaves, and keep going while it flies. */
    static function shotHits(t:Threat, path:Array<Point2>, speed:Float, dashing:Bool):Bool {
        var w = t.shot;
        var aim = positionAt(path, w.launch, speed, dashing);
        var dx = aim.x - w.ox, dy = aim.y - w.oy;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d < 0.3) return true;
        var line:DodgeMath.Line = {x: w.ox, y: w.oy, dx: dx / d, dy: dy / d, length: w.range, radius: w.radius};
        var arrive = w.launch + d / w.speed;
        for (dt in [-HIT_EARLY, 0.0, HIT_LATE]) {
            var at = positionAt(path, arrive + dt, speed, dashing);
            if (DodgeMath.onLine(line, at.x, at.y, HERO_RADIUS)) return true;
        }
        return false;
    }

    static final SEARCH_DISTANCES = [1.0, 2.0, 3.0, 4.5, 6.0, 8.0, 10.0];

    /**
     * The best way out that no attack catches, walking - or dashing when `dashing`. With
     * `allowHits`, the way caught by the fewest instead. Every walkable way (16 directions,
     * several distances, forward and sideways as much as back) is scored first - its length,
     * plus how boxed-in its end is: near a wall or an edge, in a corner, among monsters - and the
     * ways are then checked against the attacks best score first. Open ground wins over a
     * shorter way into a corner. Straight ways first; boxed in, a first leg sideways then out.
     */
    static function plan(hero:Dynamic, threats:Array<Threat>, hx:Float, hy:Float, hz:Float, speed:Float, dashing:Bool, allowHits:Bool, openOnly = false):Null<{spot:Spot, hits:Int}> {
        var inside = [for (t in threats) if (hits(hero, t, hx, hy, hz)) t];
        ensureMap(hx, hy, hz);
        var key = frame * 10 + relax;
        if (key != waysKey) { waysKey = key; straightWays = null; cornerWays = null; }
        var away = DodgeMath.awayAngle(hx, hy, [for (t in threats) {x: t.fromX, y: t.fromY}]);
        if (straightWays == null) straightWays = straightCandidates(hx, hy, hz, away);
        var best:Null<{spot:Spot, hits:Int}> = null;
        var start = {x: hx, y: hy};
        // A shot still to leave goes where the hero is then: a way that ends before it arrives can't dodge it.
        var needRun = 0.0;
        for (t in threats) if (t.shot != null) {
            var d = Math.sqrt((hx - t.shot.ox) * (hx - t.shot.ox) + (hy - t.shot.oy) * (hy - t.shot.oy));
            needRun = Math.max(needRun, t.shot.launch + d / t.shot.speed + HIT_LATE + REACTION);
        }
        var sources = [for (t in threats) if (inside.indexOf(t) >= 0 && t.shot == null && t.line == null) {x: t.fromX, y: t.fromY}];
        var bestFar = -1.0;
        function better(w:Spot, n:Int):Bool {
            if (!allowHits) return false;
            var far = 1e9;
            for (p in sources) far = Math.min(far, Math.sqrt((w.target.x - p.x) * (w.target.x - p.x) + (w.target.y - p.y) * (w.target.y - p.y)));
            if (best == null || n < best.hits || (n == best.hits && sources.length > 0 && far > bestFar + 0.5)) { bestFar = far; return true; }
            return false;
        }
        // Ways ending in the open first, straight then with a corner leg; ways ending at a wall
        // or in a corner only when no open one is clean - corners kill.
        var passes = openOnly ? [true] : [true, false];
        for (wantOpen in passes) {
            for (corner in [false, true]) {
                if (corner && cornerWays == null) cornerWays = cornerCandidates(hx, hy, hz, away);
                var tried = 0;
                for (w in (corner ? cornerWays : straightWays)) {
                    if ((w.open == true) != wantOpen) continue;
                    if (needRun > 0 && runTime(w.exit + MARGIN, speed, dashing) < needRun) continue;
                    if (tried++ >= MAX_TRIED) break;
                    var n = hitsAlong(hero, threats, inside, corner ? [start, w.via, w.target] : [start, w.target], hz, speed, dashing);
                    if (n == 0) return {spot: w, hits: 0};
                    if (better(w, n)) best = {spot: w, hits: n};
                }
            }
        }
        return best;
    }

    static var lastReposition = -10.0;
    /** True while the farming bot drives the hero: it picks its own fighting spots (Bot.crowdStep), and a second walker would only make the hero twitch. */
    public static var botDriven = false;
    /** A cast of the bot is cut for the dodge only when the walk out would otherwise end less than this many seconds before the hit. */
    static inline var CAST_GRACE = 0.5;
    static var castKeptLogged = -10.0;

    /** Nothing is about to hit, but the hero stands against a wall or in a corner with monsters
        around: walk (never dash) to open ground now, by a way no attack catches - there is room
        to dodge there, and none in a corner. */
    static function reposition(hero:Dynamic, threats:Array<Threat>, hx:Float, hy:Float, hz:Float, now:Float):Void {
        if (botDriven || mode == MODE_TELEPORT || runTarget != null || bodies.length == 0 || now - lastReposition < REPOSITION_EVERY) return;
        ensureMap(hx, hy, hz);
        if (isOpen(hx, hy)) return;
        lastReposition = now;
        var speed = Math.max(0.5, G.number(G.call("ent.Unit", "getMoveSpeed", currentHero, [null]), 5));
        unknownSeen = false;
        relax = 0;
        var way = plan(hero, threats, hx, hy, hz, speed, false, false, true);
        if (way == null) return;
        run(way.spot, hx, hy, now);
        DodgeLog.write(now, "REPOSITION out of a corner/wall: way=" + round(way.spot.exit) + " m" + (way.spot.via != null ? " via a corner" : "")
            + " open: wall " + round(openMap.clearance(way.spot.target.x, way.spot.target.y, OPEN_RANGE)) + " m, "
            + openMap.openDirections(way.spot.target.x, way.spot.target.y, OPEN_DIRECTIONS, OPEN_RANGE) + "/" + OPEN_DIRECTIONS
            + " free, here " + round(openMap.clearance(hx, hy, OPEN_RANGE)) + " m");
    }

    /** Seconds to cover `length` metres (the dash covering its part first). */
    static function runTime(length:Float, speed:Float, dashing:Bool):Float {
        if (!dashing) return length / speed;
        return length <= DASH_DISTANCE ? DASH_TIME * length / DASH_DISTANCE : DASH_TIME + (length - DASH_DISTANCE) / speed;
    }

    static var waysKey = -1;
    static var straightWays:Null<Array<Spot>> = null;
    static var cornerWays:Null<Array<Spot>> = null;

    static function straightCandidates(hx:Float, hy:Float, hz:Float, away:Float):Array<Spot> {
        var scored:Array<{spot:Spot, score:Float}> = [];
        for (distance in SEARCH_DISTANCES) {
            for (n in 0...DIRECTIONS) {
                var angle = n * 2 * Math.PI / DIRECTIONS;
                if (isAvoided(angle)) continue;
                var target = {x: hx + Math.cos(angle) * (distance + MARGIN), y: hy + Math.sin(angle) * (distance + MARGIN)};
                if (!walkable(hx, hy, hz, target.x, target.y).ok) continue;
                scored.push({spot: {exit: distance, target: target, jumpAt: -1, open: isOpen(target.x, target.y)},
                    score: distance + openScore(target.x, target.y) + headingCost(angle, away)});
            }
        }
        return bestFirst(scored);
    }

    static function cornerCandidates(hx:Float, hy:Float, hz:Float, away:Float):Array<Spot> {
        var scored:Array<{spot:Spot, score:Float}> = [];
        for (n in 0...DIRECTIONS) {
            var angle = n * 2 * Math.PI / DIRECTIONS;
            if (isAvoided(angle)) continue;
            var via = {x: hx + Math.cos(angle) * CORNER_LEG, y: hy + Math.sin(angle) * CORNER_LEG};
            if (!walkable(hx, hy, hz, via.x, via.y).ok) continue;
            for (k in 0...8) {
                var second = angle + k * Math.PI / 4;
                if (Math.abs(DodgeMath.angleDiff(second, angle + Math.PI)) < Math.PI / 4) continue; // not straight back
                for (distance in [3.0, 6.0]) {
                    var target = {x: via.x + Math.cos(second) * (distance + MARGIN), y: via.y + Math.sin(second) * (distance + MARGIN)};
                    if (!walkable(via.x, via.y, hz, target.x, target.y).ok) continue;
                    scored.push({spot: {exit: CORNER_LEG + distance, target: target, jumpAt: -1, via: via, open: isOpen(target.x, target.y)},
                        score: CORNER_LEG + distance + openScore(target.x, target.y) + headingCost(angle, away)});
                }
            }
        }
        return bestFirst(scored);
    }

    static function bestFirst(scored:Array<{spot:Spot, score:Float}>):Array<Spot> {
        scored.sort((a, b) -> a.score < b.score ? -1 : a.score > b.score ? 1 : 0);
        return [for (w in scored) w.spot];
    }

    /** Ties between equally open ways are broken by heading: away from the dangers rather than
        into them, and on the way just run rather than turning around (which only loses time). */
    static function headingCost(angle:Float, away:Float):Float {
        var cost = AWAY_COST * (1 - Math.cos(angle - away)) / 2;
        if (haxe.Timer.stamp() - lastRunAt < KEEP_HEADING_TIME) cost += TURN_COST * (1 - Math.cos(angle - lastRunAngle)) / 2;
        return cost;
    }

    /** How bad a spot is to stand in, in metres of extra running it is worth avoiding: walls,
        ledges and obstacles within OPEN_RANGE (the closer the worse), every closed direction
        around it (a corner closes many), and monsters next to it. 0: open ground. */
    /** Open ground: no wall, edge or obstacle within OPEN_CLEAR, and most directions free. */
    static function isOpen(x:Float, y:Float):Bool
        return openMap.clearance(x, y, OPEN_RANGE) >= OPEN_CLEAR && openMap.openDirections(x, y, OPEN_DIRECTIONS, OPEN_RANGE) >= OPEN_FREE;

    static function openScore(x:Float, y:Float):Float {
        var clear = openMap.clearance(x, y, OPEN_RANGE);
        var free = openMap.openDirections(x, y, OPEN_DIRECTIONS, OPEN_RANGE);
        var crowd = 0;
        for (b in bodies) if ((b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) < CROWD_RANGE * CROWD_RANGE) crowd++;
        return CLEAR_COST * (OPEN_RANGE - clear) + DIR_COST * (OPEN_DIRECTIONS - free) + CROWD_COST * crowd;
    }

    // ---- the open-space map ----------------------------------------------------------------------
    static var openMap = new OpenMap(MAP_RADIUS);
    static var openMapAt = -10.0;
    static var openMapX = 0;
    static var openMapY = 0;

    /** Rebuilds the open-space map around the hero from the heights read so far (no new reads). */
    static function ensureMap(hx:Float, hy:Float, hz:Float):Void {
        var now = haxe.Timer.stamp();
        var cx = OpenMap.cellOf(hx), cy = OpenMap.cellOf(hy);
        if (now - openMapAt < MAP_REFRESH && Math.abs(cx - openMapX) + Math.abs(cy - openMapY) < 3) return;
        openMapAt = now;
        openMapX = cx;
        openMapY = cy;
        var here = surfaceZ(hx, hy, hz);
        var trust = Math.isFinite(here) && Math.abs(here - hz) <= HEIGHT_TRUST;
        var roof = tallAt(hx, hy, hz); // under a roof or a tree: tall things overhead say nothing
        Hazard.budget = 150;
        openMap.build(cx, cy,
            (ix, iy) -> trust ? knownZ(surfaceCache, surfaceFrom, ix, iy, hz) : Math.NaN,
            (ix, iy) -> isRemembered(ix * OpenMap.CELL, iy * OpenMap.CELL) || (trust && !roof && knownTall(ix, iy, hz)) || (trust && wetKnown(ix, iy, hz)) || Hazard.trapAt(ix * OpenMap.CELL, iy * OpenMap.CELL, hz),
            stepHeight());
    }

    /** Water (or a harmful liquid) on a cell whose height is known: the dodge never runs into it. */
    static function wetKnown(ix:Int, iy:Int, hz:Float):Bool {
        var z = knownZ(surfaceCache, surfaceFrom, ix, iy, hz);
        return Math.isFinite(z) && Hazard.wetCell(ix * OpenMap.CELL, iy * OpenMap.CELL, z, 0.5, true);
    }

    static var scanX = 0x7fffffff;
    static var scanY = 0;
    static var scanDx:Array<Int> = null;
    static var scanDy:Array<Int> = null;

    /** Reads heights around the hero ahead of time, nearest first, a little every think. */
    static function scan(hx:Float, hy:Float, hz:Float):Void {
        if (scanDx == null) {
            var r = Std.int(SCAN_RADIUS / OpenMap.CELL);
            var cells = [for (dy in -r...r + 1) for (dx in -r...r + 1) if (dx * dx + dy * dy <= r * r) {dx: dx, dy: dy}];
            cells.sort((a, b) -> (a.dx * a.dx + a.dy * a.dy) - (b.dx * b.dx + b.dy * b.dy));
            scanDx = [for (c in cells) c.dx];
            scanDy = [for (c in cells) c.dy];
        }
        var cx = OpenMap.cellOf(hx), cy = OpenMap.cellOf(hy);
        if (cx == scanX && cy == scanY) return; // all read around this cell already
        var budget = SCAN_BUDGET;
        for (k in 0...scanDx.length) {
            var ix = cx + scanDx[k], iy = cy + scanDy[k];
            if (!Math.isFinite(knownZ(surfaceCache, surfaceFrom, ix, iy, hz))) { readCell(ix, iy, hz, SURFACE_TOP, surfaceCache, surfaceFrom); budget--; }
            if (!Math.isFinite(knownZ(tallCache, tallFrom, ix, iy, hz))) { readCell(ix, iy, hz, TALL_TOP, tallCache, tallFrom); budget--; }
            if (budget <= 0 || readsLeft <= 0) return;
        }
        scanX = cx;
        scanY = cy;
    }

    static function isAvoided(angle:Float):Bool {
        for (a in avoided) if (Math.abs(DodgeMath.angleDiff(angle, a.angle)) < Math.PI / 8) return true;
        return false;
    }

    /**
     * Whether the hero can run straight from (hx, hy) to (tx, ty), read from the height of the
     * top surface along the way (World.getZ: terrain plus anything solid on it - walls, fences,
     * tables, rocks - what monsters' pathfinding reads too), across the hero's whole width:
     *  - a rise of more than STEP_UP (anything the hero doesn't just walk up): blocked - gone
     *    around, never jumped (a failed jump is what left the hero stuck at fences);
     *  - something taller than the hero: blocked;
     *  - a drop of more than MAX_DROP: a cliff, blocked.
     * A height that can't be read this frame (budget spent) counts as blocked.
     */
    static function walkable(hx:Float, hy:Float, hz:Float, tx:Float, ty:Float):{ok:Bool, jumpAt:Float} {
        var dx = tx - hx, dy = ty - hy;
        var length = Math.sqrt(dx * dx + dy * dy);
        if (length < 0.01) return {ok: true, jumpAt: -1};
        var ux = dx / length, uy = dy / length;
        var sideX = -uy * BODY_HALF_WIDTH, sideY = ux * BODY_HALF_WIDTH;
        var here = surfaceZ(hx, hy, hz);
        if (!Math.isFinite(here)) { unknownSeen = true; return {ok: false, jumpAt: -1}; }
        // On a platform, bridge or ship the game's height data doesn't see (the hero's own spot
        // reads far off their feet), heights mean nothing here: only bodies and learnt obstacles.
        var heights = relax < 2 && Math.abs(here - hz) <= HEIGHT_TRUST;
        // The way starts from the hero's feet: the 50 cm cell under them may read the edge of a
        // wall they stand next to, which would make every way look like a drop.
        var previous = Math.abs(here - hz) <= stepHeight() ? here : hz;
        var heroTall = tallAt(hx, hy, hz); // standing under a roof or a tree: tall things overhead don't count
        var stepUp = stepHeight();
        for (p in DodgeMath.pathPoints(hx, hy, tx, ty, PATH_STEP)) {
            if (relax == 0 && isRemembered(p.x, p.y)) return {ok: false, jumpAt: -1}; // the hero ran into something here before
            if (inBody(p.x, p.y, hx, hy)) return {ok: false, jumpAt: -1};   // a monster stands there
            if (!heights) continue;
            var z = surfaceZ(p.x, p.y, hz);
            if (!Math.isFinite(z)) { unknownSeen = true; return {ok: false, jumpAt: -1}; } // not read yet: next frame
            if ((p.x - hx) * (p.x - hx) + (p.y - hy) * (p.y - hy) > 2.25 && Hazard.wetCell(p.x, p.y, z, 0.6)) return {ok: false, jumpAt: -1}; // water: death
            if (Hazard.trapAt(p.x, p.y, z)) return {ok: false, jumpAt: -1};  // a trap
            if (previous - z > MAX_DROP) return {ok: false, jumpAt: -1};    // cliff
            if (z - previous > stepUp) return {ok: false, jumpAt: -1};      // wall, fence, table, rock
            for (side in [1.0, -1.0]) {
                var sx = p.x + sideX * side, sy = p.y + sideY * side;
                var sz = surfaceZ(sx, sy, hz);
                if (!Math.isFinite(sz)) { unknownSeen = true; return {ok: false, jumpAt: -1}; }
                if (sz - z > stepUp) return {ok: false, jumpAt: -1};        // a post or corner beside the middle line
                if (relax == 0 && isRemembered(sx, sy)) return {ok: false, jumpAt: -1};
            }
            if (!heroTall && tallAt(p.x, p.y, hz)) return {ok: false, jumpAt: -1};
            if (relax == 0 && openMap.blockedAt(p.x, p.y)
                && (p.x - hx) * (p.x - hx) + (p.y - hy) * (p.y - hy) > 0.36) return {ok: false, jumpAt: -1}; // a wall or edge on the map
            previous = z;
        }
        return {ok: true, jumpAt: -1};
    }

    /** The highest rise the hero walks up by itself: its body's own step height (what the game
        lets it climb without jumping), never below STEP_UP. */
    static function stepHeight():Float {
        try {
            var body = G.field(currentHero, "body");
            var step = G.number(G.field(body, "stepHeight"), 0);
            var ledge = G.number(G.field(body, "maxLedgeHeight"), 0);
            return Math.max(STEP_UP, Math.max(step, Math.min(ledge, 1.0)));
        } catch (_:Dynamic) return STEP_UP;
    }

    // ---- monsters' bodies ----------------------------------------------------------------------
    static var bodies:Array<{x:Float, y:Float, r:Float}> = [];

    /** A spot inside a monster's body (not counting one the hero is already touching at the start). */
    static function inBody(x:Float, y:Float, hx:Float, hy:Float):Bool {
        for (b in bodies) {
            var r = b.r + BODY_PAD;
            if ((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) >= r * r) continue;
            if ((hx - b.x) * (hx - b.x) + (hy - b.y) * (hy - b.y) < r * r) continue; // touching it now: moving away is fine
            return true;
        }
        return false;
    }

    static function bodyAhead(hx:Float, hy:Float, angle:Float):Bool {
        var ax = hx + Math.cos(angle) * 0.8, ay = hy + Math.sin(angle) * 0.8;
        for (b in bodies) {
            var r = b.r + 0.6;
            if ((ax - b.x) * (ax - b.x) + (ay - b.y) * (ay - b.y) < r * r) return true;
        }
        return false;
    }

    static function bodyRadius(unit:Dynamic):Float {
        try {
            var shape = G.call("ent.Entity", "getColShape", unit);
            var parameters = Type.enumParameters(shape);
            if (parameters.length > 1) {
                var r = G.number(parameters[1], -1);
                if (r > 0 && r < 5) return r;
            }
        } catch (_:Dynamic) {}
        return 0.6;
    }

    // ---- obstacles learnt by running into them ------------------------------------------------
    // Fences, posts and furniture aren't in the heights the game hands out; where the hero gets
    // stopped, the cells right ahead are remembered as blocked (for this map) and avoided after.
    static var remembered = new Map<Int, Float>();
    static var rememberedCount = 0;

    static function cellKey(x:Float, y:Float):Int return packKey(Math.round(x / MEMORY_CELL), Math.round(y / MEMORY_CELL));
    static inline function packKey(ix:Int, iy:Int):Int return ((ix & 0xFFFF) << 16) | (iy & 0xFFFF);

    static function isRemembered(x:Float, y:Float):Bool {
        if (rememberedCount == 0) return false;
        var since = remembered.get(cellKey(x, y));
        return since != null && haxe.Timer.stamp() - since < MEMORY_TIME;
    }

    static function remember(hx:Float, hy:Float, angle:Float):Void {
        if (rememberedCount > MEMORY_MAX) { remembered = new Map(); rememberedCount = 0; }
        var ux = Math.cos(angle), uy = Math.sin(angle);
        for (ahead in [0.5, 0.9])
            for (side in [-0.4, 0.0, 0.4]) {
                var key = cellKey(hx + ux * ahead - uy * side, hy + uy * ahead + ux * side);
                if (!remembered.exists(key)) rememberedCount++;
                remembered.set(key, haxe.Timer.stamp());
            }
    }

    /** A new map, or far away (teleport): what was learnt no longer applies. */
    static function forgetIfMoved(hx:Float, hy:Float):Void {
        if (lastSeenX != null && Math.abs(hx - lastSeenX) + Math.abs(hy - lastSeenY) > 80) {
            remembered = new Map(); rememberedCount = 0;
            resetHeights();
        }
        lastSeenX = hx; lastSeenY = hy;
    }
    static var lastSeenX:Null<Float> = null;
    static var lastSeenY = 0.0;

    // Surface heights are cached on the open-space map's grid (OpenMap.CELL) for a while (the
    // world doesn't move), and at most HEIGHT_BUDGET new ones are read per think, so the search
    // never weighs on the game. Each read is the game's own physics-aware height sampling
    // (World.sampleZWithFilter: terrain AND everything solid on it - walls, fences, buildings,
    // dungeon floors); World.getZ without its physics flag only knows the bare terrain.
    static var surfaceCache = new Map<Int, Float>();
    static var surfaceFrom = new Map<Int, Float>();
    static var tallCache = new Map<Int, Float>();
    static var tallFrom = new Map<Int, Float>();
    static var cacheSince = 0.0;
    static var cacheSize = 0;
    static var frame = 0;
    static var readsFrame = -1;
    static var readsLeft = 0;
    static var world:Dynamic = null;
    static var physicsHeights = true;   // false once the physics sampling failed: bare terrain only
    static var physicsError = "";
    static var sampleFrom:Dynamic = null;
    static var sampleTo:Dynamic = null;
    static var noFilter:Dynamic = null;

    static function resetHeights():Void {
        surfaceCache = new Map(); surfaceFrom = new Map();
        tallCache = new Map(); tallFrom = new Map();
        cacheSize = 0;
        cacheSince = haxe.Timer.stamp();
        scanX = 0x7fffffff;
    }

    /** Height of the top surface at (x, y) below the hero's head. NaN: not read (budget). */
    static function surfaceZ(x:Float, y:Float, hz:Float):Float
        return readCell(OpenMap.cellOf(x), OpenMap.cellOf(y), hz, SURFACE_TOP, surfaceCache, surfaceFrom);

    /** Something taller than the hero at (x, y): seen only from high above (a ray starting
        inside a tall wall finds nothing, so it is looked at from over the top too). */
    static function tallAt(x:Float, y:Float, hz:Float):Bool {
        var z = readCell(OpenMap.cellOf(x), OpenMap.cellOf(y), hz, TALL_TOP, tallCache, tallFrom);
        if (!Math.isFinite(z)) { unknownSeen = true; return true; }
        return z > hz + TALL_HEIGHT;
    }

    static function knownTall(ix:Int, iy:Int, hz:Float):Bool {
        var z = knownZ(tallCache, tallFrom, ix, iy, hz);
        return Math.isFinite(z) && z > hz + TALL_HEIGHT;
    }

    /** A cached height, read from about the hero's present height; NaN if there is none. */
    static function knownZ(cache:Map<Int, Float>, from:Map<Int, Float>, ix:Int, iy:Int, hz:Float):Float {
        var key = packKey(ix, iy);
        var z = cache.get(key);
        if (z == null) return Math.NaN;
        var at = from.get(key);
        return at != null && Math.abs(at - hz) < LEVEL_TOLERANCE ? z : Math.NaN;
    }

    static function readCell(ix:Int, iy:Int, hz:Float, above:Float, cache:Map<Int, Float>, from:Map<Int, Float>):Float {
        var now = haxe.Timer.stamp();
        if (now - cacheSince > HEIGHT_CACHE_TIME || cacheSize > CACHE_MAX) { resetHeights(); cache = above == TALL_TOP ? tallCache : surfaceCache; from = above == TALL_TOP ? tallFrom : surfaceFrom; }
        if (frame != readsFrame) { readsFrame = frame; readsLeft = HEIGHT_BUDGET; }
        var known = knownZ(cache, from, ix, iy, hz);
        if (Math.isFinite(known)) return known;
        if (readsLeft <= 0) return Math.NaN;
        readsLeft--;
        var z = worldZ(ix * OpenMap.CELL, iy * OpenMap.CELL, hz, above);
        var key = packKey(ix, iy);
        cache.set(key, z);
        from.set(key, hz);
        cacheSize++;
        return z;
    }

    /** The surface height at (x, y) seen from `above` metres over `hz`, looking down. */
    public static function worldZ(x:Float, y:Float, hz:Float, above:Float):Float {
        try {
            if (world == null) world = G.current("world.World", "inst");
            if (physicsHeights) {
                try {
                    if (sampleFrom == null) {
                        sampleFrom = G.create("h3d.VectorImpl", [0.0, 0.0, 0.0]);
                        sampleTo = G.create("h3d.VectorImpl", [0.0, 0.0, 0.0]);
                        noFilter = function(point:Dynamic, last:Dynamic):Bool return false;
                    }
                    // One sample at (x, y): from (hz + above) down to (hz - above).
                    G.set(sampleFrom, "x", x); G.set(sampleFrom, "y", y); G.set(sampleFrom, "z", hz);
                    G.set(sampleTo, "x", x + 0.01); G.set(sampleTo, "y", y); G.set(sampleTo, "z", hz);
                    var point = G.call("world.World", "sampleZWithFilter", world, [sampleFrom, sampleTo, 1.0, above, noFilter]);
                    var found = G.number(G.field(point, "z"), Math.NaN);
                    if (Math.isFinite(found)) return found;
                } catch (e:Dynamic) {
                    physicsHeights = false;
                    physicsError = Std.string(e);
                }
            }
            var found = G.number(G.call("world.World", "getZ", world, [x, y, hz + above, null, null]), Math.NaN);
            if (Math.isFinite(found)) return found;
        } catch (_:Dynamic) {}
        return hz - GROUND_PROBE - 100;
    }

    /** Ground height at (x, y) for a teleport destination. */
    static function groundZ(x:Float, y:Float, hz:Float):Float {
        var z = surfaceZ(x, y, hz);
        return Math.isFinite(z) ? z : hz;
    }

    static var probed = false;

    /** Diagnostics: what the surface-height check reports around the hero (largest rise/drop within 3 m per direction). */
    static function probe(hero:Dynamic, now:Float, why:String):Void {
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var here = surfaceZ(hx, hy, hz);
        var terrain = try G.number(G.call("world.World", "getZ", G.current("world.World", "inst"), [hx, hy, hz + SURFACE_TOP, null, null]), Math.NaN) catch (_:Dynamic) Math.NaN;
        DodgeLog.write(now, "heights: " + (physicsHeights ? "physics (walls, fences, floors)" : "terrain only - physics failed: " + physicsError)
            + ", under the hero " + round(here) + ", bare terrain " + round(terrain));
        var parts = [];
        for (i in 0...8) {
            var a = i * Math.PI / 4;
            var worst = 0.0;
            for (k in 1...13) {
                var z = surfaceZ(hx + Math.cos(a) * k * 0.5, hy + Math.sin(a) * k * 0.5, hz) - here;
                if (Math.isFinite(z) && Math.abs(z) > Math.abs(worst)) worst = z;
            }
            var way = walkable(hx, hy, hz, hx + Math.cos(a) * 6, hy + Math.sin(a) * 6);
            parts.push(Std.string(i * 45) + "deg:" + round(worst) + (way.ok ? "" : "X"));
        }
        DodgeLog.write(now, "PROBE " + why + ": heroZ=" + round(hz) + " surface=" + round(here)
            + " heights within 6 m (X = blocked) " + parts.join(" "));
    }

    // ---- moving --------------------------------------------------------------------------

    static function dashReady(hero:Dynamic):Bool {
        try {
            var skill = G.call("ent.GameObject", "getSkill", hero, [DASH_KIND]);
            return skill != null && G.number(G.call("st.skill.Skill", "getCooldownLeft", skill), 1) <= 0;
        } catch (_:Dynamic) return false;
    }

    /** The game's own dash, like its key: facing the spot (the run direction is set as well). */
    static function dash(hero:Dynamic, spot:Point2):Void {
        try {
            var controller = G.current("client.PlayerController", "inst");
            if (controller == null) return;
            var angle = Math.atan2(spot.y - G.number(G.field(hero, "posy")), spot.x - G.number(G.field(hero, "posx")));
            G.call("ent.Unit", "rotateTo", hero, [angle]);
            G.call("client.UnitController", "requestSkillKind", controller, [DASH_INPUT, DASH_KIND]);
        } catch (_:Dynamic) {}
    }

    static var shotsForeseen = new haxe.ds.ObjectMap<Dynamic, Float>();
    static var lateReported = new Map<String, Bool>();

    /** Diagnostics: an arrow first dodged too late - which skill, and why it wasn't foreseen. */
    static function reportLateShot(projectile:Dynamic, hero:Dynamic, now:Float):Void {
        try {
            var skill = G.field(projectile, "baseSkill");
            var owner = G.field(skill, "owner");
            var skillKind = G.text(G.field(skill, "kind"), "?");
            var foreseen = shotsForeseen.get(owner);
            var key = skillKind + (foreseen != null && now - foreseen < 2 ? "+" : "-");
            if (lateReported.exists(key)) return;
            lateReported.set(key, true);
            var target:Dynamic = try G.call("ent.Unit", "get_targetUnit", owner) catch (_:Dynamic) null;
            var types = [];
            var active = try G.call("ent.GameObject", "getActiveSkill", owner) catch (_:Dynamic) null;
            if (active != null)
                for (step in G.fastArray(G.field(active, "steps")))
                    try {
                        var inf = G.field(step, "inf");
                        var type = G.integer(G.field(inf, "type"), -1);
                        var info = type + "@" + G.text(G.field(inf, "delay"), "-") + " on" + G.text(G.field(inf, "on"), "?")
                            + (G.call("st.skill.SkillStep", "hasStarted", step) == true ? " started(left " + round(G.number(G.call("st.skill.SkillStep", "getDurationLeft", step), -1)) + ")" : "");
                        if (type == STEP_PROJECTILE) {
                            var shot = G.field(G.field(inf, "props"), "projectile");
                            info += " follow" + G.text(G.field(shot, "followTime"), "-") + " speed" + G.text(G.field(shot, "speed"), "-");
                        }
                        types.push(info);
                    } catch (_:Dynamic) {}
            var casting = try G.call("st.skill.Skill", "isCasting", active) == true catch (_:Dynamic) false;
            types.push("casting " + casting + (casting ? " left " + round(G.number(G.call("st.skill.Skill", "getCastTimeLeft", active), -1)) : "")
                + " elapsed " + round(G.number(G.call("st.skill.BaseSkill", "getElapsedTime", active), -1)));
            DodgeLog.write(now, "LATE SHOT from " + skillKind + ": foreseen " + (foreseen != null && now - foreseen < 2 ? round(now - foreseen) + " s ago" : "never")
                + ", archer's target " + (target == hero ? "the hero" : target == null ? "none" : "other")
                + ", its skill now " + (active == null ? "none" : G.text(G.field(active, "kind"), "?") + " steps " + types.join(" | ")));
        } catch (_:Dynamic) {}
    }

    static function kind(t:Threat):String
        return t.mover ? "moving(in " + round(t.timeLeft) + " s)"
            : t.train != null ? "train(in " + round(t.timeLeft) + " s)"
            : t.melee && t.shot != null ? "lunge(in " + round(t.shot.launch) + " s, bite " + round(t.timeLeft) + " s)"
            : t.melee && t.swing.step == null ? "keep-away(reach " + round(t.swing.reach) + " m)"
            : t.melee ? "melee(reach " + round(t.swing.reach) + " m +" + round(t.swing.advance) + " m)"
            : t.swing != null ? (t.swing.turns ? "swing(monster +" + round(t.swing.advance) + " m)" : "swing(aimed)")
            : t.shot != null ? "shot(in " + round(t.shot.launch) + " s)" : t.line != null ? "projectile" : t.lasting ? "area(lasting)" : "area";

    static function round(v:Float):String return Std.string(Math.round(v * 100) / 100);

    static function enumName(value:Dynamic):String {
        if (value == null) return "";
        try return Type.enumConstructor(value) catch (_:Dynamic) return "";
    }

    // Entity types already sorted into projectiles or not (a handful): no type names per entity.
    static var projectileTypes:Array<hl.Type> = [];
    static var otherTypes:Array<hl.Type> = [];

    static var trainTypes:Array<hl.Type> = [];
    static var notTrainTypes:Array<hl.Type> = [];

    static function isTrain(object:Dynamic):Bool {
        var type = hl.Type.getDynamic(object);
        for (t in trainTypes) if (t == type) return true;
        for (t in notTrainTypes) if (t == type) return false;
        var yes = isA(object, "ent.interactible.SplineTrain");
        (yes ? trainTypes : notTrainTypes).push(type);
        return yes;
    }

    /** A train (mine carts...) running on its rails: its head's way over the next seconds. */
    static function trainThreat(hero:Dynamic, train:Dynamic):Null<Threat> {
        if (G.field(train, "removed") == true) return null;
        if (try G.call("ent.interactible.SplineTrain", "isStopped", train) == true catch (_:Dynamic) false) return null;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        var pts:Array<{t:Float, x:Float, y:Float}> = [];
        var t = 0.0;
        var near = false;
        while (t <= TRAIN_HORIZON + 0.001) {
            var p = G.call("ent.interactible.SplineTrain", "getProjectedPosition", train, [t]);
            if (p == null) return null;
            var x = G.number(G.field(p, "x")), y = G.number(G.field(p, "y"));
            pts.push({t: t, x: x, y: y});
            if ((x - hx) * (x - hx) + (y - hy) * (y - hy) < TRAIN_NOTICE * TRAIN_NOTICE) near = true;
            t += TRAIN_STEP;
        }
        // Its speed, from the first steps of its way; the cars follow the head at their spacing.
        var a = pts[0], b = pts[1];
        var speed = Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)) / TRAIN_STEP;
        var cars = G.fastArray(G.field(train, "cars"));
        var spacing = G.number(G.field(G.field(train, "trainInf"), "carSpacing"), 3);
        var length = (cars.length + 1) * Math.max(1, spacing);
        // Where the cars behind the head are now: the head's way so far, read backwards.
        if (speed > 0.3) {
            var back = TRAIN_STEP;
            while (back <= length / speed + 0.001 && back <= 4) {
                var p = G.call("ent.interactible.SplineTrain", "getProjectedPosition", train, [-back]);
                if (p == null) break;
                var x = G.number(G.field(p, "x")), y = G.number(G.field(p, "y"));
                pts.unshift({t: -back, x: x, y: y});
                if ((x - hx) * (x - hx) + (y - hy) * (y - hy) < TRAIN_NOTICE * TRAIN_NOTICE) near = true;
                back += TRAIN_STEP;
            }
        }
        if (!near) return null;
        var radius = 0.0;
        for (car in cars) { radius = Math.max(radius, objectSize(car)); trainCars.set(car, now()); }
        trainCars.set(train, now());
        radius = Math.max(TRAIN_WIDTH, radius + 0.5); // never less than measured on a real train
        var learnt = hazardExtra.get("train");
        if (learnt != null) radius += learnt;
        var threat = new Threat();
        threat.train = {pts: pts, tail: speed > 0.3 ? length / speed : 4.0, radius: radius};
        threat.hazardName = "train";
        threat.lasting = false;
        threat.timeLeft = trainArrival(threat, hx, hy);
        if (threat.timeLeft < 0) threat.timeLeft = TRAIN_HORIZON;
        threat.fromX = pts[pts.length - 1].x; threat.fromY = pts[pts.length - 1].y;
        // Away from the rails sideways: the nearest point of its way.
        var best = 1e18;
        for (p in pts) {
            var d = (p.x - hx) * (p.x - hx) + (p.y - hy) * (p.y - hy);
            if (d < best) { best = d; threat.fromX = p.x; threat.fromY = p.y; }
        }
        return threat;
    }

    /** True if the train occupies (x, y) at `time` s from now: its head passed there within the
        time its cars take to go by. */
    /** True if (x, y) is anywhere on the train's way over the horizon, or under its cars now. */
    static function trainOnWay(w:{pts:Array<{t:Float, x:Float, y:Float}>, tail:Float, radius:Float}, x:Float, y:Float):Bool {
        var r = w.radius + HERO_RADIUS;
        for (p in w.pts) if ((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) < r * r) return true;
        return false;
    }

    static function trainAt(w:{pts:Array<{t:Float, x:Float, y:Float}>, tail:Float, radius:Float}, x:Float, y:Float, time:Float):Bool {
        var r = w.radius + HERO_RADIUS;
        for (p in w.pts) {
            if (p.t > time || p.t < time - w.tail) continue;
            if ((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) < r * r) return true;
        }
        return false;
    }

    /** When the train first reaches (x, y) (0: it is there now); -1: not within the horizon. */
    static function trainArrival(t:Threat, x:Float, y:Float):Float {
        var w = t.train;
        var time = 0.0;
        while (time <= TRAIN_HORIZON + 0.001) {
            if (trainAt(w, x, y, time)) return time;
            time += TRAIN_STEP;
        }
        return -1;
    }

    static inline var KIND_IGNORE = 0;
    static inline var KIND_TRAIN = 1;
    static inline var KIND_OTHER = 2;
    static var kindTypes:Array<hl.Type> = [];
    static var kindValues:Array<Int> = [];

    /** What a game object is, for collision hazards (cached by type): monsters, heroes and
        projectiles are handled on their own; areas too. */
    static function objectKind(object:Dynamic):Int {
        var type = hl.Type.getDynamic(object);
        for (i in 0...kindTypes.length) if (kindTypes[i] == type) return kindValues[i];
        var kind = isA(object, "ent.interactible.SplineTrain") ? KIND_TRAIN
            : isA(object, "ent.Unit") || isA(object, "ent.Hero") || isA(object, "ent.Projectile") || isA(object, "st.skill.SkillArea") ? KIND_IGNORE
            : KIND_OTHER;
        kindTypes.push(type);
        kindValues.push(kind);
        return kind;
    }

    static var trainCars = new haxe.ds.ObjectMap<Dynamic, Float>();
    static var hazardExtra = new Map<String, Float>();   // per kind of moving hazard: metres added after it hit the hero

    /** How far an object reaches around its position, from its own collision shape (a rotated
        box: to its corner); -1 when it can't be read. */
    static function objectSize(object:Dynamic):Float {
        try {
            var shape = G.call("ent.Entity", "getColShape", object);
            if (shape == null) return -1;
            var r = G.number(G.staticCall("HCollision", "getMaxRadius", [shape]), -1);
            if (r <= 0 || r > 30) return -1;
            var name = Type.enumConstructor(shape);
            return name == "OBBox" ? r * Math.sqrt(3) : name == "HBBox" ? r * 2 : r;
        } catch (_:Dynamic) return -1;
    }
    static inline function now():Float return haxe.Timer.stamp();
    static var moversSeen = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>();
    static var moverReported = new Map<String, Bool>();
    static var projectilesMoving = new haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>();

    /**
     * Anything that moves fast near the hero and isn't a player's (a mine cart, a boss's blade, a
     * rolling boulder): its speed measured from where it was a moment ago, and its way over the
     * next MOVER_HORIZON seconds assumed straight - the hero must not be where it will be.
     */
    static function moverThreat(hero:Dynamic, object:Dynamic, now:Float, alive:haxe.ds.ObjectMap<Dynamic, {x:Float, y:Float, t:Float, vx:Float, vy:Float}>):Null<Threat> {
        if (G.field(object, "removed") == true) return null;
        var x = G.number(G.field(object, "posx")), y = G.number(G.field(object, "posy"));
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        if ((x - hx) * (x - hx) + (y - hy) * (y - hy) > MOVER_NOTICE * MOVER_NOTICE) return null;
        var vx = 0.0, vy = 0.0;
        var before = moversSeen.get(object);
        if (before != null && now > before.t) {
            var dt = now - before.t;
            if (dt < 0.02) { vx = before.vx; vy = before.vy; }
            else { vx = (x - before.x) / dt; vy = (y - before.y) / dt; }
        }
        alive.set(object, {x: x, y: y, t: now, vx: vx, vy: vy});
        var speed = Math.sqrt(vx * vx + vy * vy);
        if (speed < MOVER_MIN_SPEED || speed > MOVER_MAX_SPEED) return null; // standing, or a teleport/respawn jump
        if (friendly(object)) return null;
        var pts:Array<{t:Float, x:Float, y:Float}> = [];
        var t = 0.0;
        while (t <= MOVER_HORIZON + 0.001) { pts.push({t: t, x: x + vx * t, y: y + vy * t}); t += TRAIN_STEP; }
        var threat = new Threat();
        // A train's car is big: as wide around as the train itself (measured: hits ~4.5 m from its middle).
        var name = hl.Type.getDynamic(object).getTypeName();
        var size = objectSize(object);
        var radius = size > 0 ? size + 0.5 : MOVER_MIN_RADIUS;
        if (trainCars.exists(object)) radius = Math.max(TRAIN_WIDTH, radius);
        var learnt = hazardExtra.get(name);
        threat.train = {pts: pts, tail: TRAIN_STEP * 3, radius: Math.max(MOVER_MIN_RADIUS, radius + (learnt == null ? 0 : learnt))};
        threat.hazardName = name;
        threat.mover = true;
        var arrive = trainArrival(threat, hx, hy);
        threat.timeLeft = arrive >= 0 ? arrive : MOVER_HORIZON;
        // Away from its way sideways: the nearest point of it.
        var line:DodgeMath.Line = {x: x, y: y, dx: vx / speed, dy: vy / speed, length: speed * MOVER_HORIZON, radius: 0};
        var side = DodgeMath.sideSource(line, hx, hy);
        threat.fromX = side.x; threat.fromY = side.y;
        if (arrive >= 0 && !moverReported.exists(name)) {
            moverReported.set(name, true);
            DodgeLog.write(now, "moving hazard: " + name + " at " + round(speed) + " m/s, radius " + round(threat.train.radius) + " m");
        }
        return threat;
    }

    static function isProjectile(object:Dynamic):Bool {
        var type = hl.Type.getDynamic(object);
        for (t in projectileTypes) if (t == type) return true;
        for (t in otherTypes) if (t == type) return false;
        var yes = isA(object, "ent.Projectile");
        (yes ? projectileTypes : otherTypes).push(type);
        return yes;
    }

    static function isA(object:Dynamic, typeName:String):Bool {
        if (object == null) return false;
        var type = hl.Type.getDynamic(object);
        while (type != null && type.kind == HObj) {
            if (type.getTypeName() == typeName) return true;
            type = type.getSuper();
        }
        return false;
    }
}
