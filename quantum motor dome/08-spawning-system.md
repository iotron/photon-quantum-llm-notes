# Quantum Motor Dome Spawning System

This document explains the spawning system in Quantum Motor Dome, covering how ships, pickups, and other entities are spawned, respawned, and positioned in the game world.

## Ship Spawning Overview

The spawning system handles several key aspects of entity creation:

1. **Initial Ship Spawning**: Creating ships when players join the game
2. **Ship Respawning**: Repositioning ships after destruction or reconnection
3. **Spawn Protection**: Providing temporary invulnerability after spawning
4. **Random Positioning**: Placing ships at random positions on the sphere
5. **Orientation**: Ensuring ships are properly oriented on the sphere surface

## Ship Spawner System

The `ShipSpawnerSystem` handles ship creation when players join the game:

```csharp
public unsafe class ShipSpawnerSystem : SystemSignalsOnly, ISignalOnPlayerAdded
{
    public void OnPlayerAdded(Frame f, PlayerRef player, bool isRejoining)
    {
        // Don't spawn ships during certain game states
        if (f.Global->CurrentState == GameState.Postgame || 
            f.Global->CurrentState == GameState.Outro)
            return;
        
        // Create ship entity from prototype
        EntityRef shipEntity = f.Create(f.SimulationConfig.shipPrototype);
        
        // Link ship to player
        f.Add<PlayerLink>(shipEntity, new PlayerLink { Player = player });
        
        // Position ship randomly on sphere
        if (f.Unsafe.TryGetPointer<Transform3D>(shipEntity, out var transform))
        {
            PositionRandomlyOnSphere(f, transform);
            
            // Orient ship to face outward from sphere
            MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);
            transform->Rotation = FPQuaternion.LookRotation(
                -transform->Position.Normalized,
                FPVector3.Up
            );
        }
        
        // Add spawn protection
        f.Add<SpawnProtection>(shipEntity, new SpawnProtection { 
            TimeRemaining = FP._3
        });
        
        // Initialize ship components
        if (f.Unsafe.TryGetPointer<Ship>(shipEntity, out var ship))
        {
            ship->Score = 0;
            ship->BoostAmount = 100;
            
            // Allocate lists for segments and queries
            ship->Segments = f.AllocateList<FPVector3>();
            ship->SegmentQueries = f.AllocateList<PhysicsQueryRef>();
        }
        
        // Send event
        f.Events.ShipSpawned(shipEntity, player);
    }
    
    private void PositionRandomlyOnSphere(Frame f, Transform3D* transform)
    {
        MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);
        ShipSpec spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
        
        transform->Position = new FPVector3(
            f.RNG->NextFP(-1, 1),
            f.RNG->NextFP(-1, 1),
            f.RNG->NextFP(-1, 1)
        ).Normalized * (mm.mapRadius - spec.radius) + mm.mapOrigin;
    }
}
```

Key aspects of ship spawning:
1. **Entity Creation**: Creates a ship entity from a prototype
2. **Player Linking**: Links the ship to the player who will control it
3. **Random Positioning**: Places the ship at a random position on the sphere
4. **Orientation**: Orients the ship to face outward from the sphere
5. **Spawn Protection**: Adds temporary invulnerability
6. **Initialization**: Sets initial values for ship components
7. **List Allocation**: Allocates dynamic lists for segments and queries
8. **Event Notification**: Fires an event for Unity visualization

## Ship Respawning

Ships are respawned after destruction or reconnection using the `Delay` component:

```csharp
public unsafe class DelaySystem : SystemMainThreadFilter<DelaySystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Delay* Delay;
    }
    
    public override void Update(Frame f, ref Filter filter)
    {
        filter.Delay->TimeRemaining -= f.DeltaTime;
        
        if (filter.Delay->TimeRemaining <= 0)
        {
            f.Remove<Delay>(filter.Entity);
            
            // Respawn the ship if it was destroyed
            if (f.Has<Destroyer>(filter.Entity))
            {
                f.Remove<Destroyer>(filter.Entity);
                
                // Reposition the ship
                if (f.Unsafe.TryGetPointer(filter.Entity, out Transform3D* transform))
                {
                    PositionRandomlyOnSphere(f, transform);
                }
                
                // Add spawn protection
                f.Add<SpawnProtection>(filter.Entity, new SpawnProtection { 
                    TimeRemaining = FP._3
                });
                
                // Reset the ship's state
                if (f.Unsafe.TryGetPointer(filter.Entity, out Ship* ship))
                {
                    ship->Score = 0;
                    ship->BoostAmount = 100;
                }
                
                // Get player information for event
                if (f.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* link))
                {
                    f.Events.ShipRespawned(filter.Entity, link->Player);
                }
            }
        }
    }
    
    private void PositionRandomlyOnSphere(Frame f, Transform3D* transform)
    {
        // Same implementation as in ShipSpawnerSystem
    }
}
```

Key aspects of ship respawning:
1. **Delay Timing**: Uses a timer to create a delay before respawning
2. **Component Removal**: Removes the Destroyer component when respawning
3. **Repositioning**: Places the ship at a new random position
4. **Spawn Protection**: Adds temporary invulnerability
5. **State Reset**: Resets the ship's score and boost amount
6. **Event Notification**: Fires an event for Unity visualization

## Spawn Protection System

The `SpawnProtection` component provides temporary invulnerability after spawning:

```csharp
public unsafe class SpawnProtectionSystem : SystemMainThreadFilter<SpawnProtectionSystem.Filter>, IGameState_Game
{
    public struct Filter
    {
        public EntityRef Entity;
        public SpawnProtection* Protection;
    }
    
    public override bool StartEnabled => false;
    
    public override void Update(Frame f, ref Filter filter)
    {
        filter.Protection->TimeRemaining -= f.DeltaTime;
        
        if (filter.Protection->TimeRemaining <= 0)
        {
            f.Remove<SpawnProtection>(filter.Entity);
            f.Events.PlayerVulnerable(filter.Entity);
        }
    }
}
```

The `SpawnProtection` component is defined as:

```qtn
component SpawnProtection
{
    FP TimeRemaining;
}
```

Key aspects of spawn protection:
1. **Duration Timer**: Counts down the remaining protection time
2. **Automatic Removal**: Removes the component when the timer expires
3. **Event Notification**: Fires an event when protection ends
4. **Collision Filtering**: Other systems skip collisions with entities that have spawn protection

## Spherical Positioning

A key aspect of the spawning system is positioning entities on a sphere:

```csharp
private void PositionRandomlyOnSphere(Frame f, Transform3D* transform)
{
    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);
    ShipSpec spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
    
    transform->Position = new FPVector3(
        f.RNG->NextFP(-1, 1),
        f.RNG->NextFP(-1, 1),
        f.RNG->NextFP(-1, 1)
    ).Normalized * (mm.mapRadius - spec.radius) + mm.mapOrigin;
}
```

This method:
1. Gets the map metadata (sphere center and radius)
2. Gets the ship spec (for ship radius)
3. Generates a random direction by normalizing a random 3D vector
4. Scales the direction by the sphere radius minus the ship radius
5. Offsets by the sphere center

## Ship Orientation

After positioning, ships must be oriented correctly on the sphere:

```csharp
// Orient ship to face outward from sphere
MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);
transform->Rotation = FPQuaternion.LookRotation(
    -transform->Position.Normalized,
    FPVector3.Up
);
```

This ensures that:
1. The ship's forward direction is tangent to the sphere
2. The ship's up direction is aligned with the sphere's normal at that point

## Ship Destruction and Cleanup

The `Destroyer` component marks ships for cleanup and respawning:

```qtn
component Destroyer {}
```

This is a marker component with no data. It's added when a ship is destroyed:

```csharp
private void DestroyShip(Frame f, EntityRef entity)
{
    // Send explosion event
    f.Events.ShipExploded(entity);
    
    // Add delay component to prevent respawning immediately
    f.Add<Delay>(entity, new Delay { 
        TimeRemaining = FP._3
    });
    
    // Add destroyer component for cleanup
    f.Add<Destroyer>(entity);
    
    // Reset the ship's state
    Ship* ship = f.Unsafe.GetPointer<Ship>(entity);
    ship->Score = 0;
    ship->BoostAmount = 100;
    
    // Clear segments
    Collections.QList<FPVector3> segments = f.ResolveList(ship->Segments);
    segments.Clear();
    
    // Free segment queries
    Collections.QList<PhysicsQueryRef> queries = f.ResolveList(ship->SegmentQueries);
    foreach (var query in queries)
    {
        f.Physics3D.FreeQuery(query);
    }
    queries.Clear();
}
```

## Pickup Spawning

Pickups are spawned using the generic `PickupSystem`:

```csharp
public static EntityRef SpawnPickup(Frame f)
{
    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);

    EntityRef entity = default;
    if (typeof(P) == typeof(TrailPickup))
        entity = f.Create(f.SimulationConfig.trailPickup);
    else if (typeof(P) == typeof(BoostPickup))
        entity = f.Create(f.SimulationConfig.boostPickup);

    if (f.Unsafe.TryGetPointer(entity, out Pickup* p) &&
        f.Unsafe.TryGetPointer(entity, out Transform3D* tf))
    {
        // Position pickup randomly on the sphere surface
        tf->Position = new FPVector3(
            f.RNG->NextInclusive((FP)(-1), (FP)(1)),
            f.RNG->NextInclusive((FP)(-1), (FP)(1)),
            f.RNG->NextInclusive((FP)(-1), (FP)(1))
            ).Normalized * mm.mapRadius
            + mm.mapOrigin;
            
        // Orient pickup to face outward from sphere
        tf->Rotation = FPQuaternion.LookRotation(-tf->Position);
    }

    return entity;
}
```

Key aspects of pickup spawning:
1. **Entity Creation**: Creates a pickup entity from a prototype
2. **Random Positioning**: Places the pickup at a random position on the sphere
3. **Orientation**: Orients the pickup to face outward from the sphere
4. **Type Selection**: Creates different pickup types based on the generic parameter

## Explosion Spawning

When ships are destroyed, explosion entities are spawned:

```csharp
private void DestroyShip(Frame f, EntityRef entity)
{
    // Rest of implementation...
    
    // Get position for explosion effect
    Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
    
    // Spawn explosion entity
    EntityRef explosion = f.Create(f.SimulationConfig.explosion);
    Transform3D* exTransform = f.Unsafe.GetPointer<Transform3D>(explosion);
    exTransform->Position = transform->Position;
    exTransform->Rotation = transform->Rotation;
    
    // Rest of implementation...
}
```

Explosions typically have a limited lifetime managed by a timer:

```csharp
public unsafe class ExplosionSystem : SystemMainThreadFilter<ExplosionSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Explosion* Explosion;
    }
    
    public override void Update(Frame f, ref Filter filter)
    {
        filter.Explosion->TimeRemaining -= f.DeltaTime;
        
        if (filter.Explosion->TimeRemaining <= 0)
        {
            f.Destroy(filter.Entity);
        }
    }
}
```

## Spawn Events

The spawning system generates several events for Unity visualization:

```qtn
event ShipSpawned { entity_ref Entity; player_ref Player; }
event ShipRespawned { entity_ref Entity; player_ref Player; }
event ShipExploded { entity_ref Entity; }
event PlayerVulnerable { entity_ref Entity; }
```

These events are subscribed to in Unity to provide visual and audio feedback:

```csharp
public class SpawnEffect : MonoBehaviour
{
    [SerializeField] private GameObject spawnVFX;
    [SerializeField] private AudioClip spawnSound;
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventShipSpawned>(this, OnShipSpawned);
        QuantumEvent.Subscribe<EventShipRespawned>(this, OnShipRespawned);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventShipSpawned>(this);
        QuantumEvent.UnsubscribeListener<EventShipRespawned>(this);
    }
    
    private void OnShipSpawned(EventShipSpawned evt)
    {
        // Find entity view
        var entityView = QuantumEntityView.FindEntityView(evt.Entity);
        if (entityView == null) return;
        
        // Play spawn effect
        Instantiate(spawnVFX, entityView.transform.position, Quaternion.identity);
        AudioSource.PlayClipAtPoint(spawnSound, entityView.transform.position);
    }
    
    private void OnShipRespawned(EventShipRespawned evt)
    {
        // Same implementation as OnShipSpawned
    }
}
```

## Spawn Protection Visualization

The spawn protection state is visualized in Unity:

```csharp
public class ShipView : MonoBehaviour
{
    public Renderer[] renderers;
    MaterialPropertyBlock prop;
    
    void PlayerVulnerableCallback(EventPlayerVulnerable evt)
    {
        if (evt.Entity == EntityRef)
        {
            // Update ship material to show it's vulnerable
            prop.SetFloat("_Invulnerable", 0);
            foreach (Renderer ren in renderers) ren.SetPropertyBlock(prop);
        }
    }
    
    private void Start()
    {
        // Initialize with invulnerable appearance
        prop = new MaterialPropertyBlock();
        prop.SetFloat("_Invulnerable", 1);
        foreach (Renderer ren in renderers) ren.SetPropertyBlock(prop);
    }
}
```

This uses a material property to create a visual effect (typically a shield or glow) that indicates spawn protection.

## Ship Prototype

Ships are defined as entity prototypes in the Quantum asset database:

```csharp
// In SimulationConfig.User.cs
public AssetRef<EntityPrototype> shipPrototype;

// In the Unity editor
[Serializable]
public class ShipPrototype
{
    public GameObject visualPrefab;
    public Collider triggerCollider;
    public ShipSpec shipSpec;
}
```

A typical ship prototype includes:
1. **Ship Component**: Core component for ship state
2. **Transform3D**: For position and rotation
3. **PhysicsCollider3D**: For collision detection
4. **PlayerLink Component**: Optional, added at runtime for player-controlled ships
5. **Configuration**: Reference to a ShipSpec asset

## Best Practices

1. **Random Distribution**: Use proper spherical distribution for random positioning
2. **Spawn Protection**: Provide temporary invulnerability to prevent spawn killing
3. **State Initialization**: Properly initialize all component state on spawn
4. **Memory Management**: Allocate and free dynamic collections (segments, queries)
5. **Event Notification**: Use events to trigger appropriate visual and audio effects
6. **Component Sequencing**: Use marker components (Destroyer) for delayed cleanup
7. **Orientation**: Ensure entities are properly oriented on the sphere surface
8. **Resource Reset**: Reset resources (boost, score) on respawn
9. **Prototype-Based Creation**: Use entity prototypes for consistent entity creation
