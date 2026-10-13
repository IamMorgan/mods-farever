package macromod;

/** What the sequencer needs from the game: hotkey state and key injection. */
interface KeyIO {
    /** Called once per frame with every macro's activation binding, before isPressed/isDown. */
    function beginFrame(hotkeys:Array<Dynamic>):Void;
    /** True only on the frame the binding (key + optional modifier) went down. */
    function isPressed(binding:Dynamic):Bool;
    /** True while the binding is held. */
    function isDown(binding:Dynamic):Bool;
    /** Send a key-down or key-up to the game's input state. */
    function send(code:Int, down:Bool):Void;
}
