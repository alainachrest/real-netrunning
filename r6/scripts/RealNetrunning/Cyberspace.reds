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
    private let m_style: Int32;
    private let m_scale: Float;
    // the chosen floor mesh's real size, read from the mesh once it's loaded
    private let m_boundsMin: Vector4;
    private let m_boundsMax: Vector4;
    private let m_boundsStyle: Int32;
    private let m_boundsReady: Bool;
    private let m_meshToken: ref<ResourceToken>;

    public static func Get() -> ref<RNCyberspaceSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(n"RealNetrunning.RNCyberspaceSystem") as RNCyberspaceSystem;
    }

    private func OnAttach() {
        this.m_scale = 1.0;
        this.m_style = 2;
        this.LoadFloorMesh();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Extract", this, n"OnTileExtract")
            .AddTarget(EntityTarget.Template(RNCyberTileTemplate()));
    }

    // Loads the floor mesh so its real size is known before floors spawn.
    private func LoadFloorMesh() {
        this.m_boundsReady = false;
        this.m_boundsStyle = this.m_style;
        this.m_meshToken = GameInstance.GetResourceDepot().LoadResource(RNFloorMesh(this.m_style));
        if IsDefined(this.m_meshToken) {
            this.m_meshToken.RegisterCallback(this, n"OnFloorMeshLoaded");
        }
    }

    private cb func OnFloorMeshLoaded(token: ref<ResourceToken>) {
        let mesh = token.GetResource() as CMesh;
        if IsDefined(mesh) && this.m_boundsStyle == this.m_style {
            this.m_boundsMin = mesh.boundingBox.Min;
            this.m_boundsMax = mesh.boundingBox.Max;
            this.m_boundsReady = true;
        }
    }

    // Lua waits for this before building floors (it gives up after a few seconds).
    public func FloorReady() -> Bool {
        return this.m_boundsReady;
    }

    // For 'cyber debug': the floor mesh's size in metres.
    public func FloorMeshSize() -> String {
        if !this.m_boundsReady {
            return "not loaded";
        }
        return FloatToStringPrec(this.m_boundsMax.X - this.m_boundsMin.X, 2) + " x " +
            FloatToStringPrec(this.m_boundsMax.Y - this.m_boundsMin.Y, 2) + " x " +
            FloatToStringPrec(this.m_boundsMax.Z - this.m_boundsMin.Z, 2);
    }

    // Each floor is one 24 x 24 m platform, 1 m thick, centred on its position:
    // an invisible collider to stand on, with the floor mesh stretched over it.
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
        box.halfExtents = Vector3(RNFloorHalf(), RNFloorHalf(), 0.5);
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

        // What V sees: the chosen floor style ('cyber style' in the deck), fitted
        // to the platform from the mesh's real size when it's known.
        let style = this.m_style;
        let floor = new MeshComponent();
        floor.mesh *= RNFloorMesh(style);
        floor.meshAppearance = n"default";
        let sx = this.m_scale;
        let sy = this.m_scale;
        let sz = 1.0;
        let cx = 0.0;
        let cy = 0.0;
        let top = 0.0;
        if this.m_boundsReady && this.m_boundsStyle == style {
            let width = MaxF(0.1, this.m_boundsMax.X - this.m_boundsMin.X);
            let depth = MaxF(0.1, this.m_boundsMax.Y - this.m_boundsMin.Y);
            sx = RNFloorHalf() * 2.0 / width * this.m_scale;
            sy = RNFloorHalf() * 2.0 / depth * this.m_scale;
            cx = (this.m_boundsMax.X + this.m_boundsMin.X) / 2.0;
            cy = (this.m_boundsMax.Y + this.m_boundsMin.Y) / 2.0;
            top = this.m_boundsMax.Z;
        }
        floor.visualScale = Vector3(sx, sy, sz);
        let place: WorldTransform;
        // centre the mesh on the platform and put its top surface where V walks
        WorldTransform.SetPosition(place, Vector4(-cx * sx, -cy * sy, 0.5 - top * sz, 1.0));
        WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        floor.localTransform = place;
        floor.isEnabled = true;
        template.AddComponent(floor);
    }

    public func CollidersAdded() -> Int32 {
        return this.m_collidersAdded;
    }

    // --- Lua -------------------------------------------------------------------

    // Floor styles: which mesh is drawn on each tile. Takes effect for tiles spawned after.
    public func FloorStyleCount() -> Int32 { return RNFloorStyleCount(); }
    public func FloorStyleName(i: Int32) -> String { return RNFloorName(i); }
    public func GetFloorStyle() -> Int32 { return this.m_style; }
    public func SetFloorStyle(i: Int32) {
        let style = Max(0, Min(i, RNFloorStyleCount() - 1));
        if style != this.m_style || !this.m_boundsReady {
            this.m_style = style;
            this.LoadFloorMesh();
        }
    }
    public func SetFloorScale(scale: Float) {
        this.m_scale = MaxF(0.05, MinF(scale, 20.0));
    }
    public func GetFloorScale() -> Float { return this.m_scale; }

    // Sky presets while jacked in ('cyber sky'). 0 leaves the weather alone.
    public func SkyCount() -> Int32 { return 6; }
    public func SkyName(i: Int32) -> String {
        if i == 1 {
            return "Fog";
        }
        if i == 2 {
            return "Heavy clouds";
        }
        if i == 3 {
            return "Toxic rain";
        }
        if i == 4 {
            return "Pollution";
        }
        if i == 5 {
            return "Deep blue";
        }
        return "Normal weather";
    }
    public func SetSky(i: Int32) -> Bool {
        let weather = GameInstance.GetWeatherSystem(GetGameInstance());
        if !IsDefined(weather) {
            return false;
        }
        if i <= 0 {
            return weather.ResetWeather(true, 3.0);
        }
        let name = n"24h_weather_fog";
        if i == 2 { name = n"24h_weather_heavy_clouds"; }
        if i == 3 { name = n"24h_weather_toxic_rain"; }
        if i == 4 { name = n"24h_weather_pollution"; }
        if i == 5 { name = n"q302_deeb_blue"; }
        return weather.SetWeather(name, 3.0, 9u);
    }

    public func SetJackedIn(on: Bool) {
        this.m_jackedIn = on;
    }

    public func IsJackedIn() -> Bool {
        return this.m_jackedIn;
    }
}

// --- floor styles --------------------------------------------------------------
// Each mesh is measured when it loads and stretched to fit the platform.
// 'cyber scale' still multiplies that, for meshes with a border or overhang.

public func RNFloorStyleCount() -> Int32 { return 6; }

public func RNFloorName(i: Int32) -> String {
    if i == 1 {
        return "Mikoshi prison floor";
    }
    if i == 2 {
        return "Mikoshi prison platform";
    }
    if i == 3 {
        return "Mikoshi square floor";
    }
    if i == 4 {
        return "Cyberspace module";
    }
    if i == 5 {
        return "Relic cyberspace deck";
    }
    return "Arasaka Tower Mikoshi platform";
}

public func RNFloorMesh(i: Int32) -> ResRef {
    if i == 1 {
        return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_floor_a.mesh";
    }
    if i == 2 {
        return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_platform_a.mesh";
    }
    if i == 3 {
        return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_square_deco_floor_a.mesh";
    }
    if i == 4 {
        return r"base\\environment\\architecture\\_temp\\cyberspace\\cyberspace_module_a.mesh";
    }
    if i == 5 {
        return r"base\\environment\\quests\\q101_cyberspace\\q101_cyberspace_deco_a.mesh";
    }
    return r"base\\environment\\architecture\\city_center\\arasaka_tower\\interior\\mikoshi_port\\mikoshi_platform_piece_a.mesh";
}

// Half the width of a floor platform, in metres (matches cyberkit.lua).
public func RNFloorHalf() -> Float {
    return 12.0;
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
