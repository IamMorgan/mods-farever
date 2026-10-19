package macromod;

/**
 * The Better Mod Settings page (configFormats.json) and the mod's own texts in the client's
 * language. BMS re-reads that file every time the settings window opens, so the mod writes it once
 * the game's language is known (see MacroMod.localizeSettings). The English page is also the one
 * shipped in the archive; tests/GenSettings.hx regenerates it.
 */
class SettingsText {
    /** Dropdown values of a macro's mode, per language (index 0 = toggle, 1 = hold). */
    public static function modes(russian:Bool):Array<String>
        return russian ? ["Нажатие (вкл/выкл)", "Удержание"] : ["Press (Toggle)", "Hold"];

    /** The mode index of a stored dropdown value, whatever language it was saved in. */
    public static function modeIndex(value:Dynamic):Int {
        for (russian in [false, true]) {
            var index = modes(russian).indexOf(Std.string(value));
            if (index >= 0) return index;
        }
        return 0;
    }

    public static function isRussian(language:String):Bool
        return language != null && StringTools.startsWith(language.toLowerCase(), "ru");

    /** Row labels the mod looks for on screen; unique per macro, so each row is found exactly. */
    public static function keyLabel(m:Int, russian:Bool):String
        return russian ? "М" + m + ": клавиша запуска" : "M" + m + " Activation Key";

    public static function stepLabel(m:Int, s:Int, russian:Bool):String
        return russian ? "М" + m + ": шаг " + s : "M" + m + " Step " + s;

    public static function pickerTitle(m:Int, s:Int, russian:Bool):String
        return russian ? "Выберите скилл для шага " + s + " макроса М" + m : "Choose a skill for M" + m + " Step " + s;

    public static function noSkills(russian:Bool):String
        return russian ? "На панелях действий нет скиллов." : "No skills found on your action bars.";

    public static function cancel(russian:Bool):String return russian ? "Отмена" : "Cancel";

    // --- Rotation window (drawn by the mod itself, see RotationWindow) ---

    public static function rotationsTitle(russian:Bool):String return russian ? "Ротации" : "Rotations";
    public static function rotationNew(russian:Bool):String return russian ? "Новая" : "New";
    public static function rotationRepeat(russian:Bool):String return russian ? "Повторять" : "Repeat";
    public static function rotationKey(russian:Bool):String return russian ? "Клавиша:" : "Key:";
    public static function rotationKeyNotSet(russian:Bool):String return russian ? "Не задана" : "Not set";
    public static function rotationPressKey(russian:Bool):String return russian ? "Нажмите клавишу..." : "Press a key...";
    public static function rotationDelete(russian:Bool):String return russian ? "Удалить" : "Delete";
    public static function rotationClose(russian:Bool):String return russian ? "Закрыть" : "Close";
    public static function rotationEmpty(russian:Bool):String
        return russian ? "Ротаций пока нет. Нажмите «Новая»." : "No rotations yet. Click \"New\".";
    public static function rotationHint(russian:Bool):String
        return russian ? "Нажмите на ячейку, чтобы выбрать скилл. Правая кнопка или красный крестик очищают ячейку. Колесо мыши листает список."
            : "Click a cell to pick a skill. Right-click or the red X clears a cell. The mouse wheel scrolls the list.";
    public static function rotationPickerTitle(number:Int, cell:Int, russian:Bool):String
        return russian ? "Скилл для ячейки " + cell + " ротации " + number : "Skill for cell " + cell + " of rotation " + number;
    public static function rotationPage(from:Int, to:Int, total:Int):String return from + "-" + to + " / " + total;

    /** The window's note when a key is already used: by another rotation or by one of the macros. */
    public static function rotationKeyTaken(isMacro:Bool, number:Int, russian:Bool):String
        return russian ? "Эта клавиша уже занята: " + (isMacro ? "макрос " : "ротация ") + number + ". Выберите другую."
            : "That key is already used by " + (isMacro ? "macro " : "rotation ") + number + ". Choose another one.";

    public static function build(russian:Bool, macros:Int, steps:Int):Dynamic {
        inline function t(en:String, ru:String):String return russian ? ru : en;
        var configs:Array<Dynamic> = [];
        configs.push({type: "title", label: t("General", "Общие")});
        configs.push({key: "notWhileRunning", type: "checkbox",
            label: t("Don't use while running (pause macros while moving: W/A/S/D held)",
                "Не использовать на бегу (макросы ждут, пока зажаты W/A/S/D)")});
        configs.push({key: "aoeNearestTarget", type: "checkbox",
            label: t("AoE skills aim at the nearest enemy (same target as a normal skill). Off: aim at the mouse, then confirm",
                "AoE-скиллы бьют по ближайшему врагу (та же цель, что у обычного скилла). Выкл.: прицел по мыши, затем подтверждение")});
        configs.push({key: "combatOnly", type: "checkbox",
            label: t("Active only in combat (a started macro plays only while your character is in combat and waits outside it)",
                "Активно только в бою (запущенный макрос воспроизводится только в бою, вне боя ждёт)")});
        configs.push({key: "rotations_open", type: "button",
            label: t("Rotations: skills used in turn, each as soon as it is ready (opens the rotation window)",
                "Ротации: скиллы по очереди, каждый как только будет готов (открывает окно ротаций)"),
            buttonText: t("Rotations", "Ротации")});
        for (m in 1...macros + 1) {
            configs.push({type: "title", label: t("Macro " + m, "Макрос " + m)});
            configs.push({key: "m" + m + "_name", type: "text", label: t("Name", "Название"), placeholder: t("Rotation " + m, "Ротация " + m)});
            configs.push({key: "m" + m + "_hotkey", type: "keybinding", label: keyLabel(m, russian), modifiers: true});
            configs.push({key: "m" + m + "_mode", type: "dropdown", label: t("Mode", "Режим"), options: modes(russian)});
            configs.push({key: "m" + m + "_repeat", type: "checkbox", label: t("Repeat in loop", "Повторять по кругу")});
            configs.push({type: "title", label: t("Macro " + m + " - Steps", "Макрос " + m + " — шаги")});
            for (s in 1...steps + 1) {
                var prefix = "m" + m + "_s" + s;
                configs.push({key: prefix + "_skill", type: "text", label: stepLabel(m, s, russian),
                    placeholder: t("(click Choose below)", "(нажмите «Выбрать» ниже)")});
                configs.push({key: prefix + "_pick", type: "button", label: t("Pick a skill from your action bars", "Выбрать скилл с панелей действий"),
                    buttonText: t("Choose", "Выбрать")});
                configs.push({key: prefix + "_delay", type: "slider",
                    label: t("M" + m + " Step " + s + " Delay (ms)", "М" + m + ": задержка после шага " + s + " (мс)"), min: 60, max: 5000, step: 10});
            }
        }
        return {schemaVersion: 1, displayName: t("Farever Macros", "Farever Макросы"), configs: configs};
    }

    public static function json(russian:Bool, macros:Int, steps:Int):String
        return haxe.Json.stringify(build(russian, macros, steps), null, "  ");
}
