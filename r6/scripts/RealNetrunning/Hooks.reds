// -----------------------------------------------------------------------------
// Real Netrunning - hooks the Lua side listens to
// -----------------------------------------------------------------------------
//
// Outside the RealNetrunning module on purpose, so CET can observe it by its
// plain class name. The cyberspace system (Cyberspace.reds) sends it every
// cyberspace block as the block's entity initialises; the Lua side observes
// OnEntityInitialize and adds what only Lua can (the rooms' particles).

public class RNEntityHooks {
    public cb func OnEntityInitialize(event: ref<EntityLifecycleEvent>) {}
}
