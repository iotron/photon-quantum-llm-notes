# Ball Handling System

This document details the ball handling mechanics in the Quantum Arena Brawler, covering ball physics, catching/throwing mechanics, and view interpolation.

## Ball State Structure

The ball is managed through a `BallStatus` component that tracks its state:

```csharp
component BallStatus
{
    [ExcludeFromPrototype] entity_ref HoldingPlayerEntityRef;
    [ExcludeFromPrototype] CountdownTimer GravityChangeTimer;
    [ExcludeFromPrototype] CountdownTimer CatchTimeoutTimer;
    [ExcludeFromPrototype] player_ref CatchTimeoutPlayerRef;
    [ExcludeFromPrototype] bool HasCollisionEnter;
    [ExcludeFromPrototype] bool HasCollision;
    asset_ref<BallHandlingData> BallHandlingData;
}
```

This component tracks:
- Which player is holding the ball (if any)
- A timer for gravity scale changes after throwing
- A timeout to prevent immediate recatching by the same player
- Collision state for physics handling
- Configuration data reference

## Ball Handling System

The system that manages all ball interactions is implemented in the `BallHandlingSystem` class:

```csharp
public unsafe class BallHandlingSystem : SystemMainThreadFilter<BallHandlingSystem.Filter>, 
    ISignalOnBallReleased, 
    ISignalOnBallDropped, 
    ISignalOnBallPhysicsReset, 
    ISignalOnCollisionEnter3D, 
    ISignalOnCollision3D
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public BallStatus* BallStatus;
        public Transform3D* Transform;
        public PhysicsBody3D* PhysicsBody;
        public PhysicsCollider3D* Collider;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        BallHandlingData ballHandlingData = frame.FindAsset<BallHandlingData>(filter.BallStatus->BallHandlingData.Id);

        if (filter.BallStatus->IsHeldByPlayer)
        {
            CarryBall(frame, ref filter, ballHandlingData);
        }
        else
        {
            AttemptCatchBall(frame, ref filter, ballHandlingData);
        }

        UpdateBallGravityScale(frame, ref filter, ballHandlingData);
        HandleBallCollisions(frame, ref filter, ballHandlingData);

        filter.BallStatus->CatchTimeoutTimer.Tick(frame.DeltaTime);
    }
    
    // Additional methods for ball handling...
}
```

## Ball Catching Mechanics

The system checks for potential catches when the ball is not being held:

```csharp
private void AttemptCatchBall(Frame frame, ref Filter filter, BallHandlingData ballHandlingData)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    Shape3D sphereShape = Shape3D.CreateSphere(ballHandlingData.CatchRadius);
    HitCollection3D hitCollection = frame.Physics3D.OverlapShape(
        filter.Transform->Position, 
        FPQuaternion.Identity, 
        sphereShape, 
        gameSettingsData.PlayerLayerMask);

    hitCollection.SortCastDistance();
    for (int i = 0; i < hitCollection.Count; i++)
    {
        Hit3D hit = hitCollection[i];

        if (!CanCatchBall(frame, ref filter, hit.Entity))
        {
            continue;
        }

        CatchBall(frame, ref filter, hit.Entity, ballHandlingData);
        break;
    }
}

private bool CanCatchBall(Frame frame, ref Filter filter, EntityRef playerEntityRef)
{
    PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);

    if (playerStatus->IsIncapacitated)
    {
        return false;
    }

    if (playerStatus->IsHoldingBall)
    {
        return false;
    }

    if (filter.BallStatus->CatchTimeoutTimer.IsRunning)
    {
        // Allow different players to catch immediately, but prevent same player from catching
        return filter.BallStatus->CatchTimeoutPlayerRef != playerStatus->PlayerRef;
    }

    return true;
}
```

When a catch happens, the ball is attached to the player:

```csharp
private void CatchBall(Frame frame, ref Filter filter, EntityRef playerEntityRef, BallHandlingData ballHandlingData)
{
    PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
    PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(playerStatus->PlayerMovementData.Id);

    // Link ball and player
    playerStatus->HoldingBallEntityRef = filter.EntityRef;
    filter.BallStatus->HoldingPlayerEntityRef = playerEntityRef;

    // Disable physics on the ball
    filter.Collider->Enabled = false;
    filter.PhysicsBody->IsKinematic = true;
    frame.Signals.OnBallPhysicsReset(filter.EntityRef);

    // Update player KCC settings to reflect holding the ball
    playerMovementData.UpdateKCCSettings(frame, playerEntityRef);

    // Position the ball on the player
    CarryBall(frame, ref filter, ballHandlingData);

    // Trigger event
    frame.Events.OnPlayerCaughtBall(playerEntityRef, filter.EntityRef);
}

private void CarryBall(Frame frame, ref Filter filter, BallHandlingData ballHandlingData)
{
    Transform3D* playerTransform = frame.Unsafe.GetPointer<Transform3D>(filter.BallStatus->HoldingPlayerEntityRef);

    // Position the ball relative to the player
    filter.Transform->Position = playerTransform->Position + 
                               (playerTransform->Rotation * ballHandlingData.DropLocalPosition);
}
```

## Ball Throwing

When a player throws the ball, the `ThrowBallAbilityData` (shown in the ability system document) performs the core logic, but the BallHandlingSystem handles the ball release:

```csharp
public void OnBallReleased(Frame frame, EntityRef ballEntityRef)
{
    BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
    BallHandlingData ballHandlingData = frame.FindAsset<BallHandlingData>(ballStatus->BallHandlingData.Id);
    PhysicsBody3D* ballPhysicsBody = frame.Unsafe.GetPointer<PhysicsBody3D>(ballEntityRef);
    PhysicsCollider3D* ballCollider = frame.Unsafe.GetPointer<PhysicsCollider3D>(ballEntityRef);

    EntityRef playerEntityRef = ballStatus->HoldingPlayerEntityRef;
    PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
    PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(playerStatus->PlayerMovementData.Id);

    // Unlink ball and player
    ballStatus->HoldingPlayerEntityRef = default;
    ballStatus->CatchTimeoutTimer.Start(ballHandlingData.CatchTimeout);
    ballStatus->CatchTimeoutPlayerRef = playerStatus->PlayerRef;

    // Re-enable physics
    ballCollider->Enabled = true;
    ballPhysicsBody->IsKinematic = false;

    // Update player
    playerStatus->HoldingBallEntityRef = default;
    playerMovementData.UpdateKCCSettings(frame, playerEntityRef);
}
```

## Customized Ball Physics

### Variable Gravity Scale

One key feature is the customized gravity scale that changes over time after a throw:

```csharp
private void UpdateBallGravityScale(Frame frame, ref Filter filter, BallHandlingData ballHandlingData)
{
    if (filter.BallStatus->GravityChangeTimer.IsRunning)
    {
        // Use a curve to gradually change gravity from 0 to 1
        FP gravityScale = ballHandlingData.ThrowGravityChangeCurve.Evaluate(
            filter.BallStatus->GravityChangeTimer.NormalizedTime);
        
        filter.PhysicsBody->GravityScale = gravityScale;

        filter.BallStatus->GravityChangeTimer.Tick(frame.DeltaTime);
        if (filter.BallStatus->GravityChangeTimer.IsDone)
        {
            ResetBallGravity(frame, filter.EntityRef);
        }
    }
}

private void ResetBallGravity(Frame frame, EntityRef ballEntityRef)
{
    BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
    PhysicsBody3D* physicsBody = frame.Unsafe.GetPointer<PhysicsBody3D>(ballEntityRef);

    ballStatus->GravityChangeTimer.Reset();
    physicsBody->GravityScale = FP._1;
}
```

This variable gravity allows for:
- Initial flat trajectories for short passes (zero gravity)
- Gradually increasing gravity to create natural arcs
- Better control over the throw distance and height

### Custom Friction

The system adds lateral friction to the ball when it collides with surfaces, creating more consistent and controllable physics:

```csharp
public void OnCollisionEnter3D(Frame frame, CollisionInfo3D info)
{
    if (frame.Unsafe.TryGetPointer(info.Entity, out BallStatus* ballStatus))
    {
        ballStatus->HasCollisionEnter = true;
    }
}

public void OnCollision3D(Frame frame, CollisionInfo3D info)
{
    if (frame.Unsafe.TryGetPointer(info.Entity, out BallStatus* ballStatus))
    {
        ballStatus->HasCollision = true;
    }
}

private void HandleBallCollisions(Frame frame, ref Filter filter, BallHandlingData ballHandlingData)
{
    if (!filter.PhysicsBody->IsKinematic)
    {
        if (filter.BallStatus->HasCollisionEnter)
        {
            // Apply bounce friction to reduce lateral velocity on collision
            filter.PhysicsBody->Velocity.X *= ballHandlingData.LateralBounceFriction;
            filter.PhysicsBody->Velocity.Z *= ballHandlingData.LateralBounceFriction;

            frame.Events.OnBallBounced(filter.EntityRef);
        }

        if (filter.BallStatus->HasCollision)
        {
            // Apply ground friction to slow the ball when rolling
            filter.PhysicsBody->Velocity.X *= ballHandlingData.LateralGroundFriction;
            filter.PhysicsBody->Velocity.Z *= ballHandlingData.LateralGroundFriction;
        }
    }

    filter.BallStatus->HasCollisionEnter = false;
    filter.BallStatus->HasCollision = false;
}
```

This dual friction system provides:
- Initial impact friction on bounces
- Continuous friction when the ball is in contact with the ground
- More natural ball behavior without having to manually tune the physics materials

## Ball Dropping

The ball can be dropped (as opposed to thrown) when a player is knocked off the arena or stunned:

```csharp
public void OnBallDropped(Frame frame, EntityRef ballEntityRef)
{
    BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
    BallHandlingData ballHandlingData = frame.FindAsset<BallHandlingData>(ballStatus->BallHandlingData.Id);
    Transform3D* ballTransform = frame.Unsafe.GetPointer<Transform3D>(ballEntityRef);
    PhysicsBody3D* ballPhysicsBody = frame.Unsafe.GetPointer<PhysicsBody3D>(ballEntityRef);

    Transform3D* playerTransform = frame.Unsafe.GetPointer<Transform3D>(ballStatus->HoldingPlayerEntityRef);

    // Release the ball
    frame.Signals.OnBallReleased(ballEntityRef);

    // Position it at drop location
    ballTransform->Position = playerTransform->Position + 
                            (playerTransform->Rotation * ballHandlingData.DropLocalPosition);

    // Apply a small random impulse when dropping
    FPVector3 dropImpulse = new FPVector3(
        frame.RNG->NextInclusive(ballHandlingData.DropMinImpulse.X, ballHandlingData.DropMaxImpulse.X),
        frame.RNG->NextInclusive(ballHandlingData.DropMinImpulse.Y, ballHandlingData.DropMaxImpulse.Y),
        frame.RNG->NextInclusive(ballHandlingData.DropMinImpulse.Z, ballHandlingData.DropMaxImpulse.Z));

    FPVector3 impulseRelativePoint = ballPhysicsBody->CenterOfMass;
    impulseRelativePoint.Y += ballHandlingData.DropImpulseOffsetY;

    ballPhysicsBody->AddLinearImpulse(playerTransform->Rotation * dropImpulse, impulseRelativePoint);
}
```

## Ball Respawning

The ball can be respawned when it falls off the arena or when a goal is scored:

```csharp
public unsafe class BallSpawnSystem : SystemMainThreadFilter<BallSpawnSystem.Filter>, 
    ISignalOnBallSpawned, 
    ISignalOnBallRespawned, 
    ISignalOnBallDespawned
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public BallSpawner* BallSpawner;
        public Transform3D* Transform;
    }

    private EntityRef _spawnedBallEntityRef;

    public override void Update(Frame frame, ref Filter filter)
    {
        // Check if ball fell out of bounds
        if (_spawnedBallEntityRef != default)
        {
            BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(_spawnedBallEntityRef);
            Transform3D* ballTransform = frame.Unsafe.GetPointer<Transform3D>(_spawnedBallEntityRef);
            
            if (ballTransform->Position.Y < -10)  // Out of bounds check
            {
                frame.Signals.OnBallRespawned(_spawnedBallEntityRef);
            }
        }
    }

    public void OnBallSpawned(Frame frame)
    {
        var filtered = frame.Filter<BallSpawner, Transform3D>();
        if (!filtered.Next(out EntityRef spawnerEntityRef, out _, out _))
        {
            return;
        }

        Transform3D* spawnerTransform = frame.Unsafe.GetPointer<Transform3D>(spawnerEntityRef);
        
        // Create the ball entity
        EntityPrototype ballPrototype = frame.FindAsset<EntityPrototype>("Ball");
        _spawnedBallEntityRef = frame.Create(ballPrototype, spawnerTransform->Position, spawnerTransform->Rotation);
    }

    public void OnBallRespawned(Frame frame, EntityRef ballEntityRef)
    {
        var filtered = frame.Filter<BallSpawner, Transform3D>();
        if (!filtered.Next(out EntityRef spawnerEntityRef, out _, out _))
        {
            return;
        }

        Transform3D* spawnerTransform = frame.Unsafe.GetPointer<Transform3D>(spawnerEntityRef);
        
        // Reset the ball position
        Transform3D* ballTransform = frame.Unsafe.GetPointer<Transform3D>(ballEntityRef);
        ballTransform->Position = spawnerTransform->Position;
        
        // Reset physics
        frame.Signals.OnBallPhysicsReset(ballEntityRef);
        
        // Make sure the ball isn't held by any player
        BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
        if (ballStatus->IsHeldByPlayer)
        {
            EntityRef playerEntityRef = ballStatus->HoldingPlayerEntityRef;
            PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
            
            playerStatus->HoldingBallEntityRef = default;
            ballStatus->HoldingPlayerEntityRef = default;
            
            // Update player KCC settings
            PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(playerStatus->PlayerMovementData.Id);
            playerMovementData.UpdateKCCSettings(frame, playerEntityRef);
        }
    }

    public void OnBallDespawned(Frame frame, EntityRef ballEntityRef)
    {
        // Release ball if held by player
        BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
        if (ballStatus->IsHeldByPlayer)
        {
            EntityRef playerEntityRef = ballStatus->HoldingPlayerEntityRef;
            PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
            
            playerStatus->HoldingBallEntityRef = default;
            ballStatus->HoldingPlayerEntityRef = default;
            
            // Update player KCC settings
            PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(playerStatus->PlayerMovementData.Id);
            playerMovementData.UpdateKCCSettings(frame, playerEntityRef);
        }
        
        // Destroy the ball entity
        frame.Destroy(ballEntityRef);
        _spawnedBallEntityRef = default;
    }
}
```

## Ball View Interpolation

On the Unity side, the BallEntityView handles interpolation between simulation position and animated position:

```csharp
public unsafe class BallEntityView : QuantumEntityView
{
    [SerializeField] private float _spaceTransitionSpeed = 4f;

    private EntityRef _holdingPlayerEntityRef;
    private float _interpolationSpaceAlpha;

    private Vector3 _lastBallRealPosition;
    private Quaternion _lastBallRealRotation;

    private Vector3 _lastBallAnimationPosition;
    private Quaternion _lastBallAnimationRotation;

    protected override void ApplyTransform(ref UpdatePositionParameter param)
    {
        base.ApplyTransform(ref param);

        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(EntityRef);

        _holdingPlayerEntityRef = ballStatus->HoldingPlayerEntityRef;
    }

    public void UpdateSpaceInterpolation()
    {
        bool isBallHeldByPlayer = _holdingPlayerEntityRef != default;
        UpdateInterpolationSpaceAlpha(isBallHeldByPlayer);

        if (isBallHeldByPlayer)
        {
            // Get animation position from the player's ball mount point
            PlayerViewController player = PlayersManager.Instance.GetPlayer(_holdingPlayerEntityRef);

            _lastBallAnimationPosition = player.BallFollowTransform.position;
            _lastBallAnimationRotation = player.BallFollowTransform.rotation;
        }
        else
        {
            // Track the real position from simulation
            _lastBallRealPosition = transform.position;
            _lastBallRealRotation = transform.rotation;
        }

        if (_interpolationSpaceAlpha > 0f)
        {
            // Blend between real simulation position and animated position
            Vector3 interpolatedPosition = Vector3.Lerp(_lastBallRealPosition, _lastBallAnimationPosition, _interpolationSpaceAlpha);
            Quaternion interpolatedRotation = Quaternion.Slerp(_lastBallRealRotation, _lastBallAnimationRotation, _interpolationSpaceAlpha);

            transform.SetPositionAndRotation(interpolatedPosition, interpolatedRotation);
        }
    }

    private void UpdateInterpolationSpaceAlpha(bool isBallHeldByPlayer)
    {
        float deltaChange = _spaceTransitionSpeed * Time.deltaTime;
        if (isBallHeldByPlayer)
        {
            _interpolationSpaceAlpha += deltaChange;
        }
        else
        {
            _interpolationSpaceAlpha -= deltaChange;
        }

        _interpolationSpaceAlpha = Mathf.Clamp(_interpolationSpaceAlpha, 0f, 1f);
    }
}
```

This interpolation system handles the transition between:
1. **Simulation Space**: When the ball is free-moving, the Quantum physics system controls it
2. **Animation Space**: When held by a player, the Unity animation system can take over

The gradual transition between these spaces makes for smooth visuals even when quickly changing states.

## Ball Data Configuration

The `BallHandlingData` asset defines all configurable aspects of the ball:

```csharp
[CreateAssetMenu(menuName = "Quantum/Arena Brawler/Ball Handling Data")]
public class BallHandlingData : AssetObject
{
    [Header("Catching")]
    public FP CatchRadius = 1;
    public FP CatchTimeout = 1;
    
    [Header("Carrying")]
    public FPVector3 DropLocalPosition = new FPVector3(0, 1, 0);
    
    [Header("Dropping")]
    public FPVector3 DropMinImpulse = new FPVector3(-1, 2, -1);
    public FPVector3 DropMaxImpulse = new FPVector3(1, 3, 1);
    public FP DropImpulseOffsetY = FP._0_25;
    
    [Header("Physics")]
    public FP LateralBounceFriction = FP._0_80;
    public FP LateralGroundFriction = FP._0_98;
    
    [Header("Gravity")]
    public FPAnimationCurve ThrowGravityChangeCurve;
}
```

This data-driven approach allows for easy tuning and experimentation with ball physics without code changes.
