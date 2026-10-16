import macromod.MacroDefs;
import macromod.SettingsText;

/** Regenerates the shipped (English) configFormats.json: haxe -cp src -cp tests -main GenSettings --interp */
class GenSettings {
    static function main():Void sys.io.File.saveContent("configFormats.json", SettingsText.json(false, MacroDefs.MACROS, MacroDefs.STEPS));
}
