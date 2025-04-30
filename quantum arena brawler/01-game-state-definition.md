# Game State Definition

This document details the core data structures defined in the Quantum Arena Brawler's QTN files, which form the foundation of the game's deterministic simulation.

## Core Game State

The overall game state is managed through global variables that track the current game phase, timers, and score:

```csharp
// From Game.qtn
enum GameState
{
    None, Initializing, Starting, Running, GoalScored, GameOver
}

global
{
    GameState GameState;
    CountdownTimer GameStateTimer;
    CountdownTimer MainGameTimer;
    array<int>[2] TeamScore;
}

struct CountdownTimer
{
    FP TimeLeft;
    FP StartTime;
}
```

The game uses several signals and events to notify changes in game state:

```csharp
signal OnGoalScored(entity_ref playerEntityRef, PlayerTeam playerTeam);

synced event OnGameInitializing { }
synced event OnGameStarting { bool IsFirst; }
synced event OnGameRunning { }
synced event OnGoalScored { entity_ref PlayerEntityRef; PlayerTeam PlayerTeam; }
synced event OnGameOver { }
synced event OnGameRestarted { }
```

## Player Components and State

Players are represented with several components that track their status, abilities, and team association:

```csharp
// From Player.qtn
enum PlayerTeam
{
    Blue, Red
}

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

component PlayerSpawner
{
    player_ref PlayerRef;
    PlayerTeam PlayerTeam;
}
```

## Ability System Components

The ability system is defined through a set of components and structures that enable a data-driven approach:

```csharp
// From Ability.qtn
enum AbilityType
{
    Block, Dash, Attack, ThrowShort, ThrowLong, Jump
}

enum AbilityAvailabilityType
{
    Always, WithBall, WithoutBall
}

component AbilityInventory
{
    [ExcludeFromPrototype] ActiveAbilityInfo ActiveAbilityInfo;
    
    // Same order as AbilityType enum
    [Header("Ability Order: Block, Dash, Attack, ThrowShort, ThrowLong, Jump")]
    array<Ability>[6] Abilities;
}

struct ActiveAbilityInfo
{
    [ExcludeFromPrototype] int ActiveAbilityIndex;
    [ExcludeFromPrototype] FPVector3 CastDirection;
    [ExcludeFromPrototype] FPQuaternion CastRotation;
    [ExcludeFromPrototype] FPVector3 CastVelocity;
}

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

## Ball Components

The ball has its own dedicated component to track its state:

```csharp
// From Ball.qtn
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

component BallSpawner
{
}
```

## Status Effects System

The game implements a status effects system for stuns and knockbacks:

```csharp
// From StatusEffect.qtn
enum StatusEffectType
{
    Stun, Knockback
}

struct StatusEffect
{
    [ExcludeFromPrototype] CountdownTimer DurationTimer;
}

struct KnockbackStatusEffect : StatusEffect
{
    [ExcludeFromPrototype] FPVector3 KnockbackDirection;
    [ExcludeFromPrototype] FPVector3 KnockbackVelocity;
    asset_ref<KnockbackStatusEffectData> StatusEffectData;
}

[Serializable]
struct StatusEffectConfig
{
    StatusEffectType Type;
    FP Duration;
}
```

## Static Collider Linking

The game uses tagged static colliders to manage the arena environment:

```csharp
component StaticColliderLink
{
    Int32 StaticColliderIndex;
}

component TeamBaseWallStaticColliderTag { }
```

## Key Design Patterns

Several important design patterns are used in the game state definition:

1. **ExcludeFromPrototype Attributes**: Runtime values not serialized in entity prototypes
2. **Asset References**: Components reference external asset configurations for data-driven design
3. **Signals and Events**: Clear distinction between immediate causal triggers (signals) and notifications (events)
4. **Countdown Timers**: Consistent use of a CountdownTimer struct for time-based mechanics
5. **Component Composition**: Entities built from composable components rather than inheritance

## Extension Methods

The project uses extension methods for common operations, such as checking ability state:

```csharp
// Extension methods for the Ability struct
public static bool IsOnCooldown(this Ability ability)
{
    return ability.CooldownTimer.IsRunning;
}

public static bool IsDelayedOrActive(this Ability ability)
{
    return ability.DelayTimer.IsRunning || ability.DurationTimer.IsRunning;
}

public static bool HasBufferedInput(this Ability ability)
{
    return ability.InputBufferTimer.IsRunning;
}
```

## Input Structure

The game uses the `QuantumDemoInputTopDown` input structure:

```csharp
[ExcludeFromPrototype]
struct QuantumDemoInputTopDown {
    FPVector2 MoveDirection;
    FPVector2 AimDirection;
    button Left;
    button Right;
    button Up;
    button Down;
    button Jump;
    button Dash;
    button Fire;
    button AltFire;
    button Use;
}
```

This input structure is extended to support the specific ability inputs required by the game.
