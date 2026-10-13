package macromod;

/** Reads and writes the game's own key state (hxd.Key) through HlxRuntime. */
class GameKeys implements KeyIO {
    /** Read keys from Windows itself so macros work while the game window is not focused. */
    public var background = true;

    var keyType:hl.Bytes;
    var eventType:hl.Bytes;
    var kindType:hl.Bytes;
    var pressedMember:hlx.runtime.ResolvedMember;
    var downMember:hlx.runtime.ResolvedMember;
    var onEventMember:hlx.runtime.ResolvedMember;
    var nativeState = 0; // 0 = not probed, 1 = plugin loaded, -1 = plugin missing
    var states:Map<Int, {down:Bool, pressed:Bool}> = new Map();
    var edges = new Edges();

    public function new() {}

    // hlx/plugins/macromod/macro_keys.hdll; "?" keeps the mod loading if the file is missing (returns -1).
    @:hlNative("?macro_keys", "key_down") static function nativeKeyDown(vk:Int):Int return -1;

    function resolve():Bool {
        if (keyType == null) keyType = HlxRuntime.resolveType("hxd.Key");
        if (eventType == null) eventType = HlxRuntime.resolveType("hxd.Event");
        if (kindType == null) kindType = HlxRuntime.resolveType("hxd.EventKind");
        if (keyType == null || eventType == null || kindType == null) return false;
        if (pressedMember == null) pressedMember = HlxRuntime.resolveStaticMember(keyType, "isPressed");
        if (downMember == null) downMember = HlxRuntime.resolveStaticMember(keyType, "isDown");
        if (onEventMember == null) onEventMember = HlxRuntime.resolveStaticMember(keyType, "onEvent");
        return pressedMember != null && downMember != null && onEventMember != null;
    }

    function osKeysAvailable():Bool {
        if (nativeState == 0) nativeState = nativeKeyDown(8) >= 0 ? 1 : -1;
        return nativeState > 0;
    }

    /** Windows virtual-key number for a Heaps key code, or 0 if the key can't be read from Windows. */
    static function virtualKey(code:Int):Int {
        if (code >= 8 && code <= 254) return code; // Heaps keyboard codes follow Windows virtual-key numbers
        return switch code { case 1: 0x02; case 2: 0x04; case 3: 0x05; case 4: 0x06; default: 0; }; // mouse buttons
    }

    function rawDown(code:Int):Bool {
        var vk = virtualKey(code);
        if (background && vk > 0 && osKeysAvailable()) return nativeKeyDown(vk) == 1;
        return resolve() && HlxRuntime.callResolved(downMember, [code]) == true;
    }

    // Modifier values from Better Mod Settings: 0 = Ctrl, 1 = Shift, 2 = Alt.
    static function modifierKey(modifier:Int):Int return switch modifier {
        case 0: 17;
        case 1: 16;
        case 2: 18;
        default: -1;
    };

    static function supportsModifier(code:Int):Bool
        return (code >= 48 && code <= 57) || (code >= 96 && code <= 105) || (code >= 65 && code <= 90)
            || (code >= 112 && code <= 135) || code == 13 || code == 9 || (code >= 37 && code <= 40);

    /** Ctrl+F6 must not also trigger plain F6, so the held modifier has to match exactly. */
    function modifiersMatch(binding:Dynamic, code:Int):Bool {
        if (!supportsModifier(code)) return true;
        var expected:Null<Int> = null;
        if (!Std.isOfType(binding, Int)) {
            var m:Dynamic = Reflect.field(binding, "modifier");
            if (Std.isOfType(m, Int)) expected = m;
        }
        var held:Null<Int> = null;
        for (m in 0...3) if (rawDown(modifierKey(m))) { held = m; break; }
        return held == expected;
    }

    function sample(code:Int):{down:Bool, pressed:Bool} {
        var down = rawDown(code);
        // Only our own down-transition counts. hxd.Key.isPressed is not used: it can fire again on
        // every OS key-repeat while the key is held, which made Toggle macros switch on and off.
        return {down: down, pressed: edges.pressed(code, down, haxe.Timer.stamp())};
    }

    public function beginFrame(hotkeys:Array<Dynamic>):Void {
        states = new Map();
        for (binding in hotkeys) {
            var code = MacroDefs.keyCode(binding);
            if (code > 0 && !states.exists(code)) states.set(code, sample(code));
        }
    }

    function state(code:Int):{down:Bool, pressed:Bool} {
        var s = states.get(code);
        if (s == null) { s = sample(code); states.set(code, s); }
        return s;
    }

    public function isPressed(binding:Dynamic):Bool {
        var code = MacroDefs.keyCode(binding);
        return code > 0 && state(code).pressed && modifiersMatch(binding, code);
    }

    public function isDown(binding:Dynamic):Bool {
        var code = MacroDefs.keyCode(binding);
        return code > 0 && state(code).down;
    }

    /** The same call the game's window makes for a real key: it updates hxd.Key's state. */
    public function send(code:Int, down:Bool):Void {
        if (!resolve()) return;
        var kind = HlxRuntime.resolveStaticField(kindType, down ? "EKeyDown" : "EKeyUp");
        var event = HlxRuntime.constructInstanceByName(eventType, 3, [kind, 0.0, 0.0]);
        HlxRuntime.setField(event, "keyCode", code);
        HlxRuntime.callResolved(onEventMember, [event]);
    }
}
