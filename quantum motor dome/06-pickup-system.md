# Quantum Motor Dome Pickup System

This document details the pickup system in Quantum Motor Dome, covering how pickups are spawned, collected, and their effects on gameplay.

## Pickup Types

The game features two main types of pickups:

1. **Trail Pickups**: Increase the ship's trail length (score)
2. **Boost Pickups**: Replenish the ship's boost energy

Each pickup type is defined as a separate component:

```qtn
component Pickup
{
    asset_ref<PickupConfig> config;
}

component TrailPickup : Pickup
{
}

component BoostPickup : Pickup
{
}
```

## Pickup Configuration

Pickups are configured through the `PickupConfig` asset:

```csharp
public class PickupConfig : AssetObject
{
    public FP rotationSpeed;
    public FP bounceHeight;
    public FP bounceSpeed;
    
    [Header("Trail Pickup Settings")]
    public int trailSegmentsBase = 2;
    public int trailSegmentsBonus = 5;
    
    [Header("Boost Pickup Settings")]
    public FP boostEnergy = 50;
}
```

This configuration controls:
- Visual behavior (rotation speed, bounce height and speed)
- Trail pickup value (base and bonus segment counts)
- Boost pickup value (amount of boost energy restored)

## Generic Pickup System

The game uses a generic pickup system that can work with different pickup types:

```csharp
unsafe class PickupSystem<P> : SystemSignalsOnly, ISignalOnTriggerEnter3D, IGameState_Game where P : unmanaged, IComponent
{
    public override bool StartEnabled => false;

    public static int SpawnCap(Frame f) => 5 * f.ActiveUsers;

    public override void OnEnabled(Frame f)
    {
        if (f.IsVerified)
            for (int i = 0; i < SpawnCap(f); i++)
                SpawnPickup(f);
    }

    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        if (!f.TryGet(info.Other, out P pickup)) return;
        if (!f.Unsafe.TryGetPointer(info.Entity, out Ship* ship)) return;
        if (!f.TryGet(info.Entity, out PlayerLink link)) return;

        // Apply pickup effect based on type
        if (pickup is TrailPickup)
        {
            int oldScore = ship->Score;
            ship->Score += ship->Score > 0 ? 5 : 2;
            f.Events.PlayerScoreChanged(link.Player, oldScore, ship->Score);
        }
        else if (pickup is BoostPickup)
        {
            // Add boost energy and clamp to maximum
            ship->BoostAmount += f.RuntimeConfig.boostPickupValue;
            if (ship->BoostAmount > 100) ship->BoostAmount = 100;
        }

        // Send event and destroy pickup
        f.Events.PickupCollected(info.Entity, ComponentTypeId<P>.Id);
        f.Destroy(info.Other);

        // Spawn a new pickup if below cap
        if (f.ComponentCount<P>() < SpawnCap(f))
        {
            SpawnPickup(f);
        }
    }
    
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
    
    public static EntityRef SpawnPickup(Frame f, FPVector3 position)
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
            // Position pickup at specified position, projected onto sphere
            tf->Position = ((position - mm.mapOrigin).Normalized * mm.mapRadius) + mm.mapOrigin;
            tf->Rotation = FPQuaternion.LookRotation(-tf->Position);
        }

        return entity;
    }
}
```

Key aspects of this system:
1. **Generic Implementation**: Uses a type parameter to work with different pickup types
2. **Event Handling**: Subscribes to the `OnTriggerEnter3D` event to detect collisions
3. **Spawn Cap**: Maintains a maximum number of pickups based on active players
4. **Initial Population**: Spawns pickups when the system is enabled
5. **Pickup Effects**: Applies different effects based on pickup type
6. **Spawn Methods**: Provides methods for random spawning and position-specific spawning

## Spawn Cap Calculation

The number of pickups allowed in the game scales with the number of active players:

```csharp
public static int SpawnCap(Frame f) => 5 * f.ActiveUsers;
```

This ensures that:
1. Solo players have enough pickups to find
2. Multiplayer games have more pickups to support more players
3. The density of pickups remains consistent regardless of player count

## Pickup Distribution

Pickups are distributed randomly across the sphere:

```csharp
// Position pickup randomly on the sphere surface
tf->Position = new FPVector3(
    f.RNG->NextInclusive((FP)(-1), (FP)(1)),
    f.RNG->NextInclusive((FP)(-1), (FP)(1)),
    f.RNG->NextInclusive((FP)(-1), (FP)(1))
    ).Normalized * mm.mapRadius
    + mm.mapOrigin;
```

Key aspects of distribution:
1. **Random Direction**: Generates a random unit vector by normalizing a random 3D vector
2. **Sphere Projection**: Projects the position onto the sphere surface at the map radius
3. **Deterministic RNG**: Uses Quantum's deterministic random number generator

## Trail Pickup Effects

When a ship collects a trail pickup:

```csharp
if (pickup is TrailPickup)
{
    int oldScore = ship->Score;
    ship->Score += ship->Score > 0 ? 5 : 2;
    f.Events.PlayerScoreChanged(link.Player, oldScore, ship->Score);
}
```

Key aspects of trail pickups:
1. **Progressive Value**: Worth more (5 segments) for ships that already have a trail
2. **Starter Value**: Worth less (2 segments) for ships with no trail
3. **Score Event**: Fires an event to update UI elements with the new score

## Boost Pickup Effects

When a ship collects a boost pickup:

```csharp
else if (pickup is BoostPickup)
{
    // Add boost energy and clamp to maximum
    ship->BoostAmount += f.RuntimeConfig.boostPickupValue;
    if (ship->BoostAmount > 100) ship->BoostAmount = 100;
}
```

Key aspects of boost pickups:
1. **Energy Restoration**: Adds a configurable amount of boost energy
2. **Maximum Cap**: Prevents boost energy from exceeding 100
3. **Configuration**: Uses a value from the runtime configuration for flexibility

## Pickup Collection

The pickup collection process happens in the `OnTriggerEnter3D` method:

```csharp
public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
{
    if (!f.TryGet(info.Other, out P pickup)) return;
    if (!f.Unsafe.TryGetPointer(info.Entity, out Ship* ship)) return;
    if (!f.TryGet(info.Entity, out PlayerLink link)) return;

    // Apply pickup effect based on type
    // ...
    
    // Send event and destroy pickup
    f.Events.PickupCollected(info.Entity, ComponentTypeId<P>.Id);
    f.Destroy(info.Other);

    // Spawn a new pickup if below cap
    if (f.ComponentCount<P>() < SpawnCap(f))
    {
        SpawnPickup(f);
    }
}
```

Key aspects of collection:
1. **Type Verification**: Ensures the colliding entity is a valid pickup of the correct type
2. **Ship Verification**: Ensures the collecting entity is a ship with a player link
3. **Effect Application**: Applies the appropriate effect based on pickup type
4. **Event Notification**: Fires an event to trigger visual/audio feedback
5. **Pickup Destruction**: Removes the pickup from the game
6. **Respawn Logic**: Spawns a new pickup to maintain the desired pickup density

## Pickup Events

The pickup system generates events for Unity visualization:

```qtn
event PickupCollected { entity_ref Entity; Byte TypeId; }
event PlayerScoreChanged { player_ref Player; Int32 OldScore; Int32 NewScore; }
```

These events are subscribed to in Unity to provide visual and audio feedback:

```csharp
public class PickupEffects : MonoBehaviour
{
    [SerializeField] AudioClip trailPickupSound;
    [SerializeField] AudioClip boostPickupSound;
    [SerializeField] GameObject trailPickupVFX;
    [SerializeField] GameObject boostPickupVFX;
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventPickupCollected>(this, OnPickupCollected);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventPickupCollected>(this);
    }
    
    private void OnPickupCollected(EventPickupCollected evt)
    {
        // Get the ship view
        QuantumEntityView view = QuantumEntityView.FindEntityView(evt.Entity);
        if (view == null) return;
        
        // Determine pickup type and play appropriate effects
        if (evt.TypeId == ComponentTypeId<TrailPickup>.Id)
        {
            // Play trail pickup effects
            AudioSource.PlayClipAtPoint(trailPickupSound, view.transform.position);
            Instantiate(trailPickupVFX, view.transform.position, Quaternion.identity);
        }
        else if (evt.TypeId == ComponentTypeId<BoostPickup>.Id)
        {
            // Play boost pickup effects
            AudioSource.PlayClipAtPoint(boostPickupSound, view.transform.position);
            Instantiate(boostPickupVFX, view.transform.position, Quaternion.identity);
        }
    }
}
```

## Pickup Visualization

Pickups have visual representations in Unity that are driven by the `PickupView` component:

```csharp
public class PickupView : MonoBehaviour
{
    public float rotationSpeed = 50f;
    public float bounceHeight = 0.3f;
    public float bounceSpeed = 2f;
    
    private Vector3 startPosition;
    
    private void Start()
    {
        startPosition = transform.localPosition;
    }
    
    private void Update()
    {
        // Rotate pickup
        transform.Rotate(Vector3.up, rotationSpeed * Time.deltaTime);
        
        // Bounce pickup
        float bounce = Mathf.Sin(Time.time * bounceSpeed) * bounceHeight;
        transform.localPosition = startPosition + Vector3.up * bounce;
    }
}
```

This adds visual interest through:
1. **Rotation**: Continuous rotation to attract attention
2. **Bouncing**: Vertical oscillation to create a floating effect
3. **Parameterization**: Configurable values for designers to adjust

## Pickup Prototypes

Pickups are defined as entity prototypes in the Quantum asset database:

```csharp
// In SimulationConfig.User.cs
public AssetRef<EntityPrototype> trailPickup;
public AssetRef<EntityPrototype> boostPickup;

// In the Unity editor
[Serializable]
public class PickupPrototype
{
    public GameObject visualPrefab;
    public Collider triggerCollider;
    public PickupConfig config;
}
```

A typical pickup prototype includes:
1. **Pickup Component**: TrailPickup or BoostPickup component
2. **Transform3D**: For position and rotation
3. **PhysicsCollider3D**: For collision detection (as a trigger)
4. **Configuration**: Reference to a PickupConfig asset

## Game State Integration

The pickup system is only active during specific game states:

```csharp
unsafe class PickupSystem<P> : SystemSignalsOnly, ISignalOnTriggerEnter3D, IGameState_Game
{
    public override bool StartEnabled => false;
    
    // Implementation...
}
```

By implementing `IGameState_Game`, the system is automatically:
1. Disabled during lobby, countdown, and other non-gameplay states
2. Enabled when the game state changes to the main gameplay state
3. Disabled again when the game ends

## Specialized Pickup Spawning

In addition to random spawning, the system supports spawning pickups at specific positions:

```csharp
public static EntityRef SpawnPickup(Frame f, FPVector3 position)
{
    // Implementation...
}
```

This is used for:
1. **Respawn Bonuses**: Spawning pickups when a player respawns
2. **Death Drops**: Spawning pickups at the location where a ship was destroyed
3. **Reconnection Rewards**: Spawning pickups when a ship successfully reconnects its trail

## Best Practices

1. **Generic Implementation**: Use type parameters for shared functionality across pickup types
2. **Scalable Distribution**: Scale pickup count based on active players
3. **Spherical Placement**: Properly project pickups onto the sphere surface
4. **Progressive Value**: Make pickups more valuable for players already performing well
5. **Visual Feedback**: Use events to trigger appropriate visual and audio effects
6. **Game State Integration**: Only activate pickups during appropriate game states
7. **Cap Enforcement**: Maintain a maximum number of pickups to ensure balanced gameplay
8. **Configuration Assets**: Store pickup parameters in configurable assets
9. **Type Identification**: Use component type IDs for efficient type checking in events
