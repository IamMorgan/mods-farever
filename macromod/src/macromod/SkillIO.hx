package macromod;

/** What the sequencer needs to use a skill. `macroIndex` is the macro's index: each macro's progress
    is tracked on its own, so the three macros never wait for one another. */
interface SkillIO {
    /** Requests the skill a step names (display name, or an id from older configs). False if
        nothing could be requested. */
    function useSkill(macroIndex:Int, hero:Dynamic, skill:String):Bool;
    /** True while this macro's previous step isn't finished (request still queued, aiming not
        confirmed, skill still casting); its next step waits instead of cutting it off. */
    function isBusy(macroIndex:Int):Bool;
    /** Whether a rotation may use the skill now: Readiness.READY, WAITING (cooldown, silence, ...)
        or MISSING (the hero has no such skill: the rotation skips it). */
    function skillState(hero:Dynamic, skill:String):Int;
    /** True once the game has started using the skill this macro / rotation requested last (it was seen
        casting or not ready any more): skills without a cooldown, like basic attacks, are told by this. */
    function wasUsed(macroIndex:Int):Bool;
}

/** Answers of SkillIO.skillState. */
class Readiness {
    public static inline var MISSING = 0;
    public static inline var READY = 1;
    public static inline var WAITING = 2;
}
