// -----------------------------------------------------------------------------
// Real Netrunning - cyberspace support
// -----------------------------------------------------------------------------
//
// Cyberspace itself is built and run by the Lua mod (modules/cyberspace.lua).
// This file does what only redscript can:
//
//  * Blocks. Lua asks for floor slabs, walls and door barriers of any size.
//    Each is the game's own empty entity with a static box collider (so V can
//    stand on it and can't walk through it) and one of the game's cyberspace
//    meshes, measured when it loads and stretched to fit the box.
//  * The sky while jacked in.
//  * Saving: manual and quick saves are blocked while V is jacked in.

module RealNetrunning

public func RNCyberTileTemplate() -> ResRef {
    return r"base\\quest\\main_quests\\part1\\q115\\test\\empty_entity.ent";
}

// One loaded mesh and its real size.
public class RNMeshFit {
    public let style: Int32;
    public let ready: Bool;
    public let min: Vector4;
    public let max: Vector4;
    public let token: ref<ResourceToken>;
}

public class RNCyberspaceSystem extends ScriptableSystem {
    private let m_jackedIn: Bool;
    private let m_collidersAdded: Int32;
    private let m_style: Int32;      // floor mesh
    private let m_wallStyle: Int32;  // wall mesh
    private let m_scale: Float;
    private let m_floorFit: ref<RNMeshFit>;
    private let m_wallFit: ref<RNMeshFit>;

    // the size and kind of each block Lua asked for, looked up when it's built
    private let m_pending: Vector4;  // half x, half y, half z, kind
    private let m_blockIDs: array<EntityID>;
    private let m_blockSizes: array<Vector4>;

    public static func Get() -> ref<RNCyberspaceSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(n"RealNetrunning.RNCyberspaceSystem") as RNCyberspaceSystem;
    }

    private func OnAttach() {
        this.m_scale = 1.0;
        this.m_style = 2;
        this.m_wallStyle = 0;
        this.m_pending = Vector4(12.0, 12.0, 0.5, 0.0);
        this.m_floorFit = this.LoadFit(RNFloorMesh(this.m_style), this.m_style, n"OnFloorMeshLoaded");
        this.m_wallFit = this.LoadFit(RNWallMesh(this.m_wallStyle), this.m_wallStyle, n"OnWallMeshLoaded");
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Extract", this, n"OnBlockExtract")
            .AddTarget(EntityTarget.Template(RNCyberTileTemplate()));
    }

    // --- meshes ------------------------------------------------------------------

    private func LoadFit(path: ResRef, style: Int32, callback: CName) -> ref<RNMeshFit> {
        let fit = new RNMeshFit();
        fit.style = style;
        fit.token = GameInstance.GetResourceDepot().LoadResource(path);
        if IsDefined(fit.token) {
            fit.token.RegisterCallback(this, callback);
        }
        return fit;
    }

    private func Fill(fit: ref<RNMeshFit>, token: ref<ResourceToken>) {
        let mesh = token.GetResource() as CMesh;
        if IsDefined(fit) && IsDefined(mesh) {
            fit.min = mesh.boundingBox.Min;
            fit.max = mesh.boundingBox.Max;
            fit.ready = true;
        }
    }

    private cb func OnFloorMeshLoaded(token: ref<ResourceToken>) {
        if IsDefined(this.m_floorFit) && this.m_floorFit.style == this.m_style {
            this.Fill(this.m_floorFit, token);
        }
    }

    private cb func OnWallMeshLoaded(token: ref<ResourceToken>) {
        if IsDefined(this.m_wallFit) && this.m_wallFit.style == this.m_wallStyle {
            this.Fill(this.m_wallFit, token);
        }
    }

    // Lua waits for this before building (it gives up after a few seconds).
    public func FloorReady() -> Bool {
        return IsDefined(this.m_floorFit) && this.m_floorFit.ready && IsDefined(this.m_wallFit) && this.m_wallFit.ready;
    }

    private func SizeText(fit: ref<RNMeshFit>) -> String {
        if !IsDefined(fit) || !fit.ready {
            return "not loaded";
        }
        return FloatToStringPrec(fit.max.X - fit.min.X, 2) + " x " +
            FloatToStringPrec(fit.max.Y - fit.min.Y, 2) + " x " +
            FloatToStringPrec(fit.max.Z - fit.min.Z, 2);
    }

    // For 'cyber debug'.
    public func FloorMeshSize() -> String {
        return "floor " + this.SizeText(this.m_floorFit) + ", wall " + this.SizeText(this.m_wallFit);
    }

    // --- blocks --------------------------------------------------------------------

    // kind 0: floor slab (its mesh's top is the top of the box)
    // kind 1: wall or door barrier (its mesh fills the box)
    public func SpawnBlock(x: Float, y: Float, z: Float, yaw: Float, hx: Float, hy: Float, hz: Float, kind: Int32) -> EntityID {
        this.m_pending = Vector4(hx, hy, hz, Cast<Float>(kind));
        let rotation: EulerAngles;
        rotation.Yaw = yaw;
        let spec = new StaticEntitySpec();
        spec.templatePath = RNCyberTileTemplate();
        spec.position = Vector4(x, y, z, 1.0);
        spec.orientation = EulerAngles.ToQuat(rotation);
        spec.attached = true;
        let id = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
        ArrayPush(this.m_blockIDs, id);
        ArrayPush(this.m_blockSizes, this.m_pending);
        return id;
    }

    // Lua calls this on jack-out, so the size list doesn't grow forever.
    public func ForgetBlocks() {
        ArrayClear(this.m_blockIDs);
        ArrayClear(this.m_blockSizes);
    }

    private func SizeOf(id: EntityID) -> Vector4 {
        let i = ArraySize(this.m_blockIDs) - 1;
        while i >= 0 {
            if Equals(this.m_blockIDs[i], id) {
                return this.m_blockSizes[i];
            }
            i -= 1;
        }
        // built before SpawnBlock returned: it's the block being spawned right now
        return this.m_pending;
    }

    private cb func OnBlockExtract(event: ref<EntityBuilderEvent>) {
        let builder = event.GetEntityBuilder();
        if !IsDefined(builder) {
            return;
        }
        let template = builder.GetTemplate();
        if !IsDefined(template) {
            return;
        }
        let size = this.SizeOf(builder.GetEntityID());
        let kind = RoundF(size.W);

        // The preset name alone leaves the collision masks empty (collides with
        // nothing), so build the masks from the preset as well.
        let filter = new physicsFilterData();
        filter.preset = n"World Static";
        let simulation: SimulationFilter;
        SimulationFilter.SimulationFilter_BuildFromPreset(simulation, n"World Static");
        filter.simulationFilter = simulation;
        filter.queryFilter = QueryFilter.ALL();

        let box = new physicsColliderBox();
        box.halfExtents = Vector3(size.X, size.Y, size.Z);
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

        // What V sees: the chosen mesh, stretched to the box.
        let fit = kind == 1 ? this.m_wallFit : this.m_floorFit;
        let visual = new MeshComponent();
        let path = RNFloorMesh(this.m_style);
        if kind == 1 {
            path = RNWallMesh(this.m_wallStyle);
        }
        visual.mesh *= path;
        visual.meshAppearance = n"default";
        let sx = 1.0;
        let sy = 1.0;
        let sz = 1.0;
        let cx = 0.0;
        let cy = 0.0;
        let cz = 0.0;
        let offsetZ = 0.0;
        if IsDefined(fit) && fit.ready {
            sx = size.X * 2.0 / MaxF(0.1, fit.max.X - fit.min.X);
            sy = size.Y * 2.0 / MaxF(0.1, fit.max.Y - fit.min.Y);
            cx = (fit.max.X + fit.min.X) / 2.0;
            cy = (fit.max.Y + fit.min.Y) / 2.0;
            if kind == 1 {
                sz = size.Z * 2.0 / MaxF(0.1, fit.max.Z - fit.min.Z);
                cz = (fit.max.Z + fit.min.Z) / 2.0;
            } else {
                // floors keep their own thickness; the top goes where V walks
                cz = fit.max.Z;
                offsetZ = size.Z;
            }
        }
        if kind == 0 {
            sx = sx * this.m_scale;
            sy = sy * this.m_scale;
        }
        visual.visualScale = Vector3(sx, sy, sz);
        let place: WorldTransform;
        WorldTransform.SetPosition(place, Vector4(-cx * sx, -cy * sy, offsetZ - cz * sz, 1.0));
        WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        visual.localTransform = place;
        visual.isEnabled = true;
        template.AddComponent(visual);
    }

    public func CollidersAdded() -> Int32 {
        return this.m_collidersAdded;
    }

    // --- look, from Lua ----------------------------------------------------------------

    public func FloorStyleCount() -> Int32 { return RNFloorStyleCount(); }
    public func FloorStyleName(i: Int32) -> String { return RNFloorName(i); }
    public func GetFloorStyle() -> Int32 { return this.m_style; }
    public func SetFloorStyle(i: Int32) {
        let style = Max(0, Min(i, RNFloorStyleCount() - 1));
        if style != this.m_style || !IsDefined(this.m_floorFit) || !this.m_floorFit.ready {
            this.m_style = style;
            this.m_floorFit = this.LoadFit(RNFloorMesh(style), style, n"OnFloorMeshLoaded");
        }
    }

    public func WallStyleCount() -> Int32 { return RNWallStyleCount(); }
    public func WallStyleName(i: Int32) -> String { return RNWallName(i); }
    public func SetWallStyle(i: Int32) {
        let style = Max(0, Min(i, RNWallStyleCount() - 1));
        if style != this.m_wallStyle || !IsDefined(this.m_wallFit) || !this.m_wallFit.ready {
            this.m_wallStyle = style;
            this.m_wallFit = this.LoadFit(RNWallMesh(style), style, n"OnWallMeshLoaded");
        }
    }

    public func SetFloorScale(scale: Float) {
        this.m_scale = MaxF(0.05, MinF(scale, 20.0));
    }
    public func GetFloorScale() -> Float { return this.m_scale; }

    // Sky presets while jacked in ('cyber sky'). 0 puts the normal weather back.
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

// --- floor and wall styles -------------------------------------------------------
// Every mesh is measured when it loads and stretched to fit its block.

public func RNFloorStyleCount() -> Int32 { return 6; }

public func RNFloorName(i: Int32) -> String {
    if i == 1 { return "Mikoshi prison floor"; }
    if i == 2 { return "Mikoshi prison platform"; }
    if i == 3 { return "Mikoshi square floor"; }
    if i == 4 { return "Cyberspace module"; }
    if i == 5 { return "Relic cyberspace deck"; }
    return "Arasaka Tower Mikoshi platform";
}

public func RNFloorMesh(i: Int32) -> ResRef {
    if i == 1 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_floor_a.mesh"; }
    if i == 2 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_platform_a.mesh"; }
    if i == 3 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_square_deco_floor_a.mesh"; }
    if i == 4 { return r"base\\environment\\architecture\\_temp\\cyberspace\\cyberspace_module_a.mesh"; }
    if i == 5 { return r"base\\environment\\quests\\q101_cyberspace\\q101_cyberspace_deco_a.mesh"; }
    return r"base\\environment\\architecture\\city_center\\arasaka_tower\\interior\\mikoshi_port\\mikoshi_platform_piece_a.mesh";
}

public func RNWallStyleCount() -> Int32 { return 6; }

public func RNWallName(i: Int32) -> String {
    if i == 1 { return "Mikoshi prison wall B"; }
    if i == 2 { return "Mikoshi prison wall C"; }
    if i == 3 { return "Mikoshi cyberspace wall"; }
    if i == 4 { return "Mikoshi frontier wall"; }
    if i == 5 { return "Mikoshi deco wall"; }
    return "Mikoshi prison wall A";
}

public func RNWallMesh(i: Int32) -> ResRef {
    if i == 1 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_wall_b.mesh"; }
    if i == 2 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_wall_c.mesh"; }
    if i == 3 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_wall.mesh"; }
    if i == 4 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_wall_frontier_a.mesh"; }
    if i == 5 { return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_deco_wall.mesh"; }
    return r"base\\environment\\quests\\q116_mikoshi_cyberspace\\mikoshi_cs_prison_archi_wall_a.mesh";
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
