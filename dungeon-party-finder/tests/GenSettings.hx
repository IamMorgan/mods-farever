import dpf.SettingsText;

/** Regenerates the shipped (English) configFormats.json: haxe -cp src -cp tests -main GenSettings --interp */
class GenSettings {
    static function main():Void sys.io.File.saveContent("configFormats.json", SettingsText.json());
}
