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
}
