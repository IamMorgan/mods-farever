package integrator;

import hlx.runtime.HlxPrefixResult;

/**
 * Integrator: opens a local TCP port (see Server) through which the desktop app reads the game and calls its methods
 * (see Commands). Every game object is reached through HlxRuntime (see GameAccess), never through imported game classes.
 */
@:build(hlx.runtime.Mod.build())
class IntegratorMod {
    static var server:Server;

    static function main():Void {
        Log.t("mod", "Integrator loaded");
        server = new Server();
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        Commands.app = instance;
        try server.poll(Commands.handle) catch (e:Dynamic) Log.t("err", "poll failed: " + Std.string(e));
        return Continue;
    }
}
