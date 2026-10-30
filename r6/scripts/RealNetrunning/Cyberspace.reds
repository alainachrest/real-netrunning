// -----------------------------------------------------------------------------
// Real Netrunning - cyberspace support
// -----------------------------------------------------------------------------
//
// Cyberspace itself is built and run by the Lua mod (modules/cyberspace.lua).
// This file does the two things only redscript can:
//
//  * Floor tiles. Lua spawns the game's own empty entity template as invisible
//    floor tiles; when one is built, a static box collider is added to it, so
//    V can walk on cyberspace floors whatever meshes are drawn on top.
//  * Saving. Manual and quick saves are blocked while V is jacked in.

module RealNetrunning

public func RNCyberTileTemplate() -> ResRef {
    return r"base\\quest\\main_quests\\part1\\q115\\test\\empty_entity.ent";
}

public class RNCyberspaceSystem extends ScriptableSystem {
    private let m_jackedIn: Bool;
    private let m_collidersAdded: Int32;

    public static func Get() -> ref<RNCyberspaceSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(n"RealNetrunning.RNCyberspaceSystem") as RNCyberspaceSystem;
    }

    private func OnAttach() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Extract", this, n"OnTileExtract")
            .AddTarget(EntityTarget.Template(RNCyberTileTemplate()));
    }

    // Every floor tile is 8 x 8 metres and 1 metre thick, centred on its position.
    private cb func OnTileExtract(event: ref<EntityBuilderEvent>) {
        let builder = event.GetEntityBuilder();
        if !IsDefined(builder) {
            return;
        }
        let template = builder.GetTemplate();
        if !IsDefined(template) {
            return;
        }
        let filter = new physicsFilterData();
        filter.preset = n"World Static";

        let box = new physicsColliderBox();
        box.halfExtents = Vector3(4.0, 4.0, 0.5);
        box.filterData = filter;
        let shapes: array<ref<physicsICollider>>;
        ArrayPush(shapes, box);

        let collider = new ColliderComponent();
        collider.colliders = shapes;
        collider.simulationType = physicsSimulationType.Static;
        collider.filterData = filter;
        collider.isEnabled = true;
        template.AddComponent(collider);
        this.m_collidersAdded += 1;
    }

    public func CollidersAdded() -> Int32 {
        return this.m_collidersAdded;
    }

    // --- Lua -------------------------------------------------------------------

    public func SetJackedIn(on: Bool) {
        this.m_jackedIn = on;
    }

    public func IsJackedIn() -> Bool {
        return this.m_jackedIn;
    }
}

public func RNSavingBlocked() -> Bool {
    let system = RNCyberspaceSystem.Get();
    return IsDefined(system) && system.IsJackedIn();
}

// --- no saving while jacked in -----------------------------------------------

@wrapMethod(PauseMenuGameController)
private func HandlePressToSaveGame(target: wref<inkWidget>) {
    if RNSavingBlocked() {
        this.PlaySound(n"Button", n"OnPress");
        GameInstance.GetActivityLogSystem(GetGameInstance()).AddLog("Jack out of cyberspace before saving.");
        return;
    }
    wrappedMethod(target);
}

@wrapMethod(PauseMenuGameController)
private func HandlePressToQuickSaveGame() {
    if RNSavingBlocked() {
        this.PlaySound(n"Button", n"OnPress");
        GameInstance.GetActivityLogSystem(GetGameInstance()).AddLog("Jack out of cyberspace before saving.");
        return;
    }
    wrappedMethod();
}

@wrapMethod(gameuiInGameMenuGameController)
private func HandleQuickSave() {
    if RNSavingBlocked() {
        GameInstance.GetActivityLogSystem(GetGameInstance()).AddLog("Jack out of cyberspace before saving.");
        return;
    }
    wrappedMethod();
}
