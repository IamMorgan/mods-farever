package macromod;

import macromod.GameAccess as G;
import macromod.SkillIO.Readiness;
import macromod.SkillMatch.SkillRef;

/**
 * Uses a skill exactly like pressing its key does: client.UnitController.requestSkillKind on the
 * local player's controller (client.PlayerController.inst). The game then resolves the request
 * on its own every frame - checks, auto-target - and keeps it queued for a short time if the
 * skill isn't ready yet (Const.Controls.SkillQueueTime).
 *
 * Ground-aimed (AoE) skills put the game into aiming mode (client.JobKind.Aiming) until the
 * player confirms. Two ways to finish them:
 *  - auto aim off: the skill is requested (1st activation: aiming starts), then its own key is
 *    pressed once more (2nd activation: the game's own confirm, at the mouse position);
 *  - auto aim on: aiming is skipped; once the skill can be used it is used directly on the point
 *    of the nearest target - client.UnitController.getAutoTarget, the same choice normal skills
 *    get - limited to the skill's range (UnitController.tryUseSkill, what aiming itself ends with).
 *
 * Every macro has its own MacroState, so the three macros never wait for one another.
 */
class GameSkills implements SkillIO {
    static inline var AIM_STEP = 25;            // SkillStep type that makes a skill ground-aimed
    static inline var AIM_CONFIRM_DELAY = 0.08; // aiming visible this long before the confirm press
    static inline var MAX_CAST_WAIT = 6.0;      // a cast longer than this no longer holds the next step
    static inline var PRESS_FRAMES = 2;         // hxd.Key reports a key-down one frame after the event

    /** Name -> kind of every skill picked in the panel (see PickStore). */
    public var picks:Map<String, String> = new Map();
    /** The skills on the bars, refreshed by the mod whenever it reads the HUD. */
    public var hotbar:Array<HotbarSkills.HotbarSkill> = [];
    /** The "AoE skills target nearest enemy" setting. */
    public var aoeAutoAim = false;

    var keys:KeyIO;
    var now = 0.0;
    var states:Array<MacroState> = [for (_ in 0...MacroDefs.MACROS) new MacroState()];
    var releaseCode = -1; // key of the confirm press, released after PRESS_FRAMES frames
    var releaseFrames = 0;

    var queueTimeCache = -1.0;
    var heroCache:Dynamic;
    var heroRefs:Array<SkillRef> = [];

    public function new(keys:KeyIO) this.keys = keys;

    public static function controller():Dynamic {
        try return G.current("client.PlayerController", "inst") catch (_:Dynamic) return null;
    }

    public static function localHero():Dynamic return G.field(controller(), "unit");

    static function enumName(value:Dynamic):String {
        if (value == null) return "";
        try return Type.enumConstructor(value) catch (_:Dynamic) return Std.string(value);
    }

    function state(macroIndex:Int):MacroState {
        while (states.length <= macroIndex) states.push(new MacroState());
        return states[macroIndex];
    }

    /** How long the game keeps a skill request waiting (Const.Controls.SkillQueueTime). */
    function queueTime():Float {
        if (queueTimeCache < 0) {
            queueTimeCache = 0.5;
            try {
                var t = G.number(G.field(G.current("Const", "Controls"), "SkillQueueTime"), -1);
                if (t > 0) queueTimeCache = t;
            } catch (_:Dynamic) {}
        }
        return queueTimeCache;
    }

    function serverNow(ctl:Dynamic):Float return G.number(G.field(G.call("client.UnitController", "get_time", ctl), "serverNow"), -1);

    function known(hero:Dynamic):Array<SkillRef> {
        var list:Array<SkillRef> = [for (h in hotbar) h];
        if (hero != heroCache) { heroCache = hero; heroRefs = HotbarSkills.heroSkills(hero); }
        return list.concat(heroRefs);
    }

    function inputFor(kind:String):String {
        for (h in hotbar) if (h.kind == kind && h.input != "") return h.input;
        return "Skill1";
    }

    /** Forget the cached skill list (new character, respec, weapon swap...). */
    public function invalidate():Void heroCache = null;

    /** Ground-aimed: the same test the game makes before entering aiming (startSkillAim). */
    static function isAimSkill(skill:Dynamic):Bool {
        try {
            if (G.call("st.skill.BaseSkill", "getStepByType", skill, [AIM_STEP]) == null) return false;
            var script = G.field(skill, "script");
            if (script == null) return false;
            var type = hl.Type.getDynamic(script).getTypeName();
            try return G.call(type, "allowAiming", script) == true
            catch (_:Dynamic) return G.call("script.SkillScript", "allowAiming", script) == true;
        } catch (_:Dynamic) return false;
    }

    /** The game's own check before using a skill (cooldown, silence, whether the hero can act): Ok = ready now. */
    public function skillState(hero:Dynamic, value:String):Int {
        if (controller() == null) return Readiness.WAITING;
        if (hero == null) hero = localHero();
        if (hero == null) return Readiness.WAITING;
        try {
            var kind = SkillMatch.kindFor(value, picks, known(hero));
            if (kind == null) return Readiness.MISSING;
            var skill = G.call("ent.GameObject", "getSkill", hero, [kind]);
            if (skill == null || G.field(skill, "removed") == true) return Readiness.MISSING;
            return enumName(G.call("st.skill.Skill", "checkUse", skill, [null])) == "Ok" ? Readiness.READY : Readiness.WAITING;
        } catch (_:Dynamic) {
            return Readiness.WAITING;
        }
    }

    public function useSkill(macroIndex:Int, hero:Dynamic, value:String):Bool {
        var st = state(macroIndex);
        var ctl = controller();
        if (ctl == null) return false;
        if (hero == null) hero = G.field(ctl, "unit");
        var kind = SkillMatch.kindFor(value, picks, known(hero));
        if (kind == null) return false;
        try {
            var skill = G.call("ent.GameObject", "getSkill", hero, [kind]);
            if (skill == null) return false;
            // Still cooling down for longer than the game would keep the request: skip the step.
            var cooldown = G.number(G.call("st.skill.Skill", "getCooldownLeft", skill), 0);
            if (cooldown > queueTime()) return false;
            var input = inputFor(kind);
            st.lastSkill = skill;
            st.lastUsedAt = now;
            if (isAimSkill(skill)) {
                if (aoeAutoAim) {
                    st.autoSkill = skill; st.autoKind = kind; st.autoInput = input;
                    st.autoUntil = now + queueTime() + 0.25;
                    return true;
                }
                startAiming(st, ctl, input, kind);
                return true;
            }
            request(st, ctl, input, kind);
            return true;
        } catch (_:Dynamic) {
            return false;
        }
    }

    function request(st:MacroState, ctl:Dynamic, input:String, kind:String):Void {
        G.call("client.UnitController", "requestSkillKind", ctl, [input, kind]);
        st.requestTime = G.number(G.field(ctl, "requestedSkillTime"), -1);
    }

    /** 1st activation of a ground-aimed skill: the game starts aiming once the skill is ready. */
    function startAiming(st:MacroState, ctl:Dynamic, input:String, kind:String):Void {
        request(st, ctl, input, kind);
        st.aimInput = input;
        st.aimSeenAt = -1;
        st.aimUntil = now + queueTime() + 0.5;
    }

    /** One press of the key bound to a game input, the way the keyboard reports it. */
    function press(input:String):Bool {
        for (name in [input, "AimSkillConfirm"]) {
            try {
                var binding = G.staticCall("lib.Input", "getBinding", [name]);
                var code:Dynamic = G.field(binding, "code");
                if (code == null) continue;
                var c = G.integer(code, -1);
                if (c < 0) continue;
                if (releaseCode >= 0) keys.send(releaseCode, false);
                keys.send(c, true);
                releaseCode = c;
                releaseFrames = PRESS_FRAMES;
                return true;
            } catch (_:Dynamic) {}
        }
        return false;
    }

    /** The nearest target's position as a point target, kept within the skill's range. */
    function pointOn(hero:Dynamic, target:Dynamic, skill:Dynamic):Dynamic {
        var hx = G.number(G.call("ent.Entity", "get_x", hero)), hy = G.number(G.call("ent.Entity", "get_y", hero));
        var tx = G.number(G.call("ent.Entity", "get_x", target)), ty = G.number(G.call("ent.Entity", "get_y", target));
        var tz = G.number(G.call("ent.Entity", "get_z", target));
        var step = G.call("st.skill.BaseSkill", "getStepByType", skill, [AIM_STEP]);
        var range = G.number(G.field(G.field(step, "inf"), "range"), 0);
        var dx = tx - hx, dy = ty - hy;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (range > 0 && dist > range) { tx = hx + dx / dist * range; ty = hy + dy / dist * range; }
        return HlxRuntime.constructEnum(HlxRuntime.resolveType("st.skill.SkillTarget"), "Point", [{x: tx, y: ty, z: tz}]);
    }

    /** Every frame, before the game's own update. */
    public function update(time:Float):Void {
        now = time;
        // hxd.Key sees a key-down only on the frame after the event: releasing it on the very
        // next frame would erase the press before the game reads it.
        if (releaseCode >= 0 && --releaseFrames <= 0) {
            try keys.send(releaseCode, false) catch (_:Dynamic) {}
            releaseCode = -1;
        }
        var ctl = controller();
        for (st in states) {
            if (ctl == null) { st.autoSkill = null; st.aimInput = null; continue; }
            updateAuto(st, ctl);
            updateAim(st, ctl);
        }
    }

    /** Auto aim: once the skill can be used, use it on the nearest target's point. */
    function updateAuto(st:MacroState, ctl:Dynamic):Void {
        if (st.autoSkill == null) return;
        if (now > st.autoUntil) {
            st.autoSkill = null;
            return;
        }
        try {
            if (enumName(G.call("st.skill.Skill", "checkUse", st.autoSkill, [null])) != "Ok") return;
            var target = G.call("client.UnitController", "getAutoTarget", ctl, [null]);
            if (target == null) {
                // Nothing to aim at: aim and confirm at the mouse, like with auto aim off.
                startAiming(st, ctl, st.autoInput, st.autoKind);
            } else {
                G.call("client.UnitController", "tryUseSkill", ctl, [st.autoSkill, pointOn(G.field(ctl, "unit"), target, st.autoSkill)]);
            }
        } catch (_:Dynamic) {}
        st.autoSkill = null;
    }

    /** Auto aim off: the 2nd activation - the skill's key once more, while the game is aiming. */
    function updateAim(st:MacroState, ctl:Dynamic):Void {
        if (st.aimInput == null) return;
        if (enumName(G.field(ctl, "currentJob")) == "Aiming") {
            if (st.aimSeenAt < 0) st.aimSeenAt = now;
            else if (now - st.aimSeenAt >= AIM_CONFIRM_DELAY && releaseCode < 0) {
                press(st.aimInput);
                st.aimInput = null;
                st.confirmUntil = now + 0.3; // the game reads the press over the next frames
            }
        } else if (now > st.aimUntil) st.aimInput = null; // the skill never started aiming
    }

    /** True while this macro's previous step isn't finished: its request is still queued, its
        aiming isn't confirmed yet, or its skill is still casting. */
    public function isBusy(macroIndex:Int):Bool {
        var st = state(macroIndex);
        if (st.autoSkill != null || st.aimInput != null || now < st.confirmUntil) return true;
        var ctl = controller();
        if (ctl == null) return false;
        try {
            if (st.requestTime >= 0 && G.field(ctl, "requestedSkillInput") != null
                && G.number(G.field(ctl, "requestedSkillTime"), -2) == st.requestTime
                && serverNow(ctl) - st.requestTime < queueTime()) return true;
            if (st.lastSkill != null && now - st.lastUsedAt < MAX_CAST_WAIT
                && G.call("st.skill.Skill", "isCasting", st.lastSkill) == true) return true;
        } catch (_:Dynamic) {}
        return false;
    }

}

/** One macro's step in progress. */
private class MacroState {
    public var requestTime = -1.0; // requestedSkillTime of this macro's last request
    public var lastSkill:Dynamic;
    public var lastUsedAt = 0.0;
    // ground-aimed skill waiting for its confirm press (auto aim off)
    public var aimInput:String;
    public var aimUntil = 0.0;
    public var aimSeenAt = -1.0;
    public var confirmUntil = 0.0;
    // ground-aimed skill waiting to be used on the nearest target (auto aim on)
    public var autoSkill:Dynamic;
    public var autoKind:String;
    public var autoInput:String;
    public var autoUntil = 0.0;

    public function new() {}
}
