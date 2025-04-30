# Racer System Implementation

The `RacerSystem` is the core system that handles vehicle physics, collision responses, and checkpoint tracking in Quantum Racer 2.5D.

## System Definition

```csharp
[Preserve]
public unsafe class RacerSystem : SystemMainThreadFilter<RacerSystem.Filter>,
    ISignalOnPlayerAdded,
    ISignalOnTriggerEnter2D,
    ISignalOnTriggerExit2D,
    ISignalOnCollisionEnter2D,
    ISignalRespawn,
    ISignalReset
{
    // Implementation details follow
}
```

## Key Interfaces
- `SystemMainThreadFilter<RacerSystem.Filter>`: Base class for systems with a filter
- `ISignalOnPlayerAdded`: Handles player joins
- `ISignalOnTriggerEnter2D`: Detects entering trigger areas (checkpoints, modifiers)
- `ISignalOnTriggerExit2D`: Detects leaving trigger areas
- `ISignalOnCollisionEnter2D`: Handles collisions with other vehicles or walls
- `ISignalRespawn`: Handles vehicle respawning
- `ISignalReset`: Handles vehicle resetting

## Component Filter
```csharp
public struct Filter
{
    public EntityRef Entity;
    public Transform2D* Transform;
    public Transform2DVertical* Vertical;
    public PhysicsBody2D* Body;
    public Racer* Vehicle;
}
```

## Key Methods

### Update
Processes vehicle updates each frame, calling the vehicle config's update method.
```csharp
public override void Update(Frame f, ref Filter filter)
{
    if (f.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
    {
        if (manager->State != RaceState.Running) return;
    }

    var config = f.FindAsset(filter.Vehicle->Config);
    config.UpdateRacer(f, ref filter);
}
```

### OnPlayerAdded
Spawns a vehicle when a player joins.
```csharp
public void OnPlayerAdded(Frame f, PlayerRef player, bool firstTime)
{
    if (firstTime == false) return;
    f.Signals.Spawn(player, null);
}
```

### OnTriggerEnter2D
Handles vehicle entering trigger areas like modifiers or death zones.
```csharp
public void OnTriggerEnter2D(Frame f, TriggerInfo2D info)
{
    if (info.IsStatic && f.Unsafe.TryGetPointer(info.Entity, out Racer* racer))
    {
        if (racer->Finished) return;
        var modifier = f.FindAsset<RacerModifier>(info.StaticData.Asset);
        if (modifier != null)
        {
            racer->Modifier = modifier.Guid;
        }
        else
        {
            // death
            Death(f, info.Entity, racer);
        }
    }
}
```

### OnTriggerExit2D
Removes modifier effects when leaving a trigger area.
```csharp
public void OnTriggerExit2D(Frame f, ExitInfo2D info)
{
    if (info.IsStatic && f.Unsafe.TryGetPointer(info.Entity, out Racer* racer))
    {
        racer->Modifier = default;
    }
}
```

### OnCollisionEnter2D
Handles collisions with walls or other vehicles.
```csharp
public void OnCollisionEnter2D(Frame f, CollisionInfo2D info)
{
    // Skip if we can't get the physics body or racer component
    if (!f.Unsafe.TryGetPointer(info.Entity, out PhysicsBody2D* body) ||
        !f.Unsafe.TryGetPointer<Racer>(info.Entity, out var racer))
    {
        return;
    }

    if (racer->Finished) return;

    var raceConfig = f.FindAsset(f.RuntimeConfig.RaceConfig);
    
    // Wall collision handling
    if (info.IsStatic)
    {
        body->Velocity *= raceConfig.WallBumpSpeedFactor;
        body->AddLinearImpulse(info.ContactNormal * raceConfig.WallBumpForce);
        f.Events.Bump(info.Entity, 0);

        racer->Energy -= raceConfig.WallBumpDamage;
        if (racer->Energy <= FP._0)
        {
            Death(f, info.Entity, racer);
        }
    }
    // Other vehicle collision
    else if (f.Has<Racer>(info.Other))
    {
        body->AddLinearImpulse(info.ContactNormal * raceConfig.CarBumpForce);
        f.Events.VehicleBump(info.Entity, info.Other, info.ContactPoints.Average);
    }
}
```

### Respawn
Respawns a vehicle after death, resets its energy and position.
```csharp
public void Respawn(Frame f, EntityRef entity, Racer* racer, QBoolean revertPosition)
{
    var config = f.FindAsset(racer->Config);
    racer->Energy = config.InitialEnergy;
    racer->ResetTimer = default;

    if (revertPosition && f.Unsafe.TryGetPointer<Transform2D>(entity, out var transform))
    {
        transform->Teleport(f, racer->LastCheckpointPosition);

        if (f.TryGet<Transform2D>(racer->NextCheckpoint, out var checkpointTransform))
        {
            var direction = checkpointTransform.Position - transform->Position;
            var radians = FPVector2.RadiansSignedSkipNormalize(direction.Normalized, FPVector2.Up);
            transform->Rotation = -radians;

            if (f.Unsafe.TryGetPointer<Bot>(entity, out var bot))
            {
                bot->RacingLineCheckpoint = bot->RacingLineReset;
                bot->RacelineIndex = bot->RacelineIndexReset;
            }
        }
    }

    if (f.Unsafe.TryGetPointer<PhysicsBody2D>(entity, out var body))
    {
        body->IsKinematic = false;
    }

    f.Events.Respawn(entity);
}
```

### Reset
Resets a vehicle's physics state.
```csharp
public void Reset(Frame f, EntityRef entity, Racer* racer)
{
    if (f.Unsafe.TryGetPointer<Transform2DVertical>(entity, out var vertical))
    {
        vertical->Position = default;
    }

    racer->Lean = default;
    racer->Pitch = default;
    racer->VerticalSpeed = default;
    racer->Modifier = default;
    
    if (f.Unsafe.TryGetPointer<PhysicsBody2D>(entity, out var body))
    {
        body->Velocity = default;
        body->AngularVelocity = default;
        body->IsKinematic = true;
    }
}
```

### Death (Private Helper)
Handles vehicle death, setting up respawn.
```csharp
private static void Death(Frame f, EntityRef entity, Racer* racer)
{
    var raceConfig = f.FindAsset(f.RuntimeConfig.RaceConfig);
    racer->Energy = default;
    racer->ResetTimer = raceConfig.RespawnCooldown;
    f.Signals.Reset(entity, racer);
    f.Events.Death(entity);
}
```

## Implementation Notes
- Uses unsafe C# pointer access for performance
- Leverages Quantum's deterministic physics
- Handles race state checks before processing updates
- Provides response to collisions based on configuration parameters
- Sets up vehicle states based on RacerConfig assets
