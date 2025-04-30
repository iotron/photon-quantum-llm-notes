# Player System

This document describes the player-related systems in the Quantum Arena Brawler, including movement, status effects, and respawning.

## Player Components

### PlayerStatus Component

The core component that tracks player state:

```csharp
component PlayerStatus
{
    [ExcludeFromPrototype] player_ref PlayerRef;
    [ExcludeFromPrototype] entity_ref SpawnerEntityRef;
    [ExcludeFromPrototype] PlayerTeam PlayerTeam;

    [ExcludeFromPrototype] bool HasAirJump;
    [ExcludeFromPrototype] CountdownTimer JumpCoyoteTimer;
    [ExcludeFromPrototype] CountdownTimer RespawnTimer;
    [ExcludeFromPrototype] entity_ref HoldingBallEntityRef;

    asset_ref<PlayerMovementData> PlayerMovementData;
    
    [Space]
    StatusEffect StunStatusEffect;
    KnockbackStatusEffect KnockbackStatusEffect;
}
```

### PlayerSpawner Component

Manages player spawning and respawning:

```csharp
component PlayerSpawner
{
    player_ref PlayerRef;
    PlayerTeam PlayerTeam;
}
```

## Player Movement System

The MovementSystem handles player movement, rotation, and jumping mechanics:

```csharp
public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public PlayerStatus* PlayerStatus;
        public Transform3D* Transform;
        public CharacterController3D* KCC;
        public AbilityInventory* AbilityInventory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        QuantumDemoInputTopDown input = *frame.GetPlayerInput(filter.PlayerStatus->PlayerRef);

        bool wasGrounded = filter.KCC->Grounded;
        bool hasActiveAbility = filter.AbilityInventory->TryGetActiveAbility(out Ability activeAbility);

        AbilityData activeAbilityData = null;

        if (hasActiveAbility)
        {
            activeAbilityData = frame.FindAsset<AbilityData>(activeAbility.AbilityData.Id);
        }

        // Move
        PlayerMovementData movementData = frame.FindAsset<PlayerMovementData>(filter.PlayerStatus->PlayerMovementData.Id);

        if ((hasActiveAbility && !activeAbilityData.KeepVelocity) ||
            filter.PlayerStatus->IsKnockbacked)
        {
            // Apply additional velocity braking
            filter.KCC->Velocity = FPVector3.Lerp(filter.KCC->Velocity, FPVector3.Zero, movementData.NoMovementBraking * frame.DeltaTime);
        }

        FPVector3 movementDirection;
        if (hasActiveAbility || filter.PlayerStatus->IsIncapacitated)
        {
            movementDirection = FPVector3.Zero;
        }
        else
        {
            movementDirection = input.MoveDirection.XOY;
            if (movementDirection.SqrMagnitude > FP._1)
            {
                movementDirection = movementDirection.Normalized;
            }
        }

        if (!filter.PlayerStatus->IsRespawning)
        {
            filter.KCC->Move(frame, filter.EntityRef, movementDirection);
        }

        // Rotation handling
        HandleRotation(frame, ref filter, input, movementDirection, movementData, hasActiveAbility, activeAbilityData);

        // Update grounded state and jump coyote time
        UpdateGroundedState(frame, ref filter, wasGrounded, movementData, hasActiveAbility);
    }

    private void HandleRotation(Frame frame, ref Filter filter, QuantumDemoInputTopDown input, 
                                FPVector3 movementDirection, PlayerMovementData movementData, 
                                bool hasActiveAbility, AbilityData activeAbilityData)
    {
        FP rotationSpeed;
        FPQuaternion currentRotation = filter.Transform->Rotation;
        FPQuaternion targetRotation = currentRotation;

        if (filter.PlayerStatus->IsKnockbacked)
        {
            // Face opposite to knockback direction
            rotationSpeed = movementData.QuickRotationSpeed;
            targetRotation = FPQuaternion.LookRotation(-filter.PlayerStatus->KnockbackStatusEffect.KnockbackDirection);
        }
        else if (hasActiveAbility && activeAbilityData.FaceCastDirection)
        {
            // Face ability cast direction
            rotationSpeed = movementData.QuickRotationSpeed;
            targetRotation = FPQuaternion.LookRotation(filter.AbilityInventory->ActiveAbilityInfo.CastDirection);
        }
        else
        {
            rotationSpeed = movementData.DefaultRotationSpeed;

            if (movementData.FaceAimDirection && input.AimDirection != default)
            {
                // Face aim direction
                targetRotation = FPQuaternion.LookRotation(input.AimDirection.XOY);
            }
            else if (movementDirection != default)
            {
                // Face movement direction
                targetRotation = FPQuaternion.LookRotation(movementDirection);
            }
        }

        // Smooth rotation
        filter.Transform->Rotation = FPQuaternion.Slerp(currentRotation, targetRotation, rotationSpeed * frame.DeltaTime);
    }

    private void UpdateGroundedState(Frame frame, ref Filter filter, bool wasGrounded, 
                                    PlayerMovementData movementData, bool hasActiveAbility)
    {
        if (filter.KCC->Grounded)
        {
            if (!hasActiveAbility && !filter.AbilityInventory->GetAbility(AbilityType.Jump).IsOnCooldown)
            {
                // Refresh air jump when grounded
                filter.PlayerStatus->HasAirJump = true;
                
                // Start coyote time timer
                filter.PlayerStatus->JumpCoyoteTimer.Start(movementData.JumpCoyoteTime);

                if (!wasGrounded)
                {
                    frame.Events.OnPlayerLanded(filter.EntityRef);
                }
            }
        }
        else
        {
            // Tick down coyote timer when in air
            filter.PlayerStatus->JumpCoyoteTimer.Tick(frame.DeltaTime);
        }
    }
}
```

## Dynamic Character Controller Configuration

The `PlayerMovementData` asset implements a method to change the KCC configuration based on player state:

```csharp
public unsafe void UpdateKCCSettings(Frame frame, EntityRef playerEntityRef)
{
    PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
    AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(playerEntityRef);
    CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(playerEntityRef);

    CharacterController3DConfig config;

    if (playerStatus->IsKnockbacked || abilityInventory->HasActiveAbility)
    {
        // Use a special config for when player has no control
        config = frame.FindAsset<CharacterController3DConfig>(NoMovementKCCSettings.Id);
    }
    else if (playerStatus->IsHoldingBall)
    {
        // Use a slowed config when holding the ball
        config = frame.FindAsset<CharacterController3DConfig>(CarryingBallKCCSettings.Id);
    }
    else
    {
        // Use default movement config
        config = frame.FindAsset<CharacterController3DConfig>(DefaultKCCSettings.Id);
    }

    kcc->SetConfig(frame, config);
}
```

This allows for three distinct movement states:
1. **Default Movement**: Full speed and control
2. **Carrying Ball**: Reduced speed to encourage passing
3. **No Movement Control**: During abilities or knockback

## Player Spawn System

The PlayerSpawnSystem handles creating player entities and respawning after death:

```csharp
public unsafe class PlayerSpawnSystem : SystemMainThreadFilter<PlayerSpawnSystem.Filter>, 
    ISignalOnPlayerAdded, 
    ISignalOnPlayerRespawned, 
    ISignalOnPlayerRespawnTimerReset
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public PlayerSpawner* PlayerSpawner;
        public Transform3D* Transform;
    }
    
    private Dictionary<PlayerRef, EntityRef> _playerEntityRefs = new Dictionary<PlayerRef, EntityRef>();
    private Dictionary<PlayerRef, EntityRef> _spawnerEntityRefs = new Dictionary<PlayerRef, EntityRef>();

    public override void Update(Frame frame, ref Filter filter)
    {
        // Store player spawner reference
        _spawnerEntityRefs[filter.PlayerSpawner->PlayerRef] = filter.EntityRef;
    }

    public void OnPlayerAdded(Frame frame, PlayerRef playerRef)
    {
        if (!_spawnerEntityRefs.TryGetValue(playerRef, out var spawnerEntityRef))
        {
            return;
        }
        
        // Create player entity when player joins
        SpawnPlayer(frame, playerRef, spawnerEntityRef);
    }

    public void OnPlayerRespawned(Frame frame, EntityRef playerEntityRef, bool fullReset)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        
        if (playerStatus->SpawnerEntityRef == default)
        {
            return;
        }
        
        // Get spawner
        Transform3D* spawnerTransform = frame.Unsafe.GetPointer<Transform3D>(playerStatus->SpawnerEntityRef);
        Transform3D* playerTransform = frame.Unsafe.GetPointer<Transform3D>(playerEntityRef);
        
        // Teleport to spawn position
        playerTransform->Teleport(frame, spawnerTransform->Position);
        playerTransform->Rotation = spawnerTransform->Rotation;
        
        // Reset physics
        if (frame.Unsafe.TryGetPointer<CharacterController3D>(playerEntityRef, out var kcc))
        {
            kcc->Velocity = FPVector3.Zero;
        }
        
        // Drop ball if holding
        if (playerStatus->IsHoldingBall)
        {
            frame.Signals.OnBallDropped(playerStatus->HoldingBallEntityRef);
        }
        
        // Reset abilities
        frame.Signals.OnActiveAbilityStopped(playerEntityRef);
        frame.Signals.OnCooldownsReset(playerEntityRef);
        
        // Reset status effects
        frame.Signals.OnStatusEffectsReset(playerEntityRef);
        
        // Reset respawn timer
        playerStatus->RespawnTimer.Reset();
    }

    public void OnPlayerRespawnTimerReset(Frame frame, EntityRef playerEntityRef)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        playerStatus->RespawnTimer.Reset();
    }
    
    private void SpawnPlayer(Frame frame, PlayerRef playerRef, EntityRef spawnerEntityRef)
    {
        // Only spawn if not already spawned
        if (_playerEntityRefs.ContainsKey(playerRef))
        {
            return;
        }
        
        PlayerSpawner* spawner = frame.Unsafe.GetPointer<PlayerSpawner>(spawnerEntityRef);
        Transform3D* spawnerTransform = frame.Unsafe.GetPointer<Transform3D>(spawnerEntityRef);
        
        // Create player entity from prototype
        EntityPrototype playerPrototype = frame.FindAsset<EntityPrototype>("Player");
        EntityRef playerEntityRef = frame.Create(playerPrototype, spawnerTransform->Position, spawnerTransform->Rotation);
        
        // Initialize player status
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        playerStatus->PlayerRef = playerRef;
        playerStatus->SpawnerEntityRef = spawnerEntityRef;
        playerStatus->PlayerTeam = spawner->PlayerTeam;
        
        // Track player entity
        _playerEntityRefs[playerRef] = playerEntityRef;
        
        // Initialize air jump
        playerStatus->HasAirJump = true;
    }
}
```

## Status Effect Systems

The game implements two types of status effects: stun and knockback.

### Stun System

```csharp
public unsafe class StunStatusEffectSystem : SystemMainThreadFilter<StunStatusEffectSystem.Filter>, 
    ISignalOnStunApplied, 
    ISignalOnStatusEffectsReset
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public PlayerStatus* PlayerStatus;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Tick down stun timer if active
        if (filter.PlayerStatus->StunStatusEffect.DurationTimer.IsRunning)
        {
            filter.PlayerStatus->StunStatusEffect.DurationTimer.Tick(frame.DeltaTime);
            
            // If just ended, trigger end effects
            if (filter.PlayerStatus->StunStatusEffect.DurationTimer.IsDone)
            {
                filter.PlayerStatus->StunStatusEffect.DurationTimer.Reset();
            }
        }
    }

    public void OnStunApplied(Frame frame, EntityRef playerEntityRef, FP duration)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        
        // Only apply if not already stunned or with longer duration
        if (!playerStatus->StunStatusEffect.DurationTimer.IsRunning || 
            playerStatus->StunStatusEffect.DurationTimer.TimeLeft < duration)
        {
            playerStatus->StunStatusEffect.DurationTimer.Start(duration);
            
            // Drop ball if holding
            if (playerStatus->IsHoldingBall)
            {
                frame.Signals.OnBallDropped(playerStatus->HoldingBallEntityRef);
            }
            
            // Cancel any active ability
            frame.Signals.OnActiveAbilityStopped(playerEntityRef);
            
            // Trigger stun event
            frame.Events.OnPlayerStunned(playerEntityRef);
        }
    }

    public void OnStatusEffectsReset(Frame frame, EntityRef playerEntityRef)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        playerStatus->StunStatusEffect.DurationTimer.Reset();
    }
}
```

### Knockback System

```csharp
public unsafe class KnockbackStatusEffectSystem : SystemMainThreadFilter<KnockbackStatusEffectSystem.Filter>, 
    ISignalOnKnockbackApplied, 
    ISignalOnStatusEffectsReset
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public PlayerStatus* PlayerStatus;
        public Transform3D* Transform;
        public CharacterController3D* KCC;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        if (filter.PlayerStatus->KnockbackStatusEffect.DurationTimer.IsRunning)
        {
            // Get configuration
            KnockbackStatusEffectData knockbackData = frame.FindAsset<KnockbackStatusEffectData>(
                filter.PlayerStatus->KnockbackStatusEffect.StatusEffectData.Id);
            
            // Apply knockback movement
            ApplyKnockbackMovement(frame, ref filter, knockbackData);
            
            // Check for out of bounds
            if (filter.Transform->Position.Y < -10)  // Out of bounds check
            {
                frame.Events.OnPlayerEnteredVoid(filter.EntityRef);
                StartRespawnTimer(frame, filter.EntityRef);
            }
            
            // Tick timer
            filter.PlayerStatus->KnockbackStatusEffect.DurationTimer.Tick(frame.DeltaTime);
            
            // Reset when done
            if (filter.PlayerStatus->KnockbackStatusEffect.DurationTimer.IsDone)
            {
                filter.PlayerStatus->KnockbackStatusEffect.DurationTimer.Reset();
                
                // Reset KCC settings
                PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(
                    filter.PlayerStatus->PlayerMovementData.Id);
                playerMovementData.UpdateKCCSettings(frame, filter.EntityRef);
            }
        }
    }

    public void OnKnockbackApplied(Frame frame, EntityRef playerEntityRef, FP duration, FPVector3 direction)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(playerEntityRef);
        
        // Only apply if not already knockbacked or with longer duration
        if (!playerStatus->KnockbackStatusEffect.DurationTimer.IsRunning || 
            playerStatus->KnockbackStatusEffect.DurationTimer.TimeLeft < duration)
        {
            // Get knockback data
            KnockbackStatusEffectData knockbackData = frame.FindAsset<KnockbackStatusEffectData>(
                playerStatus->KnockbackStatusEffect.StatusEffectData.Id);
            
            // Set up knockback state
            playerStatus->KnockbackStatusEffect.DurationTimer.Start(duration);
            playerStatus->KnockbackStatusEffect.KnockbackDirection = direction.Normalized;
            
            // Calculate knockback velocity
            FPVector3 knockbackVelocity = direction.Normalized * knockbackData.KnockbackForce;
            
            // Add upward component
            knockbackVelocity.Y = knockbackData.KnockbackUpwardForce;
            
            // Store calculated velocity
            playerStatus->KnockbackStatusEffect.KnockbackVelocity = knockbackVelocity;
            
            // Update KCC settings
            PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(
                playerStatus->PlayerMovementData.Id);
            playerMovementData.UpdateKCCSettings(frame, playerEntityRef);
            
            // Drop ball if holding
            if (playerStatus->IsHoldingBall)
            {
                frame.Signals.OnBallDropped(playerStatus->HoldingBallEntityRef);
            }
            
            // Cancel any active ability
            frame.Signals.OnActiveAbilityStopped(playerEntityRef);
        }
    }

    public void OnStatusEffectsReset(Frame frame, EntityRef playerEntityRef)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        playerStatus->KnockbackStatusEffect.DurationTimer.Reset();
        
        // Update KCC settings
        PlayerMovementData playerMovementData = frame.FindAsset<PlayerMovementData>(
            playerStatus->PlayerMovementData.Id);
        playerMovementData.UpdateKCCSettings(frame, playerEntityRef);
    }
    
    private void ApplyKnockbackMovement(Frame frame, ref Filter filter, KnockbackStatusEffectData knockbackData)
    {
        // Calculate current knockback velocity with decay
        FP normalizedTime = filter.PlayerStatus->KnockbackStatusEffect.DurationTimer.NormalizedTime;
        FP velocityMultiplier = knockbackData.KnockbackCurve.Evaluate(normalizedTime);
        
        FPVector3 currentVelocity = filter.PlayerStatus->KnockbackStatusEffect.KnockbackVelocity * velocityMultiplier;
        
        // Apply gravity if in air
        if (!filter.KCC->Grounded)
        {
            currentVelocity.Y -= knockbackData.KnockbackGravity * frame.DeltaTime;
        }
        else
        {
            // Bounce on ground impact
            if (currentVelocity.Y < FP._0)
            {
                currentVelocity.Y = -currentVelocity.Y * knockbackData.GroundBounceMultiplier;
                
                // Apply additional lateral friction
                currentVelocity.X *= knockbackData.GroundFriction;
                currentVelocity.Z *= knockbackData.GroundFriction;
            }
        }
        
        // Store updated velocity
        filter.PlayerStatus->KnockbackStatusEffect.KnockbackVelocity = currentVelocity;
        
        // Apply movement
        FPVector3 movementDelta = currentVelocity * frame.DeltaTime;
        filter.KCC->AddDisplacement(movementDelta);
    }
    
    private void StartRespawnTimer(Frame frame, EntityRef playerEntityRef)
    {
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerEntityRef);
        GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);
        
        // Start respawn timer
        playerStatus->RespawnTimer.Start(gameSettingsData.RespawnDuration);
        
        // Reset status effects
        frame.Signals.OnStatusEffectsReset(playerEntityRef);
    }
}
```

## Player Input Extensions

The game extends the default Quantum input structure to support the ability system:

```csharp
public static class QuantumDemoInputTopDownExtensions
{
    public static bool GetAbilityInputWasPressed(this QuantumDemoInputTopDown input, AbilityType abilityType)
    {
        switch (abilityType)
        {
            case AbilityType.Jump:
                return input.Jump.WasPressed;
                
            case AbilityType.Dash:
                return input.Dash.WasPressed;
                
            case AbilityType.Attack:
                return input.Fire.WasPressed;
                
            case AbilityType.Block:
                return input.AltFire.WasPressed;
                
            case AbilityType.ThrowShort:
                return input.Fire.WasPressed;
                
            case AbilityType.ThrowLong:
                return input.AltFire.WasPressed;
                
            default:
                return false;
        }
    }
}
```

## Player Extension Methods

Extension methods provide convenient access to commonly used player state checks:

```csharp
public static class PlayerStatusExtensions
{
    public static bool IsHoldingBall(this PlayerStatus playerStatus)
    {
        return playerStatus.HoldingBallEntityRef != default;
    }
    
    public static bool IsStunned(this PlayerStatus playerStatus)
    {
        return playerStatus.StunStatusEffect.DurationTimer.IsRunning;
    }
    
    public static bool IsKnockbacked(this PlayerStatus playerStatus)
    {
        return playerStatus.KnockbackStatusEffect.DurationTimer.IsRunning;
    }
    
    public static bool IsRespawning(this PlayerStatus playerStatus)
    {
        return playerStatus.RespawnTimer.IsRunning;
    }
    
    public static bool IsIncapacitated(this PlayerStatus playerStatus)
    {
        return playerStatus.IsStunned() || playerStatus.IsRespawning();
    }
}
```

## Player View Layer

On the Unity side, the `PlayerViewController` handles the visual representation of players:

```csharp
public class PlayerViewController : QuantumEntityView
{
    [SerializeField] private Transform _ballFollowTransform;
    [SerializeField] private Animator _animator;
    
    // Animation parameters
    private static readonly int IsRunning = Animator.StringToHash("IsRunning");
    private static readonly int IsHoldingBall = Animator.StringToHash("IsHoldingBall");
    private static readonly int IsStunned = Animator.StringToHash("IsStunned");
    private static readonly int IsKnockbacked = Animator.StringToHash("IsKnockbacked");
    private static readonly int JumpTrigger = Animator.StringToHash("Jump");
    private static readonly int LandTrigger = Animator.StringToHash("Land");
    private static readonly int AttackTrigger = Animator.StringToHash("Attack");
    private static readonly int BlockTrigger = Animator.StringToHash("Block");
    private static readonly int ThrowTrigger = Animator.StringToHash("Throw");
    private static readonly int DashTrigger = Animator.StringToHash("Dash");
    private static readonly int StunTrigger = Animator.StringToHash("Stun");
    private static readonly int HitTrigger = Animator.StringToHash("Hit");
    
    public Transform BallFollowTransform => _ballFollowTransform;
    public PlayerRef PlayerRef { get; private set; }
    
    private LocalPlayerAccess _localPlayerAccess;
    
    protected override void ApplyTransform(ref UpdatePositionParameter param)
    {
        base.ApplyTransform(ref param);
        
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        if (frame.Unsafe.TryGetPointer<PlayerStatus>(EntityRef, out var playerStatus))
        {
            PlayerRef = playerStatus->PlayerRef;
            
            // Initialize local player access if this is a local player
            if (frame.IsPlayerLocal(PlayerRef) && _localPlayerAccess == null)
            {
                _localPlayerAccess = LocalPlayersManager.Instance.InitializeLocalPlayer(this);
            }
            
            // Update animator
            UpdateAnimator(frame, playerStatus);
        }
    }
    
    private void UpdateAnimator(Frame frame, PlayerStatus* playerStatus)
    {
        CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(EntityRef);
        
        // Basic state parameters
        _animator.SetBool(IsRunning, kcc->Velocity.XZ.SqrMagnitude > FP._0_10 && kcc->Grounded);
        _animator.SetBool(IsHoldingBall, playerStatus->IsHoldingBall());
        _animator.SetBool(IsStunned, playerStatus->IsStunned());
        _animator.SetBool(IsKnockbacked, playerStatus->IsKnockbacked());
    }
    
    // Event handlers for animation triggers
    public void OnPlayerJumped()
    {
        _animator.SetTrigger(JumpTrigger);
    }
    
    public void OnPlayerLanded()
    {
        _animator.SetTrigger(LandTrigger);
    }
    
    public void OnPlayerAttacked()
    {
        _animator.SetTrigger(AttackTrigger);
    }
    
    public void OnPlayerBlocked()
    {
        _animator.SetTrigger(BlockTrigger);
    }
    
    public void OnPlayerThrewBall()
    {
        _animator.SetTrigger(ThrowTrigger);
    }
    
    public void OnPlayerDashed()
    {
        _animator.SetTrigger(DashTrigger);
    }
    
    public void OnPlayerStunned()
    {
        _animator.SetTrigger(StunTrigger);
    }
    
    public void OnPlayerHit()
    {
        _animator.SetTrigger(HitTrigger);
    }
}
```

## Player Movement Data

The configuration for player movement is defined in a scriptable object:

```csharp
[CreateAssetMenu(menuName = "Quantum/Arena Brawler/Player Movement Data")]
public class PlayerMovementData : AssetObject
{
    [Header("Character Controller")]
    public AssetRef<CharacterController3DConfig> DefaultKCCSettings;
    public AssetRef<CharacterController3DConfig> CarryingBallKCCSettings;
    public AssetRef<CharacterController3DConfig> NoMovementKCCSettings;
    
    [Header("Movement")]
    public FP NoMovementBraking = 5;
    
    [Header("Rotation")]
    public bool FaceAimDirection = true;
    public FP DefaultRotationSpeed = 8;
    public FP QuickRotationSpeed = 16;
    
    [Header("Jump")]
    public FP JumpCoyoteTime = FP._0_10;
    
    // Method for updating KCC settings shown earlier
}
```

This data-driven approach allows for tweaking player movement characteristics without changing code.
