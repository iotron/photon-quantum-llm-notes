# Skills System in Quantum Platform Shooter 2D

This document explains the implementation of the Skills System in the Platform Shooter 2D sample project, covering skill casting, activation, and effects.

## Skill Components

The skill system is built on these components defined in the Quantum DSL:

```qtn
// Skill.qtn
component SkillFields
{
    FP TimeToActivate;
    entity_ref Source;
    asset_ref<SkillData> SkillData;
}

component SkillInventory
{
    FrameTimer CastRateTimer;
    asset_ref<SkillInventoryData> SkillInventoryData;
}

event OnSkillCasted
{
    entity_ref Skill;
}

event OnSkillActivated
{
    FPVector2 SkillPosition;
}

event OnSkillHitTarget
{
    FPVector2 SkillPosition;
    Int64 SkillDataId;
    entity_ref Target;
}
```

## Skill Inventory System

The `SkillInventorySystem` handles skill casting based on player input:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class SkillInventorySystem : SystemMainThreadFilter<SkillInventorySystem.Filter>
  {
    public struct Filter
    {
      public EntityRef Entity;
      public Transform2D* Transform;
      public PlayerLink* PlayerLink;
      public SkillInventory* SkillInventory;
      public Status* Status;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
      if (filter.Status->IsDead)
      {
        return;
      }

      QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);

      // Check if skill cooldown has expired
      if (filter.SkillInventory->CastRateTimer.IsRunning(frame) == false)
      {
        if (input.AltFire.WasPressed)
        {
          CastSkill(frame, ref filter, input.AimDirection);
        }
      }
    }

    private void CastSkill(Frame frame, ref Filter filter, FPVector2 direction)
    {
      // Get skill configuration data
      var skillInventoryData = frame.FindAsset(filter.SkillInventory->SkillInventoryData);
      var skillData = frame.FindAsset(skillInventoryData.SkillData);

      // Create skill entity from prototype
      var skillPrototype = frame.FindAsset(skillData.SkillPrototype);
      var skill = frame.Create(skillPrototype);

      // Configure skill fields
      var skillFields = frame.Unsafe.GetPointer<SkillFields>(skill);
      skillFields->SkillData = skillData;
      skillFields->Source = filter.Entity;
      skillFields->TimeToActivate = skillData.ActivationDelay;

      // Set skill position
      var skillTransform = frame.Unsafe.GetPointer<Transform2D>(skill);
      skillTransform->Position = filter.Transform->Position;
      
      // Apply physics velocity
      var skillPhysics = frame.Unsafe.GetPointer<PhysicsBody2D>(skill);
      skillPhysics->Velocity = direction * skillInventoryData.CastForce;
      
      // Start cooldown timer
      filter.SkillInventory->CastRateTimer = FrameTimer.FromSeconds(frame, skillInventoryData.CastRate);
      
      // Trigger skill cast event
      frame.Events.OnSkillCasted(skill);
    }
  }
}
```

Key aspects:
1. Filter selects entities with required components (Transform2D, PlayerLink, SkillInventory, Status)
2. Handles skill casting based on player input (AltFire button)
3. Creates a skill entity from a prototype
4. Configures the skill with source, position, and activation delay
5. Applies physics velocity based on aim direction
6. Manages cooldown timer between casts
7. Triggers events for view notification

## Skill System

The `SkillSystem` handles skill movement, activation, and effect application:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;
  
  [Preserve]
  public unsafe class SkillSystem : SystemMainThreadFilter<SkillSystem.Filter>
  {
    public struct Filter
    {
      public EntityRef Entity;
      public Transform2D* Transform;
      public SkillFields* SkillFields;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
      // Check if it's time to activate the skill
      if (filter.SkillFields->TimeToActivate <= FP._0)
      {
        DealAreaDamage(frame, ref filter);
        frame.Destroy(filter.Entity);
      }
      else
      {
        // Otherwise, count down activation timer
        filter.SkillFields->TimeToActivate -= frame.DeltaTime;
      }
    }

    private static void DealAreaDamage(Frame frame, ref Filter filter)
    {
      var skillData = frame.FindAsset(frame.Get<SkillFields>(filter.Entity).SkillData);
      
      // Trigger activation event
      frame.Events.OnSkillActivated(filter.Transform->Position);

      // Find all entities in the skill's area of effect
      Physics2D.HitCollection hits =
        frame.Physics2D.OverlapShape(*filter.Transform, skillData.ShapeConfig.CreateShape(frame));
        
      for (int i = 0; i < hits.Count; i++)
      {
        var targetEntity = hits[i].Entity;
        
        // Skip self
        if (targetEntity == filter.Entity)
        {
          continue;
        }

        var skillFields = frame.Get<SkillFields>(filter.Entity);
        
        // Don't hit the caster character
        if (targetEntity == skillFields.Source)
        {
          continue;
        }

        // Only consider character entities for damage
        if (targetEntity == EntityRef.None || frame.Has<Status>(targetEntity) == false)
        {
          continue;
        }

        // Line of sight check to prevent hitting through walls
        var characterPosition = frame.Get<Transform2D>(targetEntity).Position;
        if (LineOfSightHelper.HasLineOfSight(frame, filter.Transform->Position, characterPosition) == false)
        {
          continue;
        }

        // Apply skill effect
        frame.Signals.OnCharacterSkillHit(filter.Entity, targetEntity);
        
        // Trigger hit event for view notification
        frame.Events.OnSkillHitTarget(filter.Transform->Position, skillFields.SkillData.Id.Value, targetEntity);
      }
    }
  }
}
```

Key aspects:
1. Filter selects entities with required components (Transform2D, SkillFields)
2. Counts down the activation timer for the skill
3. When the timer expires, applies area damage
4. Uses Physics2D.OverlapShape to find entities in the skill's area of effect
5. Performs line of sight check to prevent hitting through walls
6. Signals hit targets for damage application
7. Triggers events for view notification

## Skill Data Configuration

Skills are configured through two types of assets:

### SkillInventoryData

This asset configures how a character manages skills:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine;
  
  public class SkillInventoryData : AssetObject
  {
    [Tooltip("Time delay between skill casting.")]
    public FP CastRate;
    
    [Tooltip("The physics force applied to the skill casted.")]
    public FP CastForce;
    
    [Tooltip("The asset reference to the SkillData.")]
    public AssetRef<SkillData> SkillData;
  }
}
```

### SkillData

This asset defines the skill's behavior and effects:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine;
  
  public class SkillData : AssetObject
  {
    [Tooltip("Prototype reference to spawn bullet projectiles")]
    public AssetRef<EntityPrototype> SkillPrototype;
    
    [Tooltip("Time delay until the skill activation.")]
    public FP ActivationDelay;
    
    [Tooltip("Damage applied in the target character.")]
    public FP Damage;
    
    [Tooltip("Shape to apply skill affect.")]
    public Shape2DConfig ShapeConfig;
  }
}
```

## Line of Sight Checking

The skills system uses a helper class for line of sight checking:

```csharp
// Simplified LineOfSightHelper
public static class LineOfSightHelper
{
    public static bool HasLineOfSight(Frame frame, FPVector2 from, FPVector2 to)
    {
        // Perform a raycast from source to target
        var hits = frame.Physics2D.LinecastAll(from, to, -1, QueryOptions.HitAll);
        
        for (int i = 0; i < hits.Count; i++)
        {
            var hit = hits[i];
            
            // If we hit a solid object (not a character), line of sight is blocked
            if (hit.Entity == EntityRef.None || !frame.Has<Status>(hit.Entity))
            {
                return false;
            }
        }
        
        return true;
    }
}
```

## Skill Visualization

The skill visualization is handled through event subscriptions:

```csharp
// Simplified SkillView
public class SkillView : QuantumEntityViewComponent
{
    public ParticleSystem CastEffect;
    public ParticleSystem ActivationEffect;
    
    public override void OnEnable()
    {
        QuantumEvent.Subscribe<EventOnSkillCasted>(this, OnSkillCasted);
        QuantumEvent.Subscribe<EventOnSkillActivated>(this, OnSkillActivated);
        QuantumEvent.Subscribe<EventOnSkillHitTarget>(this, OnSkillHitTarget);
    }
    
    private void OnSkillCasted(EventOnSkillCasted e)
    {
        if (e.Skill == EntityRef)
        {
            // Play cast effect
            CastEffect.Play();
            
            // Play sound effect
            SfxController.Instance.PlaySound(SoundType.SkillCast);
        }
    }
    
    private void OnSkillActivated(EventOnSkillActivated e)
    {
        if (transform.position.ToFPVector2().DistanceSquared(e.SkillPosition) < FP._0_50)
        {
            // Play activation effect
            ActivationEffect.Play();
            
            // Play sound effect
            SfxController.Instance.PlaySound(SoundType.SkillActivate);
        }
    }
    
    private void OnSkillHitTarget(EventOnSkillHitTarget e)
    {
        // Handle hit effects
        if (e.Target.IsValid)
        {
            // Create hit effect at target position
            // ...
        }
    }
}
```

## Character Skill Hit Signal

The damage from skills is applied through a signal:

```csharp
// In a signal implementation class (like StatusSystem)
public void OnCharacterSkillHit(Frame frame, EntityRef skill, EntityRef character)
{
    var skillFields = frame.Get<SkillFields>(skill);
    var skillData = frame.FindAsset(skillFields.SkillData);
    
    // Apply damage signal to the character
    frame.Signals.OnDamageTaken(character, skillData.Damage, skillFields.Source);
}
```

## Best Practices for Skills Implementation

1. **Separate casting from activation**: The skill system separates the creation of the skill entity from its activation
2. **Use configurable areas of effect**: Skills use shape configurations to define their area of effect
3. **Perform line of sight checks**: Skills use raycasts to ensure they can't hit through walls
4. **Use cooldown timers**: FrameTimers manage skill cooldowns deterministically
5. **Use asset references for configuration**: Skill properties are defined in assets for easy tuning
6. **Leverage entity prototypes**: Skills are spawned from entity prototypes to ensure consistency
7. **Use events for significant actions**: Events like OnSkillCasted and OnSkillActivated communicate to the view layer
8. **Use signals for internal communication**: Signals like OnCharacterSkillHit connect systems without tight coupling

These practices ensure deterministic skill behavior across all clients while providing visual feedback appropriate to each player's view.
