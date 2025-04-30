# Character System in Quantum Platform Shooter 2D

This document explains how the Character System is implemented in the Platform Shooter 2D sample project, covering player creation, state management, and respawning.

## Character Components

The character system is built on several key components defined in the Quantum DSL:

```qtn
// Character.qtn
component PlayerLink
{
    player_ref Player;
}

component Status
{
    asset_ref<StatusData> StatusData;
    FP CurrentHealth;
    Boolean IsDead;
    FrameTimer RespawnTimer;
    FrameTimer RegenTimer;
    FrameTimer InvincibleTimer;
    FrameTimer DisconnectedTimer;
}

component MovementData
{
    Boolean IsFacingRight;
}
```

Additionally, characters use standard Quantum components:
- `Transform2D`: Position and rotation
- `KCC2D`: Kinematic Character Controller for 2D movement
- `PhysicsCollider2D`: For collision detection

## Player System

The `PlayerSystem` handles player joining and character creation:

```csharp
namespace Quantum
{
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class PlayerSystem : SystemSignalsOnly, ISignalOnPlayerAdded
  {
    public void OnPlayerAdded(Frame frame, PlayerRef player, bool firstTime)
    {
      var data = frame.GetPlayerData(player);

      if (data.PlayerAvatar != null)
      {
        SetPlayerCharacter(frame, player, data.PlayerAvatar);
      }
      else
      {
        Log.Warn(
          "Character prototype is null on RuntimePlayer, check QuantumMenuConnectionBehaviourSDK to prevent adding player automatically!");
      }
    }

    private void SetPlayerCharacter(Frame frame, PlayerRef player, AssetRef<EntityPrototype> prototypeAsset)
    {
      // Create the entity from the prototype
      var characterEntity = frame.Create(prototypeAsset);

      // Link the entity to the player
      var playerLink = frame.Unsafe.GetPointer<PlayerLink>(characterEntity);
      playerLink->Player = player;

      // Signal that the character has respawned (initial spawn)
      frame.Signals.OnCharacterRespawn(characterEntity);

      // Trigger events for view notification
      frame.Events.OnCharacterCreated(characterEntity);
      frame.Events.OnPlayerSelectedCharacter(player);
    }
  }
}
```

Key aspects:
1. Implements `ISignalOnPlayerAdded` to receive notifications when players join
2. Creates a character entity from the prototype stored in the player data
3. Links the entity to the player through the `PlayerLink` component
4. Triggers signals and events for respawn handling and view notification

## Respawn System

The `RespawnSystem` handles character death and respawning:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;
  using Collections;

  [Preserve]
  public unsafe class RespawnSystem : SystemMainThread, ISignalOnCharacterRespawn,
    ISignalOnComponentAdded<SpawnIdentifier>
  {
    public void OnAdded(Frame frame, EntityRef entity, SpawnIdentifier* component)
    {
      // Add spawn point to the list
      var spawnPlaces = frame.Unsafe.GetPointerSingleton<SpawnPlaces>();
      if (frame.TryResolveList(spawnPlaces->Spawners, out var spawns) == false)
      {
        spawns = InitSpawns(frame);
      }
      spawns.Add(entity);
    }

    private QList<EntityRef> InitSpawns(Frame frame)
    {
      // Initialize spawn points list if needed
      var spawnPlaces = frame.Unsafe.GetPointerSingleton<SpawnPlaces>();
      frame.AllocateList(out spawnPlaces->Spawners);
      return frame.ResolveList(spawnPlaces->Spawners);
    }

    public override void Update(Frame frame)
    {
      // Check for dead characters that need respawning
      foreach (var (character, characterStatus) in frame.Unsafe.GetComponentBlockIterator<Status>())
      {
        if (characterStatus->IsDead)
        {
          if (characterStatus->RespawnTimer.IsRunning(frame) == false)
          {
            frame.Signals.OnCharacterRespawn(character);
          }
        }
      }
    }

    public void OnCharacterRespawn(Frame frame, EntityRef character)
    {
      // Choose a random spawn position
      var position = FPVector2.One;

      var spawnPlaces = frame.Unsafe.GetPointerSingleton<SpawnPlaces>();
      var spawns = frame.ResolveList(spawnPlaces->Spawners);

      if (spawns.Count != 0)
      {
        int index = frame.RNG->Next(0, spawns.Count);
        position = frame.Get<Transform2D>(spawns[index]).Position;
      }

      // Set character position and enable collisions
      var characterTransform = frame.Unsafe.GetPointer<Transform2D>(character);
      var collider = frame.Unsafe.GetPointer<PhysicsCollider2D>(character);

      characterTransform->Position = position;
      collider->IsTrigger = false;

      // Trigger view event
      frame.Events.OnCharacterRespawn(character);
    }
  }
}
```

Key aspects:
1. Tracks spawn points in the level
2. Checks for dead characters and initiates respawn when timer completes
3. Handles the respawn logic by selecting a random spawn point
4. Resets character state and position
5. Notifies the view system about the respawn

## Status System

The Status System (not shown in full) handles character health and status effects:

```csharp
// Simplified example
public unsafe class StatusSystem : SystemMainThreadFilter<StatusSystem.Filter>
{
  public struct Filter
  {
    public EntityRef Entity;
    public Status* Status;
  }

  public override void Update(Frame frame, ref Filter filter)
  {
    // Health regeneration
    if (filter->Status->RegenTimer.ExpiredOrNotRunning(frame) && 
        !filter->Status->IsDead &&
        filter->Status->CurrentHealth < filter->Status->StatusData.Asset.MaxHealth)
    {
      filter->Status->CurrentHealth += filter->Status->StatusData.Asset.HealthRegen;
      filter->Status->RegenTimer.Restart(frame, filter->Status->StatusData.Asset.RegenRate);
    }

    // ... other status checks and updates
  }

  // Handle damage application
  public void OnDamageTaken(Frame frame, EntityRef entity, FP damage, EntityRef source)
  {
    if (frame.Unsafe.TryGetPointer<Status>(entity, out var status))
    {
      if (status->IsDead || status->InvincibleTimer.IsRunning(frame))
      {
        return;
      }

      // Apply damage
      status->CurrentHealth -= damage;

      // Check for death
      if (status->CurrentHealth <= FP._0)
      {
        status->IsDead = true;
        status->CurrentHealth = FP._0;
        status->RespawnTimer.Restart(frame, status->StatusData.Asset.RespawnTime);

        // Trigger death event
        frame.Events.OnCharacterDied(entity, source);
      }
      else
      {
        // Trigger damage event
        frame.Events.OnCharacterDamaged(entity, damage);
      }
    }
  }
}
```

## Character View Integration

The view side is handled by the `CharacterView` component:

```csharp
namespace PlatformShooter2D
{
  using Quantum;
  using UnityEngine;

  public class CharacterView : QuantumEntityViewComponent<CustomViewContext>
  {
    public Transform Body;
    public Animator CharacterAnimator;
    [HideInInspector] public int LookDirection;

    private readonly Vector3 _rightRotation = Vector3.zero;
    private readonly Vector3 _leftRotation = new(0, 180, 0);
    private static readonly int IsFacingRight = Animator.StringToHash("IsFacingRight");

    public override void OnActivate(Frame frame)
    {
      // Set up local player reference if applicable
      PlayerLink playerLink = VerifiedFrame.Get<PlayerLink>(EntityRef);

      if (Game.PlayerIsLocal(playerLink.Player))
      {
        ViewContext.LocalCharacterView = this;
      }
    }

    public override void OnUpdateView()
    {
      if (CharacterAnimator.GetBool(IsFacingRight))
      {
        // Rotate to face right
        Body.localRotation = Quaternion.Euler(_rightRotation);
        LookDirection = 1;
      }
      else
      {
        // Rotate to face left
        Body.localRotation = Quaternion.Euler(_leftRotation);
        LookDirection = -1;
      }
    }
  }
}
```

Key aspects:
1. Extends `QuantumEntityViewComponent` to link with a Quantum entity
2. Identifies local player's character and stores a reference in the view context
3. Updates character's visual direction based on the simulation state

## Character Events

Events facilitate communication between simulation and view:

```qtn
event OnPlayerSelectedCharacter
{
    local player_ref PlayerRef;
}

// Other events in CharacterEvents.qtn
event OnCharacterCreated
{
    entity_ref Character;
}

event OnCharacterRespawn
{
    entity_ref Character;
}

event OnCharacterDied
{
    entity_ref Character;
    entity_ref Killer;
}

event OnCharacterDamaged
{
    entity_ref Character;
    FP Damage;
}
```

## Character Signals

Signals handle inter-system communication within the simulation:

```qtn
// CharacterSignals.qtn
signal OnCharacterRespawn(entity_ref character);
signal OnDamageTaken(entity_ref entity, FP damage, entity_ref source);
```

## Best Practices for Character Implementation

1. **Separate concerns**: Split character functionality across focused components and systems
2. **Use signals for internal communication**: Signals connect systems without creating tight coupling
3. **Use events for view communication**: Events notify the view layer about game state changes
4. **Leverage entity prototypes**: Store character configurations in entity prototypes for easy setup
5. **Handle unsafe pointers carefully**: When using unsafe pointers, always check for valid entities
6. **Use FrameTimers for time-based mechanics**: Respawn and regeneration use FrameTimers for deterministic timing
7. **Keep view logic separate**: Character view code should only observe and visualize state changes

These practices ensure deterministic behavior while keeping the code maintainable and modular.
