# Lag Compensation in Quantum Simple FPS

This document explains the implementation of the Lag Compensation system in the Quantum Simple FPS sample project, covering historical state buffering, proxy entities, and fair hit detection.

## Lag Compensation Components

The lag compensation system is built on these components defined in the Quantum DSL:

```qtn
component LagCompensationTarget
{
    AssetRef<EntityPrototype> ProxyPrototype;
    [ExcludeFromPrototype]
    array<Transform3D>[32] Buffer;
    [ExcludeFromPrototype]
    int BufferIndex;
}

component LagCompensationProxy
{
    [ExcludeFromPrototype]
    EntityRef Target;
}
```

These components work together to:
1. Store historical transforms for player entities
2. Create proxy entities for lag-compensated hit detection
3. Map hits on proxy entities back to the original targets

## Lag Compensation Utility

The `LagCompensationUtility` class provides helper methods for the lag compensation systems:

```csharp
namespace Quantum
{
    public static class LagCompensationUtility
    {
        // Collision layers start from 0 and go up to 31 inclusive
        private const int BaseProxyLayer = 24;

        /// <summary>
        /// Gets proxy collision layer based on PlayerRef.
        /// Proxy layer is always in range 24-31.
        /// </summary>
        public static int GetProxyCollisionLayer(PlayerRef playerRef)
        {
            return BaseProxyLayer + (playerRef.Index % 8);
        }

        /// <summary>
        /// Gets proxy collision layer mask based on PlayerRef.
        /// This mask includes only the player's proxy layer.
        /// </summary>
        public static int GetProxyCollisionLayerMask(PlayerRef playerRef)
        {
            return 1 << GetProxyCollisionLayer(playerRef);
        }

        /// <summary>
        /// Get proxy collision layer mask that includes all proxy layers.
        /// </summary>
        public static int GetAllProxyCollisionLayerMask()
        {
            // Layers 24-31 are reserved for lag compensation proxies
            return 0xFF000000;
        }

        /// <summary>
        /// Interpolates transforms between two stored transforms based on alpha.
        /// </summary>
        public static Transform3D InterpolateTransform(Transform3D from, Transform3D to, FP alpha)
        {
            Transform3D result = default;
            result.Position = FPVector3.Lerp(from.Position, to.Position, alpha);
            result.Rotation = FPQuaternion.Slerp(from.Rotation, to.Rotation, alpha);
            result.Scale = FPVector3.Lerp(from.Scale, to.Scale, alpha);
            return result;
        }
    }
}
```

## Early Lag Compensation System

The `EarlyLagCompensationSystem` is responsible for buffering historical transforms of player entities:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class EarlyLagCompensationSystem : SystemMainThreadFilter<EarlyLagCompensationSystem.Filter>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            // Store current transform in the buffer
            var bufferIndex = (filter.LagCompensationTarget->BufferIndex + 1) % filter.LagCompensationTarget->Buffer.Length;
            filter.LagCompensationTarget->Buffer[bufferIndex] = *filter.Transform;
            filter.LagCompensationTarget->BufferIndex = bufferIndex;
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Transform3D* Transform;
            public LagCompensationTarget* LagCompensationTarget;
        }
    }
}
```

This system:
1. Runs every frame for entities with Transform3D and LagCompensationTarget components
2. Captures the current transform and stores it in a circular buffer
3. Updates the buffer index for next frame

The buffer size (32 frames) is carefully chosen to provide enough history for typical network latencies while keeping memory usage reasonable.

## Late Lag Compensation System

The `LateLagCompensationSystem` creates proxy entities for lag-compensated hit detection:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class LateLagCompensationSystem : SystemMainThreadFilter<LateLagCompensationSystem.Filter>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            if (filter.Health->IsAlive == false)
                return;

            // Iterate over all players - create a proxy for each player
            var players = frame.GetComponentIterator<Player>();
            while (players.MoveNext())
            {
                var (playerEntity, player) = players.Current;
                
                // Skip creating proxy for myself
                if (playerEntity == filter.Entity)
                    continue;
                
                if (player.PlayerRef.IsValid == false)
                    continue;

                // Create a proxy entity for this player to use for lag compensation
                // when another player shoots
                if (frame.Has<LagCompensationTarget>(playerEntity) == false)
                    continue;

                var targetLCT = frame.Get<LagCompensationTarget>(playerEntity);

                // Extract player input with interpolation data
                var input = frame.GetPlayerInput(player.PlayerRef);
                var offset = input->InterpolationOffset;
                var alpha = input->InterpolationAlpha;

                // The buffer is circular
                int currentIndex = targetLCT.BufferIndex;
                int pastIndex = (currentIndex - offset + targetLCT.Buffer.Length) % targetLCT.Buffer.Length;

                // Create proxy entity
                var proxyEntity = frame.Create(targetLCT.ProxyPrototype);

                // Link proxy to target
                var proxy = frame.Unsafe.GetPointer<LagCompensationProxy>(proxyEntity);
                proxy->Target = playerEntity;

                // Update proxy collider's layer
                var collider = frame.Unsafe.GetPointer<PhysicsCollider3D>(proxyEntity);
                collider->Layer = LagCompensationUtility.GetProxyCollisionLayer(filter.Player->PlayerRef);

                // Get transform for the proxy
                var proxyTransform = frame.Unsafe.GetPointer<Transform3D>(proxyEntity);

                // In case we don't have enough historical data, use the oldest available transform
                if (offset > currentIndex)
                {
                    *proxyTransform = targetLCT.Buffer[0];
                }
                // Interpolate between two buffered transforms
                else
                {
                    var fromTransform = targetLCT.Buffer[pastIndex];
                    var toTransform = targetLCT.Buffer[(pastIndex + 1) % targetLCT.Buffer.Length];

                    *proxyTransform = LagCompensationUtility.InterpolateTransform(fromTransform, toTransform, alpha);
                }
            }
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Player*   Player;
            public Health*   Health;
        }
    }
}
```

Key aspects of this system:
1. Runs for each player that has a player component
2. For each player, creates proxy entities for all other players
3. Uses the player's input.InterpolationOffset to determine how far back in time to look
4. Interpolates between buffered transforms based on input.InterpolationAlpha
5. Places proxy entities on unique collision layers based on the player's PlayerRef

The proxy entities are temporary and only exist for a single frame to handle hit detection.

## Lag Compensation Integration with Weapons

The weapons system integrates with lag compensation when firing projectiles:

```csharp
// From WeaponsSystem.FireProjectile method
private void FireProjectile(Frame frame, ref Filter filter, FPVector3 fromPosition, FPVector3 direction, FP maxDistance, FP damage, ref DamageData damageData)
{
    // Use default layer mask + add lag compensation proxy layer mask based on PlayerRef
    var hitMask = filter.Weapons->HitMask;
    hitMask.BitMask |= LagCompensationUtility.GetProxyCollisionLayerMask(filter.Player->PlayerRef);

    var options = QueryOptions.HitAll | QueryOptions.ComputeDetailedInfo;
    var nullableHit = frame.Physics3D.Raycast(fromPosition, direction, maxDistance, hitMask, options);

    if (nullableHit.HasValue == false)
    {
        // No surface was hit, show projectile visual flying to dummy distant point
        var distantPoint = fromPosition + direction * maxDistance;
        frame.Events.FireProjectile(filter.Weapons->CurrentWeaponId, filter.Entity, distantPoint, FPVector3.Zero);
        return;
    }

    Hit3D hit = nullableHit.Value;

    if (frame.Unsafe.TryGetPointer(hit.Entity, out LagCompensationProxy* lagCompensationProxy))
    {
        // Lag compensation proxy was hit, switching hit entity to its origin entity
        hit.SetHitEntity(lagCompensationProxy->Target);
    }

    // When hitting dynamic colliders (players), hit normal is set to zero and hit impact won't be shown
    var hitNormal = hit.IsDynamic ? FPVector3.Zero : hit.Normal;
    frame.Events.FireProjectile(filter.Weapons->CurrentWeaponId, filter.Entity, hit.Point, hitNormal);

    if (frame.Unsafe.TryGetPointer(hit.Entity, out Health* health) == false)
        return;

    // Apply damage to the entity...
}
```

Key aspects of this integration:
1. Each player's raycast includes their unique proxy layer mask
2. When a proxy entity is hit, the hit entity is redirected to the original target
3. Damage is applied to the original entity, not the proxy

## How Lag Compensation Works in Quantum Simple FPS

The Quantum Simple FPS lag compensation system follows these steps:

1. **Historical State Buffering**
   - Each player entity stores a circular buffer of 32 historical transforms
   - The `EarlyLagCompensationSystem` captures transforms every frame
   - This creates a rolling window of entity positions for the last 32 frames

2. **Proxy Entity Creation**
   - For each player, the `LateLagCompensationSystem` creates proxy entities for all other players
   - Proxy entities are positioned based on the target's historical position
   - The exact historical frame is determined by input.InterpolationOffset

3. **Time Offset from Input**
   - Each player's input contains InterpolationOffset and InterpolationAlpha
   - These values represent how far back in time the client is seeing other players
   - The offset is determined by the client's network latency and prediction settings

4. **Layer-Based Collision Filtering**
   - Each player's proxies are placed on a unique collision layer (24-31)
   - When a player fires, their raycast includes only their specific proxy layer
   - This ensures players only hit their own proxy versions of other players

5. **Entity Redirection on Hit**
   - When a proxy entity is hit, the hit entity is redirected to the original target
   - Damage and effects are applied to the original entity, not the proxy
   - This creates the illusion of hitting where the player saw the target

## Interpolation and Smoothing

The system includes interpolation between historical frames for smoother movement:

```csharp
public static Transform3D InterpolateTransform(Transform3D from, Transform3D to, FP alpha)
{
    Transform3D result = default;
    result.Position = FPVector3.Lerp(from.Position, to.Position, alpha);
    result.Rotation = FPQuaternion.Slerp(from.Rotation, to.Rotation, alpha);
    result.Scale = FPVector3.Lerp(from.Scale, to.Scale, alpha);
    return result;
}
```

This interpolation:
1. Uses linear interpolation (Lerp) for position and scale
2. Uses spherical interpolation (Slerp) for rotation
3. Creates smooth movement between historical frames
4. Is applied based on the input.InterpolationAlpha value

## Input Integration

The lag compensation system relies on interpolation data from player input:

```qtn
input
{
    // ... other input fields
    byte InterpolationOffset;
    byte InterpolationAlphaEncoded;
}
```

These values are captured on the client side during input polling:

```csharp
// In CharacterInputPoller.PollInput
input.InterpolationOffset = (byte)callback.InterpolationTarget;
input.InterpolationAlpha = FP.FromFloat_UNSAFE(callback.InterpolationAlpha);
```

The `InterpolationTarget` and `InterpolationAlpha` values are provided by Quantum's input callback and represent:
1. How many frames back in time this client is seeing other players
2. The fractional interpolation between historical frames

## Proxy Prototype Configuration

The proxy prototype is defined in the Unity Editor:

```csharp
// In LagCompensationTargetEditor.cs
[CustomEditor(typeof(QuantumLagCompensationTargetSettings))]
public class LagCompensationTargetEditor : QuantumEditorBehaviour
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();
        
        var settings = target as QuantumLagCompensationTargetSettings;
        
        if (settings.ProxyPrototype == null)
        {
            EditorGUILayout.HelpBox("The Proxy Prototype must be configured to use lag compensation.", MessageType.Warning);
            
            if (GUILayout.Button("Create Default Proxy Prototype"))
            {
                // Create a new entity prototype for the proxy
                var prototype = ScriptableObject.CreateInstance<EntityPrototypeAsset>();
                prototype.name = "LagCompensationProxy";
                
                // Add the required components
                prototype.Container.Add(new LagCompensationProxySettings());
                
                // Add the same colliders as the original entity
                var originalColliders = settings.GetComponent<QuantumCharacterSettings>()?.Colliders;
                if (originalColliders != null)
                {
                    var colliderSettings = new PhysicsCollider3DSettings();
                    colliderSettings.Shapes = originalColliders.Shapes;
                    prototype.Container.Add(colliderSettings);
                }
                
                // Add transform component
                prototype.Container.Add(new Transform3DSettings());
                
                // Save the prototype asset
                AssetDatabase.CreateAsset(prototype, 
                    AssetDatabase.GetAssetPath(settings).Replace(settings.name, "LagCompensationProxy.asset"));
                AssetDatabase.SaveAssets();
                
                // Assign the new prototype
                settings.ProxyPrototype = prototype;
                EditorUtility.SetDirty(settings);
            }
        }
    }
}
```

The proxy prototype typically includes:
1. A Transform3D component
2. A PhysicsCollider3D component with the same shapes as the original entity
3. A LagCompensationProxy component
4. Minimal components to keep the proxy lightweight

## Best Practices for FPS Lag Compensation

1. **Historical state buffering**: Store a sufficient number of past transforms
2. **Layer-based collision filtering**: Use unique layers for each player's proxies
3. **Entity redirection**: Map proxy hits back to original entities
4. **Interpolation between frames**: Smooth movement between historical positions
5. **Input-driven time offset**: Let client latency determine how far back to look
6. **Separate proxy prototypes**: Lightweight entities for efficient hit detection
7. **Early and late systems**: Split buffering and proxy creation for better organization
8. **Circular buffer optimization**: Reuse buffer slots to minimize memory usage
9. **Proper cleanup**: Proxies exist for only one frame to avoid accumulation

These practices ensure fair hit detection in a networked FPS, creating a much better player experience where "if you see it, you can hit it" regardless of network latency. The system is deterministic and runs on all clients, ensuring consistent results across the network.
