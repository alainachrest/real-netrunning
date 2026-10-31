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
    public let appearances: String; // the mesh's appearance names, for 'cyber debug'
    public let names: array<CName>;
}

// The first of a mesh's appearances whose name contains `part` (e.g. "gold"),
// or "default" when it has none.
public func RNFindAppearance(fit: ref<RNMeshFit>, part: String) -> CName {
    if IsDefined(fit) && StrLen(part) > 0 {
        for name in fit.names {
            if StrFindFirst(StrLower(NameToString(name)), StrLower(part)) >= 0 {
                return name;
            }
        }
    }
    return n"default";
}

public class RNCyberspaceSystem extends ScriptableSystem {
    private let m_jackedIn: Bool;
    private let m_collidersAdded: Int32;
    private let m_style: Int32;      // floor mesh
    private let m_wallStyle: Int32;  // wall mesh
    private let m_scale: Float;
    private let m_floorFit: ref<RNMeshFit>;
    private let m_wallFit: ref<RNMeshFit>;
    private let m_backFit: ref<RNMeshFit>;   // solid backing behind floors and ceilings
    private let m_lightLevel: Float;   // 'cyber light': brightness multiplier
    private let m_lightColour: Int32;  // 'cyber light': colour preset
    private let m_markerFits: array<ref<RNMeshFit>>; // one per marker mesh (see RNMarkerMesh)
    private let m_hooks: ref<RNEntityHooks>;          // Lua adds particles from here (Hooks.reds)

    // the size and kind of each block Lua asked for, looked up when it's built
    private let m_pending: Vector4;  // half x, half y, half z, kind
    private let m_blockIDs: array<EntityID>;
    private let m_blockSizes: array<Vector4>;

    // what the scanner calls the NPCs Lua spawned (see the NPCPuppet wrap below)
    private let m_scanIDs: array<EntityID>;
    private let m_scanNames: array<String>;
    private let m_scanFactions: array<String>;

    public static func Get() -> ref<RNCyberspaceSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(n"RealNetrunning.RNCyberspaceSystem") as RNCyberspaceSystem;
    }

    private func OnAttach() {
        this.m_scale = 1.3;
        this.m_style = 2;
        this.m_wallStyle = 3;
        this.m_lightLevel = 0.8;
        this.m_lightColour = 1;
        this.m_pending = Vector4(12.0, 12.0, 0.5, 0.0);
        this.m_floorFit = this.LoadFit(RNFloorMesh(this.m_style), this.m_style, n"OnFloorMeshLoaded");
        this.m_wallFit = this.LoadFit(RNWallMesh(this.m_wallStyle), this.m_wallStyle, n"OnWallMeshLoaded");
        this.m_backFit = this.LoadFit(RNBackingMesh(), 0, n"OnBackingMeshLoaded");
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(0), 0, n"OnMarker0Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(1), 1, n"OnMarker1Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(2), 2, n"OnMarker2Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(3), 3, n"OnMarker3Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(4), 4, n"OnMarker4Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(5), 5, n"OnMarker5Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(6), 6, n"OnMarker6Loaded"));
        ArrayPush(this.m_markerFits, this.LoadFit(RNMarkerMesh(7), 7, n"OnMarker7Loaded"));
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Extract", this, n"OnBlockExtract")
            .AddTarget(EntityTarget.Template(RNCyberTileTemplate()));
        this.m_hooks = new RNEntityHooks();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Initialize", this.m_hooks, n"OnEntityInitialize")
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
            let names = "";
            for appearance in mesh.appearances {
                if IsDefined(appearance) {
                    names += (StrLen(names) > 0 ? ", " : "") + NameToString(appearance.name);
                    ArrayPush(fit.names, appearance.name);
                }
            }
            fit.appearances = names;
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

    private cb func OnBackingMeshLoaded(token: ref<ResourceToken>) {
        this.Fill(this.m_backFit, token);
    }

    private func FillMarker(i: Int32, token: ref<ResourceToken>) {
        if i < ArraySize(this.m_markerFits) {
            this.Fill(this.m_markerFits[i], token);
        }
    }
    private cb func OnMarker0Loaded(token: ref<ResourceToken>) { this.FillMarker(0, token); }
    private cb func OnMarker1Loaded(token: ref<ResourceToken>) { this.FillMarker(1, token); }
    private cb func OnMarker2Loaded(token: ref<ResourceToken>) { this.FillMarker(2, token); }
    private cb func OnMarker3Loaded(token: ref<ResourceToken>) { this.FillMarker(3, token); }
    private cb func OnMarker4Loaded(token: ref<ResourceToken>) { this.FillMarker(4, token); }
    private cb func OnMarker5Loaded(token: ref<ResourceToken>) { this.FillMarker(5, token); }
    private cb func OnMarker6Loaded(token: ref<ResourceToken>) { this.FillMarker(6, token); }
    private cb func OnMarker7Loaded(token: ref<ResourceToken>) { this.FillMarker(7, token); }

    // Lua waits for this before building (it gives up after a few seconds).
    public func FloorReady() -> Bool {
        return IsDefined(this.m_floorFit) && this.m_floorFit.ready && IsDefined(this.m_wallFit) && this.m_wallFit.ready
            && IsDefined(this.m_backFit) && this.m_backFit.ready;
    }

    // A mesh stretched to fill a box (half extents hx, hy, hz) centred at (x, y, z) in the entity.
    private func FitMesh(template: ref<EntityBuilderTemplateWrapper>, fit: ref<RNMeshFit>, path: ResRef,
                         x: Float, y: Float, z: Float, hx: Float, hy: Float, hz: Float) {
        if !IsDefined(fit) || !fit.ready {
            return;
        }
        let sx = hx * 2.0 / MaxF(0.01, fit.max.X - fit.min.X);
        let sy = hy * 2.0 / MaxF(0.01, fit.max.Y - fit.min.Y);
        let sz = hz * 2.0 / MaxF(0.01, fit.max.Z - fit.min.Z);
        let cx = (fit.max.X + fit.min.X) / 2.0;
        let cy = (fit.max.Y + fit.min.Y) / 2.0;
        let cz = (fit.max.Z + fit.min.Z) / 2.0;
        let mesh = new MeshComponent();
        mesh.mesh *= path;
        mesh.meshAppearance = n"default";
        mesh.visualScale = Vector3(sx, sy, sz);
        let place: WorldTransform;
        WorldTransform.SetPosition(place, Vector4(x - cx * sx, y - cy * sy, z - cz * sz, 1.0));
        WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        mesh.localTransform = place;
        mesh.isEnabled = true;
        template.AddComponent(mesh);
    }

    // Lights that fill a room of the given half width with soft colour: a main
    // light under the ceiling and a softer fill light near the floor.
    private func AddLight(template: ref<EntityBuilderTemplateWrapper>, half: Float) {
        template.AddComponent(this.MakeLight(half * 2.2, 9000.0, 0.0));
        template.AddComponent(this.MakeLight(half * 1.8, 3000.0, -4.0));
    }

    private func MakeLight(radius: Float, lumens: Float, z: Float) -> ref<LightComponent> {
        return this.MakeColouredLight(RNLightColour(this.m_lightColour), radius, lumens, z);
    }

    private func MakeColouredLight(colour: Color, radius: Float, lumens: Float, z: Float) -> ref<LightComponent> {
        // the plain light component is always on (the game's gameLightComponent
        // starts switched off and waits to be turned on, like a lamp)
        let light = new LightComponent();
        light.type = ELightType.LT_Point;
        light.color = colour;
        light.unit = ELightUnit.LU_Lumen;
        light.intensity = lumens * this.m_lightLevel;
        light.radius = radius;
        light.temperature = -1.0;
        light.attenuation = rendLightAttenuation.LA_InverseSquare;
        // which surfaces it lights: all of them
        light.lightChannel = Cast<Uint16>(65535);
        light.sceneDiffuse = true;
        light.sceneSpecularScale = Cast<Uint8>(100);
        light.scaleGI = Cast<Uint8>(100);
        light.scaleEnvProbes = Cast<Uint8>(100);
        light.scaleVolFog = Cast<Uint8>(40);
        light.useInTransparents = true;
        light.useInParticles = true;
        light.isEnabled = true;
        let place: WorldTransform;
        WorldTransform.SetPosition(place, Vector4(0.0, 0.0, z, 1.0));
        WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        light.localTransform = place;
        return light;
    }

    public func SetLight(level: Float, colour: Int32) {
        this.m_lightLevel = MaxF(0.0, MinF(level, 10.0));
        this.m_lightColour = Max(0, Min(colour, RNLightColourCount() - 1));
    }
    public func LightColourCount() -> Int32 { return RNLightColourCount(); }
    public func LightColourName(i: Int32) -> String { return RNLightColourName(i); }

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
        return "floor " + this.SizeText(this.m_floorFit) + ", wall " + this.SizeText(this.m_wallFit) +
            ", backing " + this.SizeText(this.m_backFit);
    }

    // --- markers: what V can use, made visible ----------------------------------------

    // A mesh scaled evenly (no stretching) so its largest side is `size` metres,
    // standing with its base `lift` metres above the entity's origin.
    // upright: the mesh lies flat as made, so stand it up (90 degrees about X).
    private func FitUniform(template: ref<EntityBuilderTemplateWrapper>, fit: ref<RNMeshFit>, path: ResRef,
                            lift: Float, size: Float, upright: Bool, look: CName) {
        if !IsDefined(fit) || !fit.ready {
            return;
        }
        let largest = MaxF(fit.max.X - fit.min.X, MaxF(fit.max.Y - fit.min.Y, fit.max.Z - fit.min.Z));
        let s = size / MaxF(0.01, largest);
        let cx = (fit.max.X + fit.min.X) / 2.0;
        let cy = (fit.max.Y + fit.min.Y) / 2.0;
        let mesh = new MeshComponent();
        mesh.mesh *= path;
        mesh.meshAppearance = look;
        mesh.visualScale = Vector3(s, s, s);
        let place: WorldTransform;
        if upright {
            // turned 90 degrees about X: the mesh's Y becomes height, its Z faces out
            let cz = (fit.max.Z + fit.min.Z) / 2.0;
            WorldTransform.SetPosition(place, Vector4(-cx * s, cz * s, lift - fit.min.Y * s, 1.0));
            WorldTransform.SetOrientation(place, Quaternion(0.70710677, 0.0, 0.0, 0.70710677));
        } else {
            WorldTransform.SetPosition(place, Vector4(-cx * s, -cy * s, lift - fit.min.Z * s, 1.0));
            WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        }
        mesh.localTransform = place;
        mesh.isEnabled = true;
        template.AddComponent(mesh);
    }

    // Every usable thing gets its own mesh and a pool of coloured light, so it
    // can be seen from across a room (see RNMarker* below for which is which).
    private func AddMarker(template: ref<EntityBuilderTemplateWrapper>, kind: Int32, size: Float) {
        let index = RNMarkerMeshIndex(kind);
        if index >= 0 && index < ArraySize(this.m_markerFits) {
            let fit = this.m_markerFits[index];
            this.FitUniform(template, fit, RNMarkerMesh(index), RNMarkerLift(kind), size, index == 0,
                RNFindAppearance(fit, RNMarkerLook(kind)));
        }
        // markers keep their full brightness however the rooms are lit
        let lumens = RNMarkerLumens(kind);
        template.AddComponent(this.MakeColouredLight(RNMarkerColour(kind), size + 4.0, lumens, RNMarkerLift(kind) + size * 0.5));
        // the ways up and down also throw a strong pool of colour on the floor
        // around them, so they stand out against the room's own light
        if kind == 13 || kind == 14 {
            template.AddComponent(this.MakeColouredLight(RNMarkerColour(kind), 7.0, lumens, 0.6));
        }
        if kind == 10 || kind == 11 {
            template.AddComponent(this.MakeColouredLight(RNMarkerColour(kind), 4.0, lumens * 0.6, 0.4));
        }
    }

    // For 'cyber debug': each marker mesh and the appearances (looks) it comes in.
    public func MarkerAppearances() -> String {
        let text = "";
        let i = 0;
        while i < ArraySize(this.m_markerFits) {
            let fit = this.m_markerFits[i];
            let line = "hologram " + IntToString(i) + " (" + RNMarkerName(i) + "): ";
            if IsDefined(fit) && fit.ready {
                line += StrLen(fit.appearances) > 0 ? fit.appearances : "(no appearances listed)";
            } else {
                line += "not loaded";
            }
            text += (StrLen(text) > 0 ? "\n" : "") + line;
            i += 1;
        }
        return text;
    }

    // For 'cyber debug': how many marker meshes have loaded.
    public func MarkersLoaded() -> Int32 {
        let n = 0;
        for fit in this.m_markerFits {
            if IsDefined(fit) && fit.ready {
                n += 1;
            }
        }
        return n;
    }

    // --- blocks --------------------------------------------------------------------

    // kind 0: floor slab (its mesh's top is the top of the box)
    // kind 1: wall or door barrier (its mesh fills the box)
    // kind 2: ceiling (the floor mesh upside down, its face on the underside of the box)
    // kind 3: solid dark block (the outer shell of a floor, corner pillars)
    // kind 4: a light (no collider, nothing to see): the room's own glow
    // kind 5: particles (no collider; Lua adds the particle system)
    // kind 10 and up: a marker (no collider): hx is its size (see RNMarker*)
    // --- scanner names ------------------------------------------------------

    public func SetScannerName(id: EntityID, name: String, faction: String) {
        let i = this.FindScannerName(id);
        if i >= 0 {
            this.m_scanNames[i] = name;
            this.m_scanFactions[i] = faction;
            return;
        }
        ArrayPush(this.m_scanIDs, id);
        ArrayPush(this.m_scanNames, name);
        ArrayPush(this.m_scanFactions, faction);
        while ArraySize(this.m_scanIDs) > 64 {
            ArrayErase(this.m_scanIDs, 0);
            ArrayErase(this.m_scanNames, 0);
            ArrayErase(this.m_scanFactions, 0);
        }
    }

    public func ClearScannerName(id: EntityID) {
        let i = this.FindScannerName(id);
        if i >= 0 {
            ArrayErase(this.m_scanIDs, i);
            ArrayErase(this.m_scanNames, i);
            ArrayErase(this.m_scanFactions, i);
        }
    }

    public func FindScannerName(id: EntityID) -> Int32 {
        let i = 0;
        while i < ArraySize(this.m_scanIDs) {
            if Equals(this.m_scanIDs[i], id) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func ScannerNameAt(i: Int32) -> String { return this.m_scanNames[i]; }
    public func ScannerFactionAt(i: Int32) -> String { return this.m_scanFactions[i]; }

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

        if kind == 4 {
            this.AddLight(template, size.X);
            return;
        }
        if kind >= 10 {
            this.AddMarker(template, kind, size.X);
            return;
        }
        if kind == 5 {
            // particles: added by the Lua side when the entity initialises
            // (Hooks.reds); this unlit light is how it recognises the block
            let tag = this.MakeColouredLight(RNLightColour(this.m_lightColour), 0.1, 0.0, 0.0);
            tag.name = n"rn_particles_here";
            template.AddComponent(tag);
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

        if kind == 3 {
            this.FitMesh(template, this.m_backFit, RNBackingMesh(), 0.0, 0.0, 0.0, size.X, size.Y, size.Z);
            return;
        }

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
        if kind != 1 {
            sx = sx * this.m_scale;
            sy = sy * this.m_scale;
        }
        visual.visualScale = Vector3(sx, sy, sz);
        let place: WorldTransform;
        if kind == 2 {
            // turned over (180 degrees about X: y and z flip), so the face that is
            // the floor's top looks down from the underside of the box
            WorldTransform.SetPosition(place, Vector4(-cx * sx, cy * sy, cz * sz - size.Z, 1.0));
            WorldTransform.SetOrientation(place, Quaternion(1.0, 0.0, 0.0, 0.0));
        } else {
            WorldTransform.SetPosition(place, Vector4(-cx * sx, -cy * sy, offsetZ - cz * sz, 1.0));
            WorldTransform.SetOrientation(place, Quaternion(0.0, 0.0, 0.0, 1.0));
        }
        visual.localTransform = place;
        visual.isEnabled = true;
        template.AddComponent(visual);

        // Floors and ceilings get a solid backing just behind their face, a little
        // larger than the room, so nothing shows through gaps in the mesh or at
        // the seams with the walls.
        if kind == 0 {
            this.FitMesh(template, this.m_backFit, RNBackingMesh(), 0.0, 0.0, -0.1, size.X + 0.6, size.Y + 0.6, size.Z - 0.05);
        }
        if kind == 2 {
            this.FitMesh(template, this.m_backFit, RNBackingMesh(), 0.0, 0.0, 0.1, size.X + 0.6, size.Y + 0.6, size.Z - 0.05);
        }

        // Wall meshes are only drawn from one side, so walls get a second copy
        // turned round (180 degrees about the vertical), back to back.
        if kind == 1 {
            let back = new MeshComponent();
            back.mesh *= path;
            back.meshAppearance = n"default";
            back.visualScale = Vector3(sx, sy, sz);
            let backPlace: WorldTransform;
            WorldTransform.SetPosition(backPlace, Vector4(cx * sx, cy * sy, offsetZ - cz * sz, 1.0));
            WorldTransform.SetOrientation(backPlace, Quaternion(0.0, 0.0, 1.0, 0.0));
            back.localTransform = backPlace;
            back.isEnabled = true;
            template.AddComponent(back);
        }
    }

    // The kind of block an entity is (see SpawnBlock), for the Lua side.
    public func BlockKind(id: EntityID) -> Int32 {
        return RoundF(this.SizeOf(id).W);
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

// --- room light colours ------------------------------------------------------------

public func RNLightColourCount() -> Int32 { return 5; }

public func RNLightColourName(i: Int32) -> String {
    if i == 0 { return "Cyberspace cyan"; }
    if i == 1 { return "Netrunner blue"; }
    if i == 2 { return "Arasaka red"; }
    if i == 3 { return "Matrix green"; }
    if i == 4 { return "Plain white"; }
    return "Cyberspace cyan";
}

public func RNLightColour(i: Int32) -> Color {
    let c: Color;
    c.Alpha = Cast<Uint8>(255);
    if i == 1 {
        c.Red = Cast<Uint8>(70); c.Green = Cast<Uint8>(120); c.Blue = Cast<Uint8>(255);
    } else if i == 2 {
        c.Red = Cast<Uint8>(255); c.Green = Cast<Uint8>(60); c.Blue = Cast<Uint8>(70);
    } else if i == 3 {
        c.Red = Cast<Uint8>(90); c.Green = Cast<Uint8>(255); c.Blue = Cast<Uint8>(140);
    } else if i == 4 {
        c.Red = Cast<Uint8>(255); c.Green = Cast<Uint8>(250); c.Blue = Cast<Uint8>(240);
    } else {
        c.Red = Cast<Uint8>(120); c.Green = Cast<Uint8>(220); c.Blue = Cast<Uint8>(255);
    }
    return c;
}

// --- markers -------------------------------------------------------------------------
// kind 10 data and 12 data already taken (hologram screens), 11 paydata (the
// same screens, in gold),
// 13 way down and 14 way up (a hologram light beam: green down, white up), 15 jack-out node
// (holographic pillar), 16 sealed doorway (security gate hologram),
// 17 device console (Mikoshi access point), 18 network core (Cynosure brain)

public func RNMarkerMeshIndex(kind: Int32) -> Int32 {
    if kind == 10 || kind == 11 || kind == 12 { return 0; }
    if kind == 13 || kind == 14 { return 2; }
    if kind == 15 { return 3; }
    if kind == 16 { return 4; }
    if kind == 17 { return 5; }
    if kind == 18 { return 6; }
    return -1;
}

// The look each marker asks its mesh for (part of an appearance name; empty: default).
public func RNMarkerLook(kind: Int32) -> String {
    if kind == 11 { return "gold"; }
    return "";
}

public func RNMarkerName(index: Int32) -> String {
    if index == 0 { return "data screens"; }
    if index == 1 { return "unused"; }
    if index == 2 { return "ways up and down"; }
    if index == 3 { return "jack-out pillar"; }
    if index == 4 { return "sealed doorway"; }
    if index == 5 { return "device console"; }
    if index == 6 { return "network core"; }
    if index == 7 { return "numbers (unused)"; }
    return "unknown";
}

public func RNMarkerMesh(index: Int32) -> ResRef {
    if index == 1 { return r"base\\fx\\vehicles\\_summoning\\mesh\\fx_veh_sum_holo_ground.mesh"; }
    if index == 2 { return r"base\\environment\\decoration\\advertising\\holograms\\hologram_light_beam.mesh"; }
    if index == 3 { return r"ep1\\fx\\quest\\q303\\paradise_hotel\\holograms\\holographic_pillar.mesh"; }
    if index == 4 { return r"base\\environment\\decoration\\electronics\\security\\office_security_gate\\office_security_gate_hologram_a.mesh"; }
    if index == 5 { return r"base\\environment\\decoration\\unique\\quest\\q101_mikoshi_access_point\\q101_mikoshi_access_point_a.mesh"; }
    if index == 6 { return r"ep1\\environment\\quests\\q305_cynosure_core\\q305_brain_hologram.mesh"; }
    if index == 7 { return r"base\\fx\\meshes\\hologram\\awacs_hologram\\fx_awacs_numbers.mesh"; }
    return r"base\\fx\\environment\\holograms\\screens\\e_hologram_screens.mesh";
}

// how far above the floor each marker floats
public func RNMarkerLift(kind: Int32) -> Float {
    if kind == 10 || kind == 11 || kind == 12 { return 0.5; }
    if kind == 18 { return 0.8; }
    return 0.0;
}

public func RNMarkerLumens(kind: Int32) -> Float {
    if kind == 12 { return 600.0; }
    if kind == 10 || kind == 11 { return 8000.0; }
    if kind == 13 || kind == 14 { return 16000.0; }
    if kind == 18 { return 6000.0; }
    if kind == 16 { return 4000.0; }
    return 3000.0;
}

public func RNMarkerColour(kind: Int32) -> Color {
    let c: Color;
    c.Alpha = Cast<Uint8>(255);
    if kind == 11 {        // paydata: gold
        c.Red = Cast<Uint8>(255); c.Green = Cast<Uint8>(200); c.Blue = Cast<Uint8>(60);
    } else if kind == 12 { // taken: dim grey
        c.Red = Cast<Uint8>(120); c.Green = Cast<Uint8>(120); c.Blue = Cast<Uint8>(130);
    } else if kind == 13 { // way down: green
        c.Red = Cast<Uint8>(80); c.Green = Cast<Uint8>(255); c.Blue = Cast<Uint8>(120);
    } else if kind == 14 || kind == 15 { // way up, jack out: white
        c.Red = Cast<Uint8>(240); c.Green = Cast<Uint8>(245); c.Blue = Cast<Uint8>(255);
    } else if kind == 16 { // sealed: red
        c.Red = Cast<Uint8>(255); c.Green = Cast<Uint8>(40); c.Blue = Cast<Uint8>(50);
    } else if kind == 17 { // console: orange
        c.Red = Cast<Uint8>(255); c.Green = Cast<Uint8>(140); c.Blue = Cast<Uint8>(40);
    } else if kind == 18 { // core: violet
        c.Red = Cast<Uint8>(190); c.Green = Cast<Uint8>(80); c.Blue = Cast<Uint8>(255);
    } else {               // data: cyan
        c.Red = Cast<Uint8>(90); c.Green = Cast<Uint8>(230); c.Blue = Cast<Uint8>(255);
    }
    return c;
}

// A plain dark box from the game's level design kit, for backing and shells.
public func RNBackingMesh() -> ResRef {
    return r"base\\environment\\ld_kit\\box_1_1_1_snappoints_dark.mesh";
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

// The scanner shows cyberspace NPCs as what they are in the Net (ICE, a rogue
// AI construct, a NetWatch agent, a gang's netrunner), not the game character
// they were spawned from: after the game fills in the scan, the name and
// affiliation are replaced for the NPCs Lua named.
@wrapMethod(NPCPuppet)
public const func CompileScannerChunks() -> Bool {
    let ok = wrappedMethod();
    if !ok {
        return ok;
    }
    let system = RNCyberspaceSystem.Get();
    if !IsDefined(system) {
        return ok;
    }
    let i = system.FindScannerName(this.GetEntityID());
    if i < 0 {
        return ok;
    }
    let board = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ScannerModules);
    if !IsDefined(board) {
        return ok;
    }
    let name = new ScannerName();
    name.Set(system.ScannerNameAt(i));
    board.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerName, ToVariant(name));
    let faction = system.ScannerFactionAt(i);
    if StrLen(faction) > 0 {
        let chunk = new ScannerFaction();
        chunk.Set(faction);
        board.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerFaction, ToVariant(chunk));
    }
    return ok;
}
