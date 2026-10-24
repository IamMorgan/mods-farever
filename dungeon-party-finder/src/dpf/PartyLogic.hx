package dpf;

/** Where the dungeon lobby of the party is, as far as the window cares. */
enum LobbyPhase {
    /** No lobby (yet), or it does not have me. */
    Missing;
    Waiting;
    AllReady;
    /** The leader pressed start; the game counts down. */
    Delay;
    Starting;
}

enum ButtonKind {
    /** Nothing to press: waiting for the lobby. */
    Wait;
    /** The leader's start button (enabled once everyone is ready). */
    Start(enabled:Bool);
    /** The leader called the start off. */
    CancelStart;
    /** A member's ready button; `on` while they are ready. */
    Ready(on:Bool);
    Loading;
}

class PartyLogic {
    public static function button(leader:Bool, phase:LobbyPhase, allReady:Bool, myReady:Bool):ButtonKind
        return switch phase {
            case Missing: Wait;
            case Starting: Loading;
            case Delay: leader ? CancelStart : Loading;
            case Waiting | AllReady: leader ? Start(allReady) : Ready(myReady);
        };

    /** The phase from the lobby's state name (InstanceInfoState: WaitPlayers, AllPlayersReady, DelayStarting(t), Starting). */
    public static function phaseOf(stateName:String, hasLobby:Bool):LobbyPhase {
        if (!hasLobby) return Missing;
        if (stateName == null) return Waiting;
        if (StringTools.startsWith(stateName, "DelayStarting")) return Delay;
        if (StringTools.startsWith(stateName, "Starting")) return Starting;
        if (StringTools.startsWith(stateName, "AllPlayersReady")) return AllReady;
        return Waiting;
    }

    /** A reason of the game (EReason) counts as success when it is the plain Ok. */
    public static function isOk(reasonName:String):Bool return reasonName == null || reasonName == "Ok";
}
