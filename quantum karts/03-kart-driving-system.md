# Quantum Karts Driving System

This document explains the kart driving system in Quantum Karts, covering the core physics, movement, and handling mechanics that create the kart racing experience.

## Core Components

The kart driving system consists of several interrelated components:

### Kart Component

The `Kart` component is the central element of the driving system, defined in `Kart.qtn`:

```qtn
component Kart {    
    [ExcludeFromPrototype] ComponentPrototypeRef Prototype;	
    [ExcludeFromPrototype] FPVector3 Velocity;	
    [ExcludeFromPrototype] FPVector3 OldVelocity;	
    [ExcludeFromPrototype] FPVector3 ExternalForce;	
    [ExcludeFromPrototype] FPVector3 CollisionPositionCompensation;
    [ExcludeFromPrototype] FP SidewaysSpeedSqr;
    [ExcludeFromPrototype] FP SurfaceFrictionMultiplier;
    [ExcludeFromPrototype] FP SurfaceSpeedMultiplier;
    [ExcludeFromPrototype] FP SurfaceHandlingMultiplier;
    [ExcludeFromPrototype] FPQuaternion TargetRotation;
    [ExcludeFromPrototype] byte GroundedWheels;
    [ExcludeFromPrototype] byte OffroadWheels;
    [ExcludeFromPrototype] FP AirTime;
    [ExcludeFromPrototype] FP OffroadTime;
    [ExcludeFromPrototype] PhysicsQueryRef OverlapQuery;
        
    asset_ref<KartStats> StatsAsset;
    asset_ref<KartVisuals> VisualAsset;
}
```

### KartStats Asset

The `KartStats` asset defines the movement characteristics of each kart:

```csharp
public unsafe partial class KartStats : AssetObject
{
    public FPVector3 overlapShapeSize;
    public FPVector3 overlapShapeOffset;
    public LayerMask overlapLayerMask;

    public FPAnimationCurve acceleration;
    public FPAnimationCurve turningRate;
    public FPAnimationCurve frictionEffect;
    public FP maxSpeed;
    public FP minThrottle;
    public FP gravity;
    public FP drag;
    public FP rotationCorrectionRate;
    public FP rotationSmoothingThreshold;
    public FP maxTilt;
    public FP groundDistance;
}
```

### Wheels Component

The `Wheels` component manages wheel physics and ground detection:

```qtn
component Wheels {
    [ExcludeFromPrototype] array<WheelStatus>[4] WheelStatuses;
    [ExcludeFromPrototype] FP SuspensionLength;
    [ExcludeFromPrototype] FP SuspensionTravel;
    [ExcludeFromPrototype] FP SuspensionStiffness;
    [ExcludeFromPrototype] FPVector3 COM;
    
    FPVector3 FrontLeft;
    FPVector3 FrontRight;
    FPVector3 RearLeft;
    FPVector3 RearRight;
}
```

## Physics Implementation

### Kart Movement

The core physics is implemented in the `Kart.Update` method:

```csharp
public unsafe partial struct Kart
{
    public bool IsGrounded => GroundedWheels > 1;
    public bool IsOffroad => OffroadWheels >= 4;

    public void Update(Frame frame, KartSystem.Filter filter)
    {
        Transform3D* transform = filter.Transform3D;
        Wheels* wheelComp = filter.Wheels;
        
        // Get kart stats
        var stats = frame.FindAsset(StatsAsset);
        
        // Process wheel information
        FPVector3 up = transform->Up;
        FPVector3 targetUp = up;
        FPVector3 averagePoint = transform->Position + FPVector3.Up * stats.groundDistance;
        
        GroundedWheels = 0;
        OffroadWheels = 0;
        SurfaceFrictionMultiplier = 0;
        SurfaceSpeedMultiplier = 1;
        SurfaceHandlingMultiplier = 1;
        
        // Process each wheel
        for (int i = 0; i < wheelComp->WheelStatuses.Length; i++)
        {
            WheelStatus* status = wheelComp->WheelStatuses.GetPointer(i);
            
            if (status->Grounded)
            {
                targetUp += status->HitNormal;
                averagePoint += status->HitPoint;
                GroundedWheels++;
                
                // Apply surface effects
                DrivingSurface surface = frame.FindAsset(status->HitSurface);
                SurfaceFrictionMultiplier += surface.FrictionMultiplier;
                SurfaceSpeedMultiplier += surface.SpeedMultiplier;
                SurfaceHandlingMultiplier += surface.HandlingMultiplier;
                
                if (surface.Offroad)
                {
                    OffroadWheels++;
                }
            }
        }
        
        // Average the values
        averagePoint /= (GroundedWheels + 1);
        targetUp /= (GroundedWheels + 1);
        
        SurfaceFrictionMultiplier /= wheelComp->WheelStatuses.Length;
        SurfaceSpeedMultiplier /= (GroundedWheels + 1);
        SurfaceHandlingMultiplier /= (GroundedWheels + 1);
        
        // Track airtime
        AirTime = !IsGrounded ? AirTime + frame.DeltaTime : 0;
        
        // Apply collision detection
        ApplyOverlapCollision(frame, filter.Entity);
        
        // Cap ground normal to a maximum tilt angle
        FP tiltAngle = FPVector3.Angle(targetUp, FPVector3.Up);
        if (tiltAngle > stats.maxTilt)
        {
            targetUp = FPVector3.Lerp(FPVector3.Up, targetUp, FPMath.InverseLerp(0, tiltAngle, stats.maxTilt));
        }
        
        // Calculate new position based on velocity
        FPVector3 newPosition = transform->Position + CollisionPositionCompensation + Velocity * frame.DeltaTime;
        
        // Handle ground alignment
        FPVector3 targetForward;
        
        if (IsGrounded)
        {
            // When grounded, align to surface
            Plane avgGround = new(averagePoint, targetUp);
            FP distance = avgGround.SignedDistanceTo(newPosition);
            
            // Remove gravity if close to ground
            if (distance < stats.groundDistance)
            {
                FP velocityToGround = FPVector3.Dot(Velocity, targetUp);
                
                if (velocityToGround < FP._0)
                {
                    Velocity -= targetUp * velocityToGround;
                }
                
                newPosition += (stats.groundDistance - distance) * targetUp;
            }
            
            targetForward = FPVector3.Cross(transform->Right, targetUp);
        }
        else
        {
            // In air, gradually align to level
            targetUp = FPVector3.MoveTowards(targetUp, FPVector3.Up,
                stats.rotationCorrectionRate * frame.DeltaTime);
            targetForward = FPVector3.Cross(transform->Right, targetUp);
        }
        
        // Rotation handling
        FPQuaternion lookRotation = FPQuaternion.LookRotation(targetForward, targetUp);
        FP angle = FPQuaternion.Angle(lookRotation, transform->Rotation);
        FP smoothing = FPMath.Clamp01(angle / stats.rotationSmoothingThreshold);
        FP wheelMultiplier = FP._0_25 + (FP._0_75 * (GroundedWheels / 4));
        FP lerp = FP._0_50 * smoothing * wheelMultiplier;
        
        lookRotation = FPQuaternion.Slerp(transform->Rotation, lookRotation, lerp);
        
        // Apply steering rotation
        bool hasInput = FPMath.Abs(filter.KartInput->GetTotalSteering()) > FP._0_05;
        if (hasInput)
        {
            lookRotation *= FPQuaternion.AngleAxis(
                filter.KartInput->GetTotalSteering()
                * SurfaceHandlingMultiplier
                * FPMath.Sign(FPVector3.Dot(Velocity, transform->Forward))
                * GetTurningRate(frame, filter.Drifting)
                * frame.DeltaTime,
                FPVector3.Up
            );
        }
        
        // Apply position and rotation
        transform->Position = newPosition;
        transform->Rotation = lookRotation;
        
        // Calculate sideways speed (used for drifting)
        SidewaysSpeedSqr = FPVector3.Project(Velocity, transform->Right).SqrMagnitude;
        
        // Apply physics forces
        Accelerate(frame, filter.Entity, filter.KartInput, transform->Forward);
        ApplyExternalForce(frame);
        ApplyGravity(frame, targetUp);
        ApplyFriction(frame, transform);
        ApplyDrag(frame);
        LimitVelocity(frame, filter.Entity);
        
        // Reset external force
        ExternalForce = FPVector3.Zero;
    }
    
    // Additional methods...
}
```

### Key Physics Methods

Several methods handle specific aspects of the kart physics:

#### Acceleration

```csharp
private void Accelerate(Frame frame, EntityRef entity, KartInput* input, FPVector3 direction)
{
    if (!IsGrounded)
    {
        return;
    }

    KartStats stats = frame.FindAsset(StatsAsset);

    Velocity += GetAcceleration(frame, entity) * frame.DeltaTime *
                FPMath.Clamp(input->Throttle, stats.minThrottle, 1) * direction;
}

public FP GetAcceleration(Frame frame, EntityRef entity)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    FP bonus = 0;

    if (frame.Unsafe.TryGetPointer(entity, out KartBoost* kartBoost) && kartBoost->CurrentBoost != null)
    {
        BoostConfig config = frame.FindAsset(kartBoost->CurrentBoost);
        bonus += config.AccelerationBonus;
    }

    return stats.acceleration.Evaluate(GetNormalizedSpeed(frame)) * SurfaceSpeedMultiplier + bonus;
}
```

#### Friction

```csharp
private void ApplyFriction(Frame frame, Transform3D* t)
{
    if (!IsGrounded)
    {
        return;
    }

    KartStats stats = frame.FindAsset(StatsAsset);

    FPVector3 frictionDirection = t->Right;
    FP frictionAmount = FPVector3.Dot(Velocity, frictionDirection);
    FP effect = stats.frictionEffect.Evaluate(GetNormalizedSpeed(frame));
    FPVector3 friction = frictionDirection * (frictionAmount * SurfaceFrictionMultiplier * effect);

    Velocity -= friction;
}
```

#### Gravity and Drag

```csharp
private void ApplyGravity(Frame frame, FPVector3 up)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    Velocity += up * stats.gravity * frame.DeltaTime * (IsGrounded ? FP._0_10 : FP._1);
}

private void ApplyDrag(Frame frame)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    Velocity -= Velocity * stats.drag * frame.DeltaTime * (IsGrounded ? FP._1 : FP._0_10);
}
```

#### Speed Limiting

```csharp
private void LimitVelocity(Frame frame, EntityRef entity)
{
    // No hard clamping so kart doesn't suddenly "hit a wall" when a boost ends
    Velocity = FPVector3.MoveTowards(
        Velocity,
        FPVector3.ClampMagnitude(Velocity, GetMaxSpeed(frame, entity)),
        FP._0_10
    );
}

public FP GetMaxSpeed(Frame frame, EntityRef entity)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    FP bonus = 0;

    if (frame.Unsafe.TryGetPointer(entity, out KartBoost* kartBoost) && kartBoost->CurrentBoost != null)
    {
        BoostConfig config = frame.FindAsset(kartBoost->CurrentBoost);
        bonus += config.MaxSpeedBonus;
    }

    return stats.maxSpeed * SurfaceSpeedMultiplier + bonus;
}
```

## Collision Handling

The kart system uses a custom overlap-based collision system rather than relying on the physics engine for more precise control:

```csharp
private void ApplyOverlapCollision(Frame frame, EntityRef entity)
{
    FP collisionSetback = FP._0;
    FPVector3 bounce = new();

    var hits = frame.Physics3D.GetQueryHits(OverlapQuery);
    if (hits.Count > 0)
    {
        for (int i = 0; i < hits.Count; i++)
        {
            Hit3D overlap = hits[i];

            if (overlap.Entity == entity) { continue; }

            // Don't pop out on the other side of thin obstacles
            FP dot = FPVector3.Dot(Velocity.Normalized, overlap.Normal);
            if (dot > 0) { continue; }

            // Don't sink further in the ground
            if (FPVector3.Dot(overlap.Normal, FPVector3.Down) > FP._0_50) { continue; }

            bounce += overlap.Normal;

            FPVector3 flatVelocity = Velocity;
            flatVelocity.Y = 0;

            Velocity -= dot * dot * flatVelocity * FP._0_50;

            collisionSetback = FPMath.Max(collisionSetback, overlap.OverlapPenetration);
        }

        bounce = bounce.Normalized;
    }

    bounce.Y = 0;

    CollisionPositionCompensation = bounce * collisionSetback;
}

public Shape3D GetOverlapShape(Frame frame)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    return Shape3D.CreateBox(stats.overlapShapeSize, stats.overlapShapeOffset);
}
```

## Wheel System

The wheel system is responsible for detecting the ground beneath each wheel and providing surface information:

```csharp
public unsafe class WheelQuerySystem : SystemMainThreadFilter<WheelQuerySystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform3D* Transform3D;
        public Wheels* Wheels;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        Transform3D* transform = filter.Transform3D;
        Wheels* wheels = filter.Wheels;
        
        FPVector3[] wheelPositions = new FPVector3[4];
        
        // Calculate world space position of each wheel
        wheelPositions[0] = transform->LocalToWorldPosition(wheels->FrontLeft);
        wheelPositions[1] = transform->LocalToWorldPosition(wheels->FrontRight);
        wheelPositions[2] = transform->LocalToWorldPosition(wheels->RearLeft);
        wheelPositions[3] = transform->LocalToWorldPosition(wheels->RearRight);
        
        // Center of mass offset
        wheels->COM = (wheelPositions[0] + wheelPositions[1] + wheelPositions[2] + wheelPositions[3]) / 4;
        
        // Perform raycasts for each wheel
        for (int i = 0; i < 4; i++)
        {
            FPVector3 startPos = wheelPositions[i] + transform->Up * wheels->SuspensionTravel;
            FPVector3 endPos = wheelPositions[i] - transform->Up * wheels->SuspensionLength;
            
            WheelStatus* status = wheels->WheelStatuses.GetPointer(i);
            
            status->Grounded = false;
            
            if (frame.Physics3D.Raycast(startPos, endPos, out var hit))
            {
                status->Grounded = true;
                status->HitPoint = hit.Point;
                status->HitNormal = hit.Normal;
                status->SuspensionCompression = 1 - (hit.Distance / (wheels->SuspensionLength + wheels->SuspensionTravel));
                
                // Get surface type from hit entity
                if (frame.Unsafe.TryGetPointer<DrivingSurface>(hit.Entity, out var surface))
                {
                    status->HitSurface = surface->SurfaceType;
                }
                else
                {
                    status->HitSurface = default;
                }
            }
        }
    }
}
```

## Surface System

Different surfaces can affect kart handling through the `DrivingSurface` component:

```csharp
public unsafe partial class DrivingSurface : AssetObject
{
    public bool Offroad;
    public FP FrictionMultiplier = 1;
    public FP SpeedMultiplier = 1;
    public FP HandlingMultiplier = 1;
    public ParticleRef EffectType;
}
```

The surface multipliers affect:
- **Friction**: How much sideways grip the kart has
- **Speed**: Maximum speed and acceleration
- **Handling**: How responsive steering is

## KartSystem Integration

The `KartSystem` ties all components together, filtering entities with the required components and updating them each frame:

```csharp
public unsafe class KartSystem : SystemMainThreadFilter<KartSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform3D* Transform3D;
        public Kart* Kart;
        public Wheels* Wheels;
        public KartInput* KartInput;
        public Drifting* Drifting;
        public RaceProgress* RaceProgress;
        public KartHitReceiver* KartHitReceiver;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        Input input = default;

        // Don't update karts during race setup
        if (!frame.Unsafe.TryGetPointerSingleton(out Race* race) || (race->CurrentRaceState < RaceState.InProgress))
        {
            // Handle ready toggle during waiting phase
            if (frame.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* playerLink)
                && frame.GetPlayerInput(playerLink->Player)->Respawn.WasPressed)
            {
                playerLink->Ready = !playerLink->Ready;
                frame.Events.LocalPlayerReady(playerLink->Player, playerLink->Ready);
            }

            return;
        }

        // Update race progress
        filter.RaceProgress->Update(frame, filter);

        // Skip update if respawning
        if (frame.Unsafe.TryGetPointer(filter.Entity, out RespawnMover* respawnMover))
        {
            return;
        }

        // Get input from AI or player
        if (frame.Unsafe.TryGetPointer(filter.Entity, out AIDriver* ai))
        {
            ai->Update(frame, filter, ref input);
        }
        else if (frame.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* playerLink))
        {
            input = *frame.GetPlayerInput(playerLink->Player);
        }

        // Handle respawn
        if (input.Respawn)
        {
            frame.Add<RespawnMover>(filter.Entity);
        }

        // Handle weapon usage
        if (input.Powerup.WasPressed && frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
        {
            weapons->UseWeapon(frame, filter);
        }

        // Update hit receiver
        filter.KartHitReceiver->Update(frame, filter);

        if (filter.KartHitReceiver->HitTimer > 0)
        {
            input.Direction = FPVector2.Zero;
            filter.Drifting->Direction = 0;
        }

        // Update all kart components
        filter.KartInput->Update(frame, input);
        filter.Wheels->Update(frame);
        filter.Drifting->Update(frame, filter);
        filter.Kart->Update(frame, filter);
    }
    
    // Additional methods for player connection, AI, spawning, etc.
}
```

## Best Practices

1. **Separation of Concerns**: Each aspect of kart physics is handled by a separate component/system
2. **Surface-based Effects**: Use driving surfaces to create varied terrain behavior
3. **Custom Collision**: Custom overlap detection for precise collision response
4. **Animation Curves**: Use FPAnimationCurve for non-linear physics behavior
5. **Wheel Raycasts**: Perform separate calculations for each wheel to handle uneven terrain
6. **Deterministic Math**: Always use Quantum's FP types for deterministic simulation
7. **Entity Filtering**: Use SystemMainThreadFilter for efficient component access
