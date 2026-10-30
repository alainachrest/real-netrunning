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
        // The preset name alone leaves the collision masks empty (collides with
        // nothing), so build the masks from the preset as well.
        let filter = new physicsFilterData();
        filter.preset = n"World Static";
        let simulation: SimulationFilter;
        SimulationFilter.SimulationFilter_BuildFromPreset(simulation, n"World Static");
        filter.simulationFilter = simulation;
        filter.queryFilter = QueryFilter.ALL();

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

        // What V sees: a Mikoshi platform piece from Arasaka Tower, stretched to
        // the tile. The mesh is 4.44 x 4.69 m and 0.2 m thick, centred at
        // (-0.12, 0, -0.10), so scale it to 8 x 8 m and lift its top to the
        // top of the collider.
        let floor = new MeshComponent();
        floor.mesh *= r"base\\environment\\architecture\\city_center\\arasaka_tower\\interior\\mikoshi_port\\mikoshi_platform_piece_a.mesh";
        floor.meshAppearance = n"default";
        floor.visualScale = Vector3(1.8, 1.707, 1.0);
        let place: WorldTransform;
        WorldTransform.SetPosition(place, Vector4(0.219, 0.0, 0.495, 1.0));
        WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        floor.localTransform = place;
        floor.isEnabled = true;
        template.AddComponent(floor);
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
