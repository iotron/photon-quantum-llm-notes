# Quantum Motor Dome Collision System

This document explains the collision detection and handling system in Quantum Motor Dome, covering how ships interact with trails, other ships, and how reconnection mechanics work.

## Collision Architecture

The collision system is split into two main components to optimize performance:

1. **Query Injection System**: Creates physics queries for all trail segments
2. **Query Retrieval System**: Processes the results of those queries and handles collisions

This separation allows for efficient physics processing by minimizing the number of collision checks performed each frame.

## Ship Segments and Queries

Each ship maintains two lists for collision detection:

```qtn
component Ship
{
	// Other properties...
	list<FPVector3> Segments;
	list<PhysicsQueryRef> SegmentQueries;
}
```

- `Segments`: Stores the positions of each segment in the ship's trail
- `SegmentQueries`: Stores physics query references for collision detection between segments

## Collision Query Injection

The `ShipCollisionInjectionSystem` creates linecast queries between each pair of adjacent trail segments:

```csharp
public unsafe class ShipCollisionInjectionSystem : SystemMainThread, IGameState_Game
{
    public override bool StartEnabled => false;

    public override void Update(Frame f)
    {
        foreach (var (entity, ship) in f.Unsafe.GetComponentBlockIterator<Ship>())
        {
            if (f.Has<Delay>(entity)) continue;
            
            // Get trail segments
            Collections.QList<FPVector3> segments = f.ResolveList(ship.Segments);
            if (segments.Count < 2) continue;
            
            // Free existing queries
            Collections.QList<PhysicsQueryRef> queries = f.ResolveList(ship.SegmentQueries);
            foreach (var query in queries)
            {
                f.Physics3D.FreeQuery(query);
            }
            queries.Clear();
            
            // Create linecast queries between each pair of adjacent segments
            for (int i = 0; i < segments.Count - 1; i++)
            {
                FPVector3 start = segments[i];
                FPVector3 end = segments[i + 1];
                
                // Create linecast query
                PhysicsQueryRef query = f.Physics3D.Linecast(
                    start, 
                    end, 
                    f.Physics3D.AllLayers,
                    entity
                );
                queries.Add(query);
            }
        }
    }
}
```

Key aspects of this system:
1. **Query Management**: Frees old queries before creating new ones to prevent memory leaks
2. **Targeted Checks**: Creates linecast queries only between adjacent segments
3. **Entity Reference**: Includes the source entity in the query for proper filtering
4. **Efficiency**: Only processes entities without the `Delay` component

## Collision Query Retrieval

The `ShipCollisionRetrievalSystem` processes the results of linecast queries and handles collisions:

```csharp
public unsafe class ShipCollisionRetrievalSystem : SystemMainThread, IGameState_Game
{
    public override bool StartEnabled => false;

    public override void Update(Frame f)
    {
        ShipSpec spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
        
        foreach (var (entity, ship) in f.Unsafe.GetComponentBlockIterator<Ship>())
        {
            // Skip entities with delay or spawn protection
            if (f.Has<Delay>(entity) || f.Has<SpawnProtection>(entity)) continue;
            
            // Get query results
            Collections.QList<PhysicsQueryRef> queries = f.ResolveList(ship.SegmentQueries);
            
            for (int i = 0; i < queries.Count; i++)
            {
                PhysicsQueryRef query = queries[i];
                var results = f.Physics3D.GetLinecastHits(query);
                
                foreach (var hit in results)
                {
                    // Skip self hits and entities with spawn protection
                    if (hit.Entity == entity) continue;
                    if (f.Has<SpawnProtection>(hit.Entity)) continue;
                    
                    // Handle the collision
                    HandleCollision(f, entity, hit.Entity, i, spec);
                }
            }
        }
    }
    
    private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
    {
        // Implementation details...
    }
}
```

Key aspects of this system:
1. **Query Processing**: Retrieves the results of each query
2. **Filtering**: Skips irrelevant hits (self, entities with spawn protection)
3. **Collision Handling**: Delegates actual collision response to a separate method
4. **Segment Index**: Tracks which segment was involved in the collision for special handling (e.g., reconnection)

## Collision Types

The system handles three main types of collisions:

### 1. Self-Collision (Reconnection)

When a ship's head collides with its own trail (except the segment directly connected to the head):

```csharp
private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
{
    // Check if this is a self-collision
    if (hitEntity == entity)
    {
        // Check if this is the head segment
        if (segmentIndex == 0)
        {
            Ship* ship = f.Unsafe.GetPointer<Ship>(entity);
            Collections.QList<FPVector3> segments = f.ResolveList(ship->Segments);
            
            // Require minimum segment count for reconnection
            if (segments.Count < 10) return;
            
            // Check alignment between ship heading and trail direction
            Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
            FP dot = FPVector3.Dot(
                transform->Forward,
                (segments[1] - segments[0]).Normalized
            );
            
            // Reconnection successful if alignment is good
            if (dot > spec.connectThreshold)
            {
                // Get player link
                f.Unsafe.TryGetPointer(entity, out PlayerLink* link);
                
                // Award points based on trail length
                int points = ship->Score * ship->Score / 10;
                f.Global->playerData.Resolve(f, out var dict);
                dict.TryGetValuePointer(link->Player, out var pd);
                pd->points += (short)points;
                
                // Send event
                f.Events.PlayerReconnected(entity, segments.Count);
                
                // Add delay for respawn
                f.Add<Delay>(entity, new Delay { 
                    TimeRemaining = spec.despawnAfterConnectDelay 
                });
                f.Events.PlayerDataChanged(link->Player, f.Number);
            }
        }
    }
    else
    {
        // Handle other collision types...
    }
}
```

Key aspects of reconnection:
1. **Segment Index Check**: Only the first segment (head) can trigger reconnection
2. **Minimum Length**: Requires a minimum number of segments for valid reconnection
3. **Alignment Check**: Verifies the ship is moving in a similar direction to the trail
4. **Point Calculation**: Awards points based on the square of the trail length
5. **Respawn Delay**: Adds a delay component for respawning the ship

### 2. Ship-to-Ship Collision

When two ships collide with each other:

```csharp
private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
{
    // Self-collision handling...
    
    // Check if this is a ship-to-ship collision
    if (f.Unsafe.TryGetComponent(hitEntity, out Ship hitShip))
    {
        // Get transforms
        Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
        Transform3D* hitTransform = f.Unsafe.GetPointer<Transform3D>(hitEntity);
        
        // Calculate impact velocity
        FPVector3 relativeVelocity = transform->Forward - hitTransform->Forward;
        FP impactSpeed = relativeVelocity.Magnitude;
        
        // Only handle significant impacts
        if (impactSpeed > FP._0_50)
        {
            // Determine which ship gets destroyed based on impact angle
            FP dot = FPVector3.Dot(transform->Forward, hitTransform->Forward);
            
            // Head-on collision destroys both ships
            if (dot < FP._0_50)
            {
                DestroyShip(f, entity);
                DestroyShip(f, hitEntity);
            }
            // Side impact - destroy the ship that was hit from the side
            else if (dot > FP._0_50)
            {
                FP dot1 = FPVector3.Dot(transform->Forward, (hitTransform->Position - transform->Position).Normalized);
                FP dot2 = FPVector3.Dot(hitTransform->Forward, (transform->Position - hitTransform->Position).Normalized);
                
                if (dot1 > dot2)
                    DestroyShip(f, hitEntity);
                else
                    DestroyShip(f, entity);
            }
        }
    }
    else
    {
        // Handle ship-to-trail collision...
    }
}
```

Key aspects of ship-to-ship collisions:
1. **Impact Velocity**: Calculates the relative velocity between ships
2. **Threshold Check**: Only processes collisions above a minimum impact speed
3. **Collision Angle**: Determines the type of collision (head-on, side impact)
4. **Dual Destruction**: In head-on collisions, both ships are destroyed
5. **Side Impact Logic**: In side impacts, the ship hit from the side is destroyed

### 3. Ship-to-Trail Collision

When a ship collides with another ship's trail:

```csharp
private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
{
    // Self-collision handling...
    // Ship-to-ship collision handling...
    
    // This must be a ship-to-trail collision
    DestroyShip(f, entity);
    
    // Award points to the owner of the trail
    f.Unsafe.TryGetPointer(entity, out PlayerLink* victimLink);
    f.Unsafe.TryGetPointer(hitEntity, out PlayerLink* killerLink);
    
    if (victimLink != null && killerLink != null && victimLink->Player != killerLink->Player)
    {
        f.Global->playerData.Resolve(f, out var dict);
        dict.TryGetValuePointer(killerLink->Player, out var pd);
        pd->points += 50;
        
        f.Events.PlayerKilled(victimLink->Player, killerLink->Player);
    }
}
```

Key aspects of ship-to-trail collisions:
1. **Ship Destruction**: The colliding ship is always destroyed
2. **Point Awarding**: Points are awarded to the owner of the trail
3. **Player Verification**: Ensures both ships are owned by players and not the same player
4. **Kill Event**: Fires an event for UI feedback

## Ship Destruction

Ship destruction is handled by a common helper method:

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
    
    // Get position for explosion effect
    Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
    
    // Spawn explosion entity
    EntityRef explosion = f.Create(f.SimulationConfig.explosion);
    Transform3D* exTransform = f.Unsafe.GetPointer<Transform3D>(explosion);
    exTransform->Position = transform->Position;
    exTransform->Rotation = transform->Rotation;
    
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

Key aspects of ship destruction:
1. **Event Firing**: Sends an explosion event for visual/audio effects
2. **Delay Addition**: Adds a delay to prevent immediate respawning
3. **Destroyer Component**: Adds a component to mark the entity for cleanup
4. **Explosion Creation**: Spawns an explosion entity at the ship's position
5. **State Reset**: Resets the ship's score and boost amount
6. **Segment Clearing**: Removes all trail segments
7. **Query Cleanup**: Frees all physics queries to prevent memory leaks

## Spawn Protection

To prevent unfair collisions immediately after spawning, ships are given temporary spawn protection:

```csharp
public unsafe class SpawnProtectionSystem : SystemMainThreadFilter<SpawnProtectionSystem.Filter>, IGameState_Game
{
    public struct Filter
    {
        public EntityRef Entity;
        public SpawnProtection* Protection;
    }
    
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

The `SpawnProtection` component is added when a ship is spawned and automatically removed after a duration:

```qtn
component SpawnProtection
{
    FP TimeRemaining;
}
```

## Delay System

The `Delay` component is used to prevent immediate respawns after destruction:

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
                
                // Reposition the ship to a random spawn point
                if (f.Unsafe.TryGetPointer(filter.Entity, out Transform3D* transform))
                {
                    // Get random spawn position
                    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);
                    ShipSpec spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
                    
                    transform->Position = new FPVector3(
                        f.RNG->NextFP(-1, 1),
                        f.RNG->NextFP(-1, 1),
                        f.RNG->NextFP(-1, 1)
                    ).Normalized * (mm.mapRadius - spec.radius) + mm.mapOrigin;
                    
                    transform->Rotation = FPQuaternion.LookRotation(
                        -transform->Position.Normalized,
                        FPVector3.Up
                    );
                }
                
                // Add spawn protection
                f.Add<SpawnProtection>(filter.Entity, new SpawnProtection { 
                    TimeRemaining = FP._3
                });
            }
        }
    }
}
```

Key aspects of the delay system:
1. **Timer Countdown**: Decrements the remaining time each frame
2. **Component Removal**: Removes the Delay component when the timer expires
3. **Ship Respawning**: Handles respawning if the entity has a Destroyer component
4. **Position Randomization**: Places the ship at a random position on the sphere
5. **Spawn Protection**: Adds a SpawnProtection component to prevent immediate collisions

## Unity Visualization

The collision events are visualized in Unity using the `ShipView` class:

```csharp
public class ShipView : MonoBehaviour
{
    public GameObject explosionPrefab;
    
    void PlayerVulnerableCallback(EventPlayerVulnerable evt)
    {
        if (evt.Entity == EntityRef)
        {
            // Update ship material to show it's vulnerable
            prop.SetFloat("_Invulnerable", 0);
            foreach (Renderer ren in renderers) ren.SetPropertyBlock(prop);
        }
    }
    
    void OnDestroy()
    {
        // Player ship explosion effect
        if (explosionPrefab != null)
        {
            Instantiate(explosionPrefab, transform.position, transform.rotation);
        }
        
        // Unsubscribe from events
        QuantumEvent.UnsubscribeListener<EventPlayerVulnerable>(this);
        // Other event unsubscriptions...
    }
}
```

## Collision Events

The collision system generates several events for Unity visualization:

```qtn
// Ship exploded
event ShipExploded { entity_ref Entity; }

// Ship reconnected its trail
event PlayerReconnected { entity_ref Entity; Int32 SegmentCount; }

// Player was killed by another player
event PlayerKilled { player_ref Victim; player_ref Killer; }

// Ship is now vulnerable after spawn protection
event PlayerVulnerable { entity_ref Entity; }
```

These events trigger visual effects, sound effects, score updates, and other feedback in the Unity view.

## Best Practices

1. **System Separation**: Split collision detection and handling into separate systems
2. **Query Management**: Always free queries when no longer needed to prevent memory leaks
3. **Spawn Protection**: Use temporary invulnerability to prevent unfair deaths
4. **Collision Types**: Handle different collision scenarios with appropriate responses
5. **Delay Mechanism**: Use delay components to control timing of respawns
6. **Event Communication**: Use events to communicate collision information to the Unity view
7. **Resource Cleanup**: Clear trail segments and queries when ships are destroyed
8. **Alignment Checks**: Use dot products to assess collision angles and alignment quality
9. **Efficient Filtering**: Skip unnecessary collision checks (self, entities with protection)
