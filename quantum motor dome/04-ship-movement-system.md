# Quantum Motor Dome Ship Movement System

This document explains the ship movement system in Quantum Motor Dome, covering the core physics, movement mechanics, and trail implementation that forms the foundation of the gameplay.

## Core Components

The ship movement system consists of several interrelated components:

### Ship Component

The `Ship` component is the central element that defines a player-controlled ship:

```qtn
component Ship
{
	[Header("Runtime Properties")]
	FP BoostAmount;
	int Score;
	list<FPVector3> Segments;
	list<PhysicsQueryRef> SegmentQueries;

	[Header("Movement State")]
	FP SteerAmount;
	bool IsBraking;
	bool IsBoosting;
}
```

Key properties:
- `BoostAmount`: Current boost energy (0-100)
- `Score`: Player's current score (correlates to trail length)
- `Segments`: List of positions forming the ship's trail
- `SegmentQueries`: Physics queries for collision detection
- Movement state flags for steering, braking, and boosting

### ShipSpec Asset

The `ShipSpec` asset defines the movement characteristics of ships:

```csharp
public partial class ShipSpec : AssetObject
{
    public FP radius;
    public FP speedNormal;
    public FP speedBoosting;
    public FP speedBraking;
    public FP steerRate;
    public FP segmentDistance;
    public FP boostDrain;
    [Range(0, 1)] public FP connectThreshold;
    public FP despawnAfterConnectDelay;
}
```

Key properties:
- `radius`: Size of the ship for collision and positioning
- `speedNormal/speedBoosting/speedBraking`: Movement speeds under different states
- `steerRate`: How quickly the ship turns
- `segmentDistance`: Distance between trail segments
- `boostDrain`: How quickly boost energy depletes when used
- `connectThreshold`: Alignment threshold for successful trail reconnection
- `despawnAfterConnectDelay`: Delay before respawning after a successful reconnection

### MapMeta Asset

The `MapMeta` asset defines the spherical arena:

```csharp
public class MapMeta : AssetObject
{
    public FPVector3 mapOrigin;
    public FP mapRadius;
}
```

## ShipFilter

The movement system uses a filter to efficiently process only entities with the required components:

```csharp
public struct ShipFilter
{
    public EntityRef Entity;
    public Transform3D* Transform;
    public Ship* Player;
    public PlayerLink* Link;
}
```

## Ship Movement Implementation

The core ship movement logic is implemented in the `ShipMovementSystem`:

```csharp
unsafe class ShipMovementSystem : SystemMainThreadFilter<ShipFilter>, IGameState_Game
{
    public override bool StartEnabled => false;

    static ShipSpec spec;

    public override void OnInit(Frame f)
    {
        spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
    }

    public override void Update(Frame f, ref ShipFilter filter)
    {
        if (f.Has<Delay>(filter.Entity)) return;

        Input* input = f.GetPlayerInput(filter.Link->Player);

        Collections.QList<FPVector3> segs =
            f.ResolveList(filter.Player->Segments);

        if (segs.Count < filter.Player->Score)
        {
            segs.Add(filter.Transform->Position);
        }
        
        // Update ship state based on input
        filter.Player->SteerAmount = FPMath.Clamp(input->steer, -1, 1);
        filter.Player->IsBoosting = input->boost && filter.Player->BoostAmount > 0;
        filter.Player->IsBraking = input->brake;

        // Apply steering
        FP steerRate = filter.Player->SteerAmount * spec.steerRate;
        if (filter.Player->IsBraking) steerRate /= 2;

        filter.Transform->Rotation *= FPQuaternion.AngleAxis(steerRate * f.DeltaTime, FPVector3.Up);
        
        // Calculate speed based on input state
        FP speed = filter.Player->IsBoosting ? 
            spec.speedBoosting : 
            input->brake ? spec.speedBraking : spec.speedNormal;

        // Handle boost energy consumption
        if (filter.Player->IsBoosting)
        {
            filter.Player->BoostAmount -= spec.boostDrain * f.DeltaTime;
            if (filter.Player->BoostAmount < 0) filter.Player->BoostAmount = 0;
        }

        // Apply movement
        filter.Transform->Position += filter.Transform->Forward * speed * f.DeltaTime;
        
        // Orient to sphere surface
        Orient(f, filter.Transform, filter.Player);
        
        // Update trail segments
        if (segs.Count > 0)
        {
            FPVector3* ptr = segs.GetPointer(segs.Count - 1);
            *ptr = filter.Transform->Position;

            for (int i = segs.Count - 2; i >= 0; i--)
            {
                MoveDistance(f, segs.GetPointer(i), segs.GetPointer(i + 1), spec.segmentDistance, spec.radius);
            }
        }
    }
}
```

The system performs several key operations:
1. **Input Processing**: Retrieves and applies player input
2. **State Update**: Updates ship state based on input
3. **Steering**: Applies rotation based on steering input
4. **Speed Calculation**: Determines speed based on current state (normal/boosting/braking)
5. **Boost Management**: Consumes boost energy when boosting
6. **Position Update**: Moves the ship based on current speed and direction
7. **Orientation**: Ensures the ship stays properly oriented on the sphere
8. **Trail Management**: Updates the positions of trail segments

## Spherical Movement

One of the unique aspects of the game is that ships move on the surface of a sphere. This is handled by the `Orient` method:

```csharp
public static void Orient(Frame f, Transform3D* tf, Ship* player)
{
    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);

    // Calculate vector from sphere center to ship
    FPVector3 n = mm.mapOrigin - tf->Position;
    
    // Project ship onto sphere surface at the correct radius
    tf->Position =
        (tf->Position - mm.mapOrigin).Normalized
        * (mm.mapRadius - spec.radius)
        + mm.mapOrigin;

    // Rotate ship to align with sphere surface
    tf->Rotation = FPQuaternion.FromToRotation(tf->Up, n) * tf->Rotation;
}
```

This method:
1. Gets the vector from the sphere center to the ship
2. Projects the ship onto the sphere surface, accounting for ship radius
3. Reorients the ship to align with the sphere surface

## Trail System

The trail system is a core gameplay mechanic. Each ship leaves a trail of segments behind it, which is implemented as a list of positions:

```csharp
// Add a new segment if needed
if (segs.Count < filter.Player->Score)
{
    segs.Add(filter.Transform->Position);
}

// Update the most recent segment to follow the ship
if (segs.Count > 0)
{
    FPVector3* ptr = segs.GetPointer(segs.Count - 1);
    *ptr = filter.Transform->Position;

    // Update all other segments to maintain proper spacing
    for (int i = segs.Count - 2; i >= 0; i--)
    {
        MoveDistance(f, segs.GetPointer(i), segs.GetPointer(i + 1), spec.segmentDistance, spec.radius);
    }
}
```

The `MoveDistance` method ensures that trail segments:
1. Maintain proper spacing between segments
2. Stay on the sphere surface
3. Form a smooth trail behind the ship

```csharp
static void MoveDistance(Frame f, FPVector3* src, FPVector3* dest, FP distance, FP mapOffset)
{
    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);

    FPVector3 d = *src - *dest;

    if (d.SqrMagnitude > distance * distance)
    {
        // Move segment toward next segment to maintain spacing
        *src = *dest + d.Normalized * distance;
        
        // Project segment onto sphere surface
        *src = (*src - mm.mapOrigin).Normalized
            * (mm.mapRadius - mapOffset)
            + mm.mapOrigin;
    }
}
```

## Trail Growth

The `Score` property of the `Ship` component determines how many trail segments the ship should have. When the score increases (e.g., through pickup collection), the trail grows:

```csharp
public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
{
    // Skip non-pickup collisions
    if (!f.TryGet(info.Other, out TrailPickup pickup)) return;
    if (!f.Unsafe.TryGetPointer(info.Entity, out Ship* ship)) return;
    if (!f.TryGet(info.Entity, out PlayerLink link)) return;

    // Increase score (trail length)
    int oldScore = ship->Score;
    ship->Score += ship->Score > 0 ? 5 : 2;
    f.Events.PlayerScoreChanged(link.Player, oldScore, ship->Score);
    
    // Destroy pickup
    f.Destroy(info.Other);
    
    // Spawn new pickup if needed
    if (f.ComponentCount<TrailPickup>() < PickupSystem<TrailPickup>.SpawnCap(f))
    {
        PickupSystem<TrailPickup>.SpawnPickup(f);
    }
}
```

## Collision Queries

The game needs to detect collisions between ships and trails. This is handled by two systems working together:

1. **ShipCollisionInjectionSystem**: Creates physics queries for each trail segment:

```csharp
public unsafe class ShipCollisionInjectionSystem : SystemMainThread, IGameState_Game
{
    public override void Update(Frame f)
    {
        foreach (var (entity, ship) in f.Unsafe.GetComponentBlockIterator<Ship>())
        {
            if (f.Has<Delay>(entity)) continue;
            
            // Get ship segments
            Collections.QList<FPVector3> segments = f.ResolveList(ship.Segments);
            if (segments.Count < 2) continue;
            
            // Free existing queries
            Collections.QList<PhysicsQueryRef> queries = f.ResolveList(ship.SegmentQueries);
            foreach (var query in queries)
            {
                f.Physics3D.FreeQuery(query);
            }
            queries.Clear();
            
            // Create linecast queries between segments
            for (int i = 0; i < segments.Count - 1; i++)
            {
                FPVector3 start = segments[i];
                FPVector3 end = segments[i + 1];
                
                // Create linecast query
                PhysicsQueryRef query = f.Physics3D.Linecast(
                    start, 
                    end, 
                    0, 
                    entity
                );
                queries.Add(query);
            }
        }
    }
}
```

2. **ShipCollisionRetrievalSystem**: Processes the results of those queries:

```csharp
public unsafe class ShipCollisionRetrievalSystem : SystemMainThread, IGameState_Game
{
    public override void Update(Frame f)
    {
        foreach (var (entity, ship) in f.Unsafe.GetComponentBlockIterator<Ship>())
        {
            if (f.Has<Delay>(entity) || f.Has<SpawnProtection>(entity)) continue;
            
            // Process linecast results
            Collections.QList<PhysicsQueryRef> queries = f.ResolveList(ship.SegmentQueries);
            for (int i = 0; i < queries.Count; i++)
            {
                PhysicsQueryRef query = queries[i];
                var results = f.Physics3D.GetLinecastHits(query);
                
                foreach (var hit in results)
                {
                    // Skip hits with self and ships with spawn protection
                    if (hit.Entity == entity) continue;
                    if (f.Has<SpawnProtection>(hit.Entity)) continue;
                    
                    // Trigger collision
                    HandleCollision(f, entity, hit.Entity, i);
                }
            }
        }
    }
    
    private void HandleCollision(Frame f, EntityRef shipEntity, EntityRef hitEntity, int segmentIndex)
    {
        // Implementation of collision response
        // (e.g., destroy ship, spawn explosion, etc.)
    }
}
```

## Trail Reconnection

A key gameplay mechanic is the ability to reconnect a ship's trail to itself, scoring points:

```csharp
private void HandleCollision(Frame f, EntityRef shipEntity, EntityRef hitEntity, int segmentIndex)
{
    // Skip if not a ship
    if (!f.Unsafe.TryGetComponent(hitEntity, out Ship hitShip)) return;
    
    // Check if we hit our own trail
    if (hitEntity == shipEntity)
    {
        // Check if this is the head segment reconnecting to the tail
        if (segmentIndex == 0)
        {
            ShipSpec spec = f.FindAsset<ShipSpec>(f.SimulationConfig.shipSpec.Id);
            Ship* ship = f.Unsafe.GetPointer<Ship>(shipEntity);
            
            // Get segments
            Collections.QList<FPVector3> segments = f.ResolveList(ship->Segments);
            if (segments.Count < spec.minReconnectSegments) return;
            
            // Check alignment quality
            Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(shipEntity);
            FP dot = FPVector3.Dot(
                transform->Forward,
                (segments[1] - segments[0]).Normalized
            );
            
            // Reconnection successful if alignment is good
            if (dot > spec.connectThreshold)
            {
                // Award points
                f.Unsafe.TryGetPointer(shipEntity, out PlayerLink* link);
                int points = ship->Score * ship->Score / 10;
                f.Events.PlayerScored(link->Player, points);
                
                // Reset ship
                f.Add<Delay>(shipEntity, new Delay { TimeRemaining = spec.despawnAfterConnectDelay });
                f.Events.PlayerReconnected(shipEntity, segments.Count);
            }
        }
    }
    else
    {
        // Handle ship-to-ship collision
        // Implementation details...
    }
}
```

The reconnection mechanic:
1. Checks if a ship has collided with its own trail
2. Verifies it's the head segment connecting to a point in the trail
3. Checks alignment quality (ship must be facing in a similar direction as the trail)
4. Awards points based on trail length
5. Triggers a respawn after a delay

## Unity Visualization

The Unity-side `ShipView` class visualizes the ship and its trail:

```csharp
public unsafe class ShipView : MonoBehaviour
{
    public Transform pivot;
    public Transform socket;
    public Transform reconnectTarget;
    [SerializeField] LineRenderer ren;
    public LineRenderer trailRenderer;
    
    private void Update()
    {
        Ship* player = game.Frames.Predicted.Unsafe.GetPointer<Ship>(EntityRef);
        Quantum.Collections.QList<Photon.Deterministic.FPVector3> segs = 
            game.Frames.Predicted.ResolveList(player->Segments);

        // Update trail renderer
        ren.positionCount = segs.Count;
        for (int i = 0; i < segs.Count; i++)
        {
            Photon.Deterministic.FPVector3* seg = segs.GetPointer(i);
            ren.SetPosition(i, seg->ToUnityVector3());
        }

        // Handle trail disconnection visual
        if (trailSegs <= 1 && segs.Count > 1)
        {
            // disconnect socket from ship
            socket.SetParent(transform);
        }

        trailSegs = segs.Count;

        // Position trail socket
        if (trailSegs > 1)
        {
            Vector3 end = segs.GetPointer(0)->ToUnityVector3();
            Vector3 next = segs.GetPointer(1)->ToUnityVector3();
            socket.position = end;
            socket.rotation = Quaternion.LookRotation(next - end, -end);
        }
        
        // Apply visual effects for steering
        Quaternion rollRot = Quaternion.AngleAxis(player->SteerAmount.AsFloat * -rollAmount, Vector3.forward);
        Quaternion oversteerRot = Quaternion.Euler(0, player->SteerAmount.AsFloat * oversteerAmount, 0);
        Quaternion tgtRot = oversteerRot * rollRot;
        Quaternion srcRot = pivot.localRotation;
        pivot.localRotation = Quaternion.RotateTowards(
            srcRot, 
            tgtRot, 
            Mathf.Sqrt(Quaternion.Angle(srcRot, tgtRot)) * steerVisualRate * Time.deltaTime
        );

        // Handle boost audio
        wasBoosting = player->IsBoosting;
    }
}
```

Key aspects of the visualization:
1. **Trail Rendering**: Uses a LineRenderer to visualize the trail segments
2. **Trail Socket**: Visual connection point for the start of the trail
3. **Steering Effects**: Applies visual tilt and oversteer based on steering input
4. **Boost Effects**: Plays audio and visual effects when boosting

## Best Practices

1. **Separation of Systems**: Split functionality into focused systems (movement, collision detection, collision response)
2. **Efficient Queries**: Use physics queries for collision detection rather than manual checks
3. **Trail Management**: Keep trail segments properly spaced and oriented on the sphere
4. **Visual Feedback**: Apply smooth visual effects to make movement feel natural
5. **Resource Management**: Manage resources like boost energy and explicitly free physics queries
6. **Spherical Projection**: Consistently project positions onto the sphere surface
7. **State-Based Speed**: Vary speed based on current state (normal/boosting/braking)
8. **Configurable Parameters**: Store movement parameters in configurable assets
