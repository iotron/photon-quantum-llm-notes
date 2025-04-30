# Ability System

This document details the Arena Brawler's data-driven ability system, focusing on how abilities are defined, activated, and managed.

## Ability System Overview

The ability system in Quantum Arena Brawler is built with several key features:

1. **Data-Driven Design**: All abilities are configured through asset files
2. **Input Buffering**: Smoother gameplay through queued ability activations
3. **Activation Delay**: Helps prevent mispredictions in the network simulation
4. **Contextual Abilities**: Different abilities available when holding/not holding the ball
5. **Priority System**: Clear activation order when multiple abilities are triggered

## Core Components

### AbilityInventory Component

Each player has an `AbilityInventory` component that stores all ability data:

```csharp
component AbilityInventory
{
    [ExcludeFromPrototype] ActiveAbilityInfo ActiveAbilityInfo;
        
    // Same order as AbilityType enum also used for activation priority
    [Header("Ability Order: Block, Dash, Attack, ThrowShort, ThrowLong, Jump")]
    array<Ability>[6] Abilities;
}
```

### Ability Struct

Each ability is represented by a struct containing all necessary state:

```csharp
struct Ability
{
    [ExcludeFromPrototype] AbilityType AbilityType;

    [ExcludeFromPrototype] CountdownTimer InputBufferTimer;
    [ExcludeFromPrototype] CountdownTimer DelayTimer;
    [ExcludeFromPrototype] CountdownTimer DurationTimer;
    [ExcludeFromPrototype] CountdownTimer CooldownTimer;

    asset_ref<AbilityData> AbilityData;
}
```

### ActiveAbilityInfo Struct

When an ability is active, its properties are stored in an `ActiveAbilityInfo` struct:

```csharp
struct ActiveAbilityInfo
{
    [ExcludeFromPrototype] int ActiveAbilityIndex;

    [ExcludeFromPrototype] FPVector3 CastDirection;
    [ExcludeFromPrototype] FPQuaternion CastRotation;
    [ExcludeFromPrototype] FPVector3 CastVelocity;
}
```

## Ability System Implementation

The `AbilitySystem` class is responsible for updating all player abilities:

```csharp
public unsafe class AbilitySystem : SystemMainThreadFilter<AbilitySystem.Filter>, 
    ISignalOnActiveAbilityStopped, 
    ISignalOnCooldownsReset, 
    ISignalOnComponentAdded<AbilityInventory>
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public PlayerStatus* PlayerStatus;
        public AbilityInventory* AbilityInventory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        QuantumDemoInputTopDown input = *frame.GetPlayerInput(filter.PlayerStatus->PlayerRef);
            
        for (int i = 0; i < filter.AbilityInventory->Abilities.Length; i++)
        {
            AbilityType abilityType = (AbilityType)i;
            ref Ability ability = ref filter.AbilityInventory->Abilities[i];
            AbilityData abilityData = frame.FindAsset<AbilityData>(ability.AbilityData.Id);

            abilityData.UpdateAbility(frame, filter.EntityRef, ref ability);
            abilityData.UpdateInput(frame, ref ability, input.GetAbilityInputWasPressed(abilityType));
            abilityData.TryActivateAbility(frame, filter.EntityRef, filter.PlayerStatus, ref ability);
        }
    }
    
    // Signal handlers for stopping abilities and resetting cooldowns
    public void OnActiveAbilityStopped(Frame frame, EntityRef playerEntityRef)
    {
        AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(playerEntityRef);

        if (!abilityInventory->HasActiveAbility)
        {
            return;
        }

        for (int i = 0; i < abilityInventory->Abilities.Length; i++)
        {
            Ability ability = abilityInventory->Abilities[i];

            if (ability.IsDelayedOrActive)
            {
                ability.StopAbility(frame, playerEntityRef);
                break;
            }
        }
    }

    public void OnCooldownsReset(Frame frame, EntityRef playerEntityRef)
    {
        AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(playerEntityRef);

        for (int i = 0; i < abilityInventory->Abilities.Length; i++)
        {
            Ability ability = abilityInventory->Abilities[i];
            ability.ResetCooldown();
        }
    }
}
```

## Ability Data Base Class

The `AbilityData` class is the base class for all abilities:

```csharp
public unsafe partial class AbilityData : AssetObject
{
    public FP InputBuffer = FP._0_10 + FP._0_05;
    public FP Delay = FP._0_10 + FP._0_05;
    public FP Duration = FP._0_25;
    public FP Cooldown = 5;

    public AbilityAvailabilityType AvailabilityType;
    public AbilityCastDirectionType CastDirectionType = AbilityCastDirectionType.Aim;
    public bool FaceCastDirection = true;
    public bool KeepVelocity = false;
    public bool StartCooldownAfterDelay = false;
    
    [Header("Unity")] [SerializeField] private GameObject _uiAbilityPrefab;

    public virtual Ability.AbilityState UpdateAbility(Frame frame, EntityRef entityRef, ref Ability ability)
    {
        return ability.Update(frame, entityRef);
    }

    public virtual void UpdateInput(Frame frame, ref Ability ability, bool inputWasPressed)
    {
        if (inputWasPressed)
        {
            ability.BufferInput(frame);
        }
    }

    public virtual bool TryActivateAbility(Frame frame, EntityRef entityRef, PlayerStatus* playerStatus, ref Ability ability)
    {
        if ((AvailabilityType == AbilityAvailabilityType.WithBall && !playerStatus->IsHoldingBall) ||
            (AvailabilityType == AbilityAvailabilityType.WithoutBall && playerStatus->IsHoldingBall))
        {
            return false;
        }

        if (ability.HasBufferedInput)
        {
            if (ability.TryActivateAbility(frame, entityRef, playerStatus->PlayerRef))
            {
                return true;
            }
        }

        return false;
    }
}
```

## Ability Lifecycle

Each ability goes through a specific lifecycle:

1. **Input Detection**: Player presses input associated with ability
2. **Input Buffering**: Start a timer to remember input for a short period
3. **Activation Check**: Verify ability can be activated (not on cooldown, player state allows it)
4. **Activation Delay**: Short delay to synchronize with network
5. **Active Duration**: Ability effects active for the configured duration
6. **Cooldown**: Ability cannot be used again until cooldown expires

## Ability Extensions

These extension methods simplify working with abilities:

```csharp
public static class AbilityExtensions
{
    // Get an ability's state based on its timers
    public static Ability.AbilityState GetState(this Ability ability)
    {
        if (ability.DelayTimer.IsRunning)
        {
            return Ability.AbilityState.Delayed;
        }
        
        if (ability.DurationTimer.IsRunning)
        {
            return Ability.AbilityState.Active;
        }
        
        if (ability.CooldownTimer.IsRunning)
        {
            return Ability.AbilityState.Cooldown;
        }

        return Ability.AbilityState.Ready;
    }
    
    // Input buffering logic
    public static void BufferInput(this ref Ability ability, Frame frame)
    {
        AbilityData abilityData = frame.FindAsset<AbilityData>(ability.AbilityData.Id);
        ability.InputBufferTimer.Start(abilityData.InputBuffer);
    }
    
    // Ability activation logic
    public static bool TryActivateAbility(this ref Ability ability, Frame frame, EntityRef entityRef, PlayerRef playerRef)
    {
        AbilityData abilityData = frame.FindAsset<AbilityData>(ability.AbilityData.Id);
        AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(entityRef);
        
        if (ability.IsDelayedOrActive || ability.IsOnCooldown)
        {
            return false;
        }

        // Check for other active abilities
        for (int i = 0; i < abilityInventory->Abilities.Length; i++)
        {
            Ability otherAbility = abilityInventory->Abilities[i];
            if (otherAbility.IsDelayedOrActive)
            {
                return false;
            }
        }

        // Start timers
        ability.InputBufferTimer.Reset();
        ability.DelayTimer.Start(abilityData.Delay);
        ability.DurationTimer.Start(abilityData.Duration);
        
        if (!abilityData.StartCooldownAfterDelay)
        {
            ability.CooldownTimer.Start(abilityData.Cooldown);
        }

        // Store casting info
        SetAbilityCastingInfo(frame, abilityInventory, entityRef, playerRef, ref ability);
        
        return true;
    }
    
    // Helper to set casting info
    private static void SetAbilityCastingInfo(Frame frame, AbilityInventory* abilityInventory, EntityRef entityRef, 
                                              PlayerRef playerRef, ref Ability ability)
    {
        AbilityData abilityData = frame.FindAsset<AbilityData>(ability.AbilityData.Id);
        
        // Store active ability index
        abilityInventory->ActiveAbilityInfo.ActiveAbilityIndex = (int)ability.AbilityType;
        
        // Determine cast direction based on configuration
        abilityInventory->ActiveAbilityInfo.CastDirection = abilityData.GetCastDirection(frame, entityRef, playerRef);
        
        // Store rotation based on direction
        abilityInventory->ActiveAbilityInfo.CastRotation = FPQuaternion.LookRotation(
            abilityInventory->ActiveAbilityInfo.CastDirection);
            
        // Store current velocity if needed
        if (frame.Unsafe.TryGetPointer<CharacterController3D>(entityRef, out var kcc))
        {
            abilityInventory->ActiveAbilityInfo.CastVelocity = kcc->Velocity;
        }
    }
}
```

## Specific Ability Implementations

The game includes several ability types that inherit from the base `AbilityData` class:

### Attack Ability

```csharp
public unsafe class AttackAbilityData : AbilityData
{
    [Header("Attack")]
    public FP PunchRadius = 1;
    public FP PunchDistance = 2;
    public int PunchSegments = 3;
    public FP PunchDamage = 1;
    public FP StunDuration = 1;
    
    public override bool TryActivateAbility(Frame frame, EntityRef entityRef, PlayerStatus* playerStatus, ref Ability ability)
    {
        if (base.TryActivateAbility(frame, entityRef, playerStatus, ref ability))
        {
            frame.Events.OnPlayerAttacked(entityRef);
            
            // Perform punch hit detection using a compound shape of growing spheres
            AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(entityRef);
            Transform3D* transform = frame.Unsafe.GetPointer<Transform3D>(entityRef);
            
            for (int i = 0; i < PunchSegments; i++)
            {
                FP segmentDistance = PunchDistance * ((i + 1) / (FP)PunchSegments);
                FP segmentRadius = PunchRadius * (1 + i * FP._0_25);
                
                FPVector3 segmentCenter = transform->Position + 
                    abilityInventory->ActiveAbilityInfo.CastDirection * segmentDistance;
                
                PerformHitDetection(frame, entityRef, segmentCenter, segmentRadius);
            }
            
            return true;
        }
        
        return false;
    }
    
    private void PerformHitDetection(Frame frame, EntityRef attackerEntityRef, FPVector3 center, FP radius)
    {
        // Create sphere for hit detection
        Shape3D sphereShape = Shape3D.CreateSphere(radius);
        
        // Check for hits against players
        GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);
        HitCollection3D hitCollection = frame.Physics3D.OverlapShape(center, FPQuaternion.Identity, 
                                                                   sphereShape, gameSettingsData.PlayerLayerMask);
        
        for (int i = 0; i < hitCollection.Count; i++)
        {
            EntityRef hitEntityRef = hitCollection[i].Entity;
            
            // Skip self-hits
            if (hitEntityRef == attackerEntityRef)
            {
                continue;
            }
            
            if (frame.Unsafe.TryGetPointer<PlayerStatus>(hitEntityRef, out var hitPlayerStatus))
            {
                Transform3D* attackerTransform = frame.Unsafe.GetPointer<Transform3D>(attackerEntityRef);
                Transform3D* hitTransform = frame.Unsafe.GetPointer<Transform3D>(hitEntityRef);
                
                FPVector3 hitDirection = (hitTransform->Position - attackerTransform->Position).Normalized;
                
                // Apply knockback in hit direction
                frame.Signals.OnKnockbackApplied(hitEntityRef, StunDuration, hitDirection);
                
                // Apply stun
                frame.Signals.OnStunApplied(hitEntityRef, StunDuration);
                
                // Trigger hit event
                frame.Events.OnPlayerHit(hitEntityRef);
            }
        }
    }
}
```

### Block Ability

```csharp
public unsafe class BlockAbilityData : AbilityData
{
    // Simple block ability provides immunity to attacks while active
    public override bool TryActivateAbility(Frame frame, EntityRef entityRef, PlayerStatus* playerStatus, ref Ability ability)
    {
        if (base.TryActivateAbility(frame, entityRef, playerStatus, ref ability))
        {
            frame.Events.OnPlayerBlocked(entityRef);
            return true;
        }
        
        return false;
    }
}
```

### Dash Ability

```csharp
public unsafe class DashAbilityData : AbilityData
{
    [Header("Dash")]
    public FP DashDistance = 5;
    public FPAnimationCurve DashMovementCurve;
    
    private FP _lastNormalizedTime;
    
    public override Ability.AbilityState UpdateAbility(Frame frame, EntityRef entityRef, ref Ability ability)
    {
        Ability.AbilityState abilityState = base.UpdateAbility(frame, entityRef, ref ability);
        
        if (abilityState.IsActive)
        {
            AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(entityRef);
            Transform3D* transform = frame.Unsafe.GetPointer<Transform3D>(entityRef);
            CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(entityRef);

            FP lastNormalizedPosition = DashMovementCurve.Evaluate(_lastNormalizedTime);
            FPVector3 lastRelativePosition = abilityInventory->ActiveAbilityInfo.CastDirection * 
                                           DashDistance * lastNormalizedPosition;

            FP newNormalizedTime = ability.DurationTimer.NormalizedTime;
            FP newNormalizedPosition = DashMovementCurve.Evaluate(newNormalizedTime);
            FPVector3 newRelativePosition = abilityInventory->ActiveAbilityInfo.CastDirection * 
                                          DashDistance * newNormalizedPosition;

            // Move by the delta between new and last position to avoid issues with KCC penetration correction
            transform->Position += newRelativePosition - lastRelativePosition;
            
            _lastNormalizedTime = newNormalizedTime;
        }
        else if (abilityState.IsDelayed && ability.DelayTimer.WasJustStarted)
        {
            // Reset last normalized time when ability activates
            _lastNormalizedTime = FP._0;
            
            frame.Events.OnPlayerDashed(entityRef);
        }
        
        return abilityState;
    }
}
```

### Jump Ability

```csharp
public unsafe class JumpAbilityData : AbilityData
{
    [Header("Jump")]
    public FP JumpVelocity = 10;
    public FP AirJumpVelocityMultiplier = FP._0_75;
    
    public override bool TryActivateAbility(Frame frame, EntityRef entityRef, PlayerStatus* playerStatus, ref Ability ability)
    {
        // Can only jump if grounded or has air jump
        CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(entityRef);
        
        if (!kcc->Grounded && !playerStatus->JumpCoyoteTimer.IsRunning && !playerStatus->HasAirJump)
        {
            return false;
        }
        
        if (base.TryActivateAbility(frame, entityRef, playerStatus, ref ability))
        {
            bool isAirJump = !kcc->Grounded && !playerStatus->JumpCoyoteTimer.IsRunning;
            
            // Apply jump velocity
            FP jumpVelocity = JumpVelocity;
            if (isAirJump)
            {
                jumpVelocity *= AirJumpVelocityMultiplier;
                playerStatus->HasAirJump = false;
                
                frame.Events.OnPlayerAirJumped(entityRef);
            }
            else
            {
                playerStatus->JumpCoyoteTimer.Reset();
                
                frame.Events.OnPlayerJumped(entityRef);
            }
            
            // Apply velocity
            kcc->Velocity.Y = jumpVelocity;
            
            return true;
        }
        
        return false;
    }
}
```

### Throw Ball Ability

```csharp
public unsafe class ThrowBallAbilityData : AbilityData
{
    [Header("Throw")]
    public FP ThrowForce = 20;
    public FP ThrowUpwardAngle = 15;
    public FP GravityChangeTime = 1;
    public bool IsLongThrow = false;
    
    public override bool TryActivateAbility(Frame frame, EntityRef entityRef, PlayerStatus* playerStatus, ref Ability ability)
    {
        // Can only throw if holding the ball
        if (!playerStatus->IsHoldingBall)
        {
            return false;
        }
        
        if (base.TryActivateAbility(frame, entityRef, playerStatus, ref ability))
        {
            // Get the ball
            EntityRef ballEntityRef = playerStatus->HoldingBallEntityRef;
            BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
            PhysicsBody3D* ballPhysicsBody = frame.Unsafe.GetPointer<PhysicsBody3D>(ballEntityRef);
            
            // Release the ball
            frame.Signals.OnBallReleased(ballEntityRef);
            
            // Get throw direction
            AbilityInventory* abilityInventory = frame.Unsafe.GetPointer<AbilityInventory>(entityRef);
            FPVector3 throwDirection = abilityInventory->ActiveAbilityInfo.CastDirection;
            
            // Adjust direction for upward angle
            FPQuaternion upwardRotation = FPQuaternion.AngleAxis(ThrowUpwardAngle, FPVector3.Cross(throwDirection, FPVector3.Up).Normalized);
            throwDirection = upwardRotation * throwDirection;
            
            // Apply impulse to the ball
            ballPhysicsBody->AddLinearImpulse(throwDirection * ThrowForce);
            
            // Start with zero gravity, gradually increase
            ballPhysicsBody->GravityScale = FP._0;
            ballStatus->GravityChangeTimer.Start(GravityChangeTime);
            
            // Trigger event
            frame.Events.OnPlayerThrewBall(entityRef, IsLongThrow);
            
            return true;
        }
        
        return false;
    }
}
```

## Input Buffering

A key feature of the ability system is input buffering, which allows ability inputs to be stored for a short time:

1. When a player presses an ability button, even if the ability can't be activated immediately, the input is remembered 
2. As soon as conditions allow (e.g., after current ability ends), the buffered ability activates
3. This creates a more responsive feel and is especially important for chaining abilities

Input buffering makes the game more responsive in multiplayer situations by compensating for network latency.

## Ability Availability

The game changes available abilities based on the player's state:

- **Without ball**: Block, Dash, Attack, Jump
- **With ball**: Block, Dash, ThrowShort, ThrowLong, Jump

This context-sensitive ability system creates more strategic gameplay as player abilities change with ball possession.
