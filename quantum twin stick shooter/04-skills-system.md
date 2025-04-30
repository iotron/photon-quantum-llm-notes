# Skills and Combat System

This document explains the skills and combat implementation in the Quantum Twin Stick Shooter, focusing on how character abilities, attacks, and damage are handled.

## Overview

The skills and combat system in Twin Stick Shooter features:

1. **Data-Driven Skills**: Configurable skill behaviors and effects
2. **Basic and Special Abilities**: Each character has two unique skills
3. **Attack Implementation**: Skills spawn attack entities for damage
4. **Polymorphic Behavior**: Skills can be extended with custom behavior
5. **Resource Management**: Skills cost resources to use (mana, energy, etc.)
6. **Cooldown Management**: Skills have usage restrictions
7. **Visual Effects Integration**: Synchronized effects between simulation and view

## Core Components

### Character Attacks

```csharp
// From Character.qtn
component CharacterAttacks 
{
    asset_ref<SkillData> BasicSkillData;
    asset_ref<SkillData> SpecialSkillData;
}
```

### Skill Component

```csharp
// Generated from Skill.qtn
component Skill
{
    asset_ref<SkillData> SkillData;
    EntityRef Source;
    FP TTL;
    FP ActionTimer;
    FPVector2 ActionVector;
}
```

### Attack Component

```csharp
// From Attack.qtn
component Attack
{
    asset_ref<AttackData> AttackData;
    EntityRef Source;
    FP TTL;
}
```

## SkillData Asset

The `SkillData` class defines the behavior of skills:

```csharp
public abstract unsafe partial class SkillData : AssetObject
{
    // Configuration properties
    public AssetRef<EntityPrototype> SkillPrototype;
    public AssetRef<EntityPrototype> AttackPrototype;
    public bool HasTTL;
    public FP ActionInterval;
    public int ActionAmount;
    public FP RotationLockDuration;
    public FP MovementLockDuration;
    public bool AutoAimCheckSight = true;
    public FP Cost = 1;
    public EAttributeType CostType;
    public FP AutoAimRadius = 10;

    // Called when the skill is initially created
    public virtual EntityRef OnCreate(Frame frame, EntityRef source, SkillData data,
        FPVector2 characterPos, FPVector2 actionVector)
    {
        // Create the skill entity
        EntityRef skillEntity = frame.Create(SkillPrototype);
        Skill* skill = frame.Unsafe.GetPointer<Skill>(skillEntity);
        skill->SkillData = data;
        skill->Source = source;
        skill->ActionTimer = ActionInterval;
        skill->ActionVector = actionVector;

        // Set position
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(skillEntity);
        transform->Position = characterPos;

        // Apply skill cost
        if (Cost != 0)
        {
            AttributesHelper.ChangeAttribute(frame, source, CostType, 
                EModifierAppliance.OneTime, EModifierOperation.Subtract, Cost, 0);
        }
        
        // Apply movement/rotation locks
        if (MovementLockDuration > 0)
        {
            MovementData* movementData = frame.Unsafe.GetPointer<MovementData>(source);
            movementData->IsOnAttackMovementLock = true;
            
            frame.Timer.Set(source, "MovementLock", MovementLockDuration, 
                () => { 
                    if (frame.Exists(source)) {
                        movementData->IsOnAttackMovementLock = false; 
                    }
                });
        }
        
        return skillEntity;
    }

    // Called each frame to update the skill
    public virtual void OnUpdate(Frame frame, EntityRef source, EntityRef skillEntity, Skill* skill)
    {
        if (skill->ActionTimer >= ActionInterval)
        {
            skill->ActionTimer = 0;
            OnAction(frame, source, skillEntity, skill);
        }
        skill->TTL += frame.DeltaTime;
        skill->ActionTimer += frame.DeltaTime;
    }

    // Called when the skill performs its action (e.g., creates an attack)
    public virtual EntityRef OnAction(Frame frame, EntityRef source, EntityRef skillEntity, Skill* skill)
    {
        // Create attack entity
        EntityRef attackEntity = frame.Create(AttackPrototype);
        Transform2D* attackTransform = frame.Unsafe.GetPointer<Transform2D>(attackEntity);

        // Position the attack based on source
        if (source != default)
        {
            Transform2D sourceTransform = frame.Get<Transform2D>(source);
            attackTransform->Position = sourceTransform.Position;
            attackTransform->Rotation = sourceTransform.Rotation;
        }
        else
        {
            Transform2D skillTransform = frame.Get<Transform2D>(skillEntity);
            attackTransform->Position = skillTransform.Position;
            attackTransform->Rotation = skillTransform.Rotation;
        }

        // Setup attack properties
        Attack* attack = frame.Unsafe.GetPointer<Attack>(attackEntity);
        attack->Source = source;
        AttackData data = frame.FindAsset<AttackData>(attack->AttackData.Id);

        // Initialize attack
        data.OnCreate(frame, attackEntity, source, attack);
        
        // Send event for view synchronization
        frame.Events.SkillAction(skill->SkillData.Id);

        return attackEntity;
    }

    // Called when the skill is deactivated
    public virtual void OnDeactivate(Frame frame, EntityRef skillEntity, Skill* skill)
    {
        var skillData = frame.FindAsset<SkillData>(skill->SkillData.Id);
        frame.Signals.OnDisableSkill(skill->Source, skillData);

        frame.Destroy(skillEntity);
    }
}
```

## AttackData Asset

The `AttackData` class defines the behavior of attacks:

```csharp
public abstract unsafe partial class AttackData : AssetObject
{
    public FP Damage;
    public FP TTL;
    public AssetRef<Shape2D> CollisionShape;
    public Boolean IsContinuousDamage;
    public FP DamageInterval;

    // Called when the attack is created
    public virtual void OnCreate(Frame frame, EntityRef attackEntity, 
        EntityRef source, Attack* attack)
    {
        attack->TTL = 0;
        
        // Add physics trigger for damage detection
        if (CollisionShape.Id.IsValid)
        {
            PhysicsCollider2D* collider = frame.Unsafe.AddOrGetPointer<PhysicsCollider2D>(attackEntity);
            collider->Shape = CollisionShape;
            collider->IsTrigger = true;
        }
    }

    // Called each frame to update the attack
    public virtual void OnUpdate(Frame frame, EntityRef attackEntity, Attack* attack)
    {
        // Apply continuous damage if needed
        if (IsContinuousDamage && attack->TTL >= DamageInterval)
        {
            attack->TTL = 0;
            ApplyDamageToOverlappingEntities(frame, attackEntity, attack);
        }
        
        attack->TTL += frame.DeltaTime;
        
        // Destroy attack when TTL expires
        if (TTL > 0 && attack->TTL >= TTL)
        {
            frame.Destroy(attackEntity);
        }
    }
    
    // Apply damage to entities overlapping with the attack
    protected void ApplyDamageToOverlappingEntities(Frame frame, EntityRef attackEntity, Attack* attack)
    {
        // Get all entities overlapping with attack collider
        PhysicsCollider2D collider = frame.Get<PhysicsCollider2D>(attackEntity);
        Transform2D transform = frame.Get<Transform2D>(attackEntity);
        
        // Get team info for friendly fire check
        TeamInfo sourceTeam = default;
        if (frame.Exists(attack->Source))
        {
            sourceTeam = frame.Get<TeamInfo>(attack->Source);
        }
        
        // Check overlapping entities
        foreach (var hit in Physics2D.OverlapShape(frame, collider.Shape, transform))
        {
            // Skip if not a character or same team
            if (!frame.Has<Character>(hit) || !frame.Has<Health>(hit))
                continue;
                
            if (frame.Has<TeamInfo>(hit))
            {
                TeamInfo hitTeam = frame.Get<TeamInfo>(hit);
                if (sourceTeam.Index == hitTeam.Index)
                    continue; // Skip same team
            }
            
            // Apply damage
            Health* health = frame.Unsafe.GetPointer<Health>(hit);
            if (health->IsDead == false)
            {
                HealthSystem.ApplyDamage(frame, hit, attack->Source, Damage);
            }
        }
    }
}
```

## SkillSystem Implementation

The `SkillSystem` handles the creation, update, and deactivation of skills:

```csharp
[Preserve]
public unsafe class SkillSystem : SystemMainThreadFilter<SkillSystem.Filter>, ISignalOnCreateSkill
{
    public struct Filter
    {
        public EntityRef Entity;
        public Skill* Skill;
    }

    // Handle skill creation
    public void OnCreateSkill(Frame frame, EntityRef character, FPVector2 characterPos, 
        SkillData data, FPVector2 actionVector)
    {
        // Call polymorphic OnCreate
        data.OnCreate(frame, character, data, characterPos, actionVector);

        // Trigger view event for animation
        frame.Events.CharacterSkill(character);
    }

    // Update active skills
    public override void Update(Frame frame, ref Filter filter)
    {
        SkillData data = frame.FindAsset<SkillData>(filter.Skill->SkillData.Id);
        
        // Call polymorphic OnUpdate
        data.OnUpdate(frame, filter.Skill->Source, filter.Entity, filter.Skill);
        
        // Check if skill TTL is over
        if (data.HasTTL == true && filter.Skill->TTL >= (data.ActionAmount * data.ActionInterval))
        {
            data.OnDeactivate(frame, filter.Entity, filter.Skill);
        }
    }
}
```

## Attack System Implementation

The `AttackSystem` handles updating active attacks:

```csharp
[Preserve]
public unsafe class AttackSystem : SystemMainThreadFilter<AttackSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Attack* Attack;
    }

    // Update active attacks
    public override void Update(Frame frame, ref Filter filter)
    {
        AttackData data = frame.FindAsset<AttackData>(filter.Attack->AttackData.Id);
        
        // Call polymorphic OnUpdate
        data.OnUpdate(frame, filter.Entity, filter.Attack);
    }
}
```

## Skills Creation System

The `CharacterSkillCreationSystem` handles creating skills when players use abilities:

```csharp
[Preserve]
public unsafe class CharacterSkillCreationSystem : 
    SystemMainThreadFilter<CharacterSkillCreationSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Character* Character;
        public CharacterAttacks* CharacterAttacks;
        public InputContainer* InputContainer;
        public Transform2D* Transform;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Skip if character is dead or inputs disabled
        if (frame.Global->ControllersEnabled == false)
            return;
            
        if (frame.Has<Health>(filter.Entity) && frame.Get<Health>(filter.Entity).IsDead)
            return;

        // Get input
        QuantumDemoInputTopDown input = filter.InputContainer->Input;
        
        // Check for basic attack
        if (input.Fire)
        {
            TryCreateSkill(frame, filter.Entity, filter.Transform->Position, 
                filter.CharacterAttacks->BasicSkillData, input.AimDirection);
        }
        
        // Check for special attack
        else if (input.AltFire)
        {
            TryCreateSkill(frame, filter.Entity, filter.Transform->Position, 
                filter.CharacterAttacks->SpecialSkillData, input.AimDirection);
        }
    }

    private void TryCreateSkill(Frame frame, EntityRef entity, FPVector2 position, 
        AssetRef<SkillData> skillDataRef, FPVector2 actionDirection)
    {
        // Skip if no skill data or invalid direction
        if (skillDataRef.Id.IsValid == false || actionDirection == FPVector2.Zero)
            return;
            
        SkillData skillData = frame.FindAsset<SkillData>(skillDataRef.Id);
        
        // Check if character has enough resource
        FP currentResourceValue = AttributesHelper.GetCurrentValue(
            frame, entity, skillData.CostType);
            
        if (currentResourceValue < skillData.Cost)
            return;
            
        // Check cooldown
        string cooldownKey = $"Skill_{skillDataRef.Id.Value}";
        if (frame.Timer.IsSet(entity, cooldownKey))
            return;
            
        // Auto-aim if needed
        if (skillData.AutoAimRadius > 0)
        {
            actionDirection = TryGetAutoAimDirection(
                frame, entity, position, actionDirection, skillData);
        }
        
        // Create the skill
        frame.Signals.OnCreateSkill(entity, position, skillData, actionDirection);
        
        // Set cooldown
        FP cooldown = AttributesHelper.GetCurrentValue(frame, entity, EAttributeType.SkillCooldown);
        frame.Timer.Set(entity, cooldownKey, cooldown);
    }
    
    private FPVector2 TryGetAutoAimDirection(Frame frame, EntityRef source, 
        FPVector2 position, FPVector2 defaultDirection, SkillData skillData)
    {
        // Implementation of auto-aim logic
        // Find closest enemy within auto-aim radius
        // Check line of sight if required
        // Return direction to enemy or default direction
        
        // ... (simplified for brevity)
        
        return defaultDirection;
    }
}
```

## Health System

The `HealthSystem` manages character health and damage:

```csharp
[Preserve]
public unsafe class HealthSystem : SystemMainThreadFilter<HealthSystem.Filter>, 
    ISignalOnCharacterDamage, ISignalOnSetCharacterImmune
{
    public struct Filter
    {
        public EntityRef Entity;
        public Health* Health;
    }

    // Apply damage to a character
    public static void ApplyDamage(Frame frame, EntityRef target, 
        EntityRef source, FP amount)
    {
        // Skip if target is already dead
        Health* health = frame.Unsafe.GetPointer<Health>(target);
        if (health->IsDead || health->IsImmortal)
            return;
            
        // Reduce armor if available
        FP armor = AttributesHelper.GetCurrentValue(frame, target, EAttributeType.Armor);
        FP damageReduction = FPMath.Min(armor, amount * FP._0_50);
        FP finalDamage = amount - damageReduction;
        
        // Apply damage
        health->Current -= finalDamage;
        
        // Send damage event
        frame.Events.CharacterDamaged(target, finalDamage);
        frame.Signals.OnCharacterDamage(target);
        
        // Check if character died
        if (health->Current <= 0)
        {
            health->Current = 0;
            health->IsDead = true;
            
            // Handle character defeat
            HandleCharacterDefeat(frame, target, source);
        }
    }
    
    // Handle character defeat
    private static void HandleCharacterDefeat(Frame frame, EntityRef character, 
        EntityRef killer)
    {
        // Send defeat event
        frame.Events.CharacterDefeated(character);
        frame.Signals.OnCharacterDefeated(character);
        
        // Increment killer's score if valid
        if (frame.Exists(killer) && frame.Has<Player>(killer))
        {
            Player* player = frame.Unsafe.GetPointer<Player>(killer);
            player->Kills++;
        }
        
        // Handle respawn setup
        if (frame.Has<Respawn>(character))
        {
            Respawn* respawn = frame.Unsafe.GetPointer<Respawn>(character);
            respawn->Timer = 0;
            respawn->IsDead = true;
        }
    }
    
    // Set character temporary immunity (e.g., after respawn)
    public void OnSetCharacterImmune(Frame frame, EntityRef character, FP time)
    {
        if (frame.Has<Health>(character))
        {
            Health* health = frame.Unsafe.GetPointer<Health>(character);
            health->IsImmortal = true;
            
            // Set timer to disable immortality
            frame.Timer.Set(character, "Immortality", time, () => {
                if (frame.Exists(character))
                {
                    Health* h = frame.Unsafe.GetPointer<Health>(character);
                    h->IsImmortal = false;
                }
            });
        }
    }
    
    // Called when character takes damage (for effects, etc.)
    public void OnCharacterDamage(Frame frame, EntityRef character)
    {
        // Implementation of damage reactions
        // e.g., visual effects, interrupt actions, etc.
    }
}
```

## Skill Example: Projectile Skill

Here's an example of a custom skill implementation:

```csharp
// Arrow shot skill (simplified)
public unsafe class ArrowSkillData : SkillData
{
    public FP ProjectileSpeed = 20;
    public int ProjectileCount = 1;
    public FP SpreadAngle = 0;
    
    public override EntityRef OnAction(Frame frame, EntityRef source, 
        EntityRef skillEntity, Skill* skill)
    {
        EntityRef result = default;
        Transform2D sourceTransform = frame.Get<Transform2D>(source);
        
        // Calculate spread for multiple projectiles
        FP baseAngle = sourceTransform.Rotation;
        FP spreadStep = SpreadAngle / FPMath.Max(1, ProjectileCount - 1);
        FP startAngle = baseAngle - SpreadAngle / 2;
        
        // Create each projectile
        for (int i = 0; i < ProjectileCount; i++)
        {
            // Calculate this projectile's angle
            FP angle = startAngle + spreadStep * i;
            FPVector2 direction = FPVector2.FromAngle(angle);
            
            // Create projectile entity
            EntityRef projectile = frame.Create(AttackPrototype);
            
            // Set position and direction
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(projectile);
            transform->Position = sourceTransform.Position;
            transform->Rotation = angle;
            
            // Set projectile properties
            Attack* attack = frame.Unsafe.GetPointer<Attack>(projectile);
            attack->Source = source;
            
            // Add movement component
            PhysicsBody2D* body = frame.Unsafe.AddOrGetPointer<PhysicsBody2D>(projectile);
            body->Velocity = direction * ProjectileSpeed;
            
            // Initialize attack data
            AttackData attackData = frame.FindAsset<AttackData>(attack->AttackData.Id);
            attackData.OnCreate(frame, projectile, source, attack);
            
            result = projectile;
        }
        
        // Play attack sound
        frame.Events.SkillAction(skill->SkillData.Id);
        
        return result;
    }
}
```

## Skill Example: Area Effect

Here's another example of a custom skill:

```csharp
// Spellcaster area effect (simplified)
public unsafe class SpellAreaSkillData : SkillData
{
    public FP Radius = 3;
    public FP GrowthRate = 1;
    public FP MaxRadius = 5;
    
    public override EntityRef OnCreate(Frame frame, EntityRef source, 
        SkillData data, FPVector2 characterPos, FPVector2 actionVector)
    {
        // Calculate target position
        FPVector2 targetPos = characterPos + actionVector.Normalized * Radius;
        
        // Create base skill entity
        EntityRef skillEntity = base.OnCreate(frame, source, data, characterPos, actionVector);
        
        // Set skill position to target position
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(skillEntity);
        transform->Position = targetPos;
        
        return skillEntity;
    }
    
    public override EntityRef OnAction(Frame frame, EntityRef source, 
        EntityRef skillEntity, Skill* skill)
    {
        // Create attack entity
        EntityRef attackEntity = frame.Create(AttackPrototype);
        
        // Position attack at skill position
        Transform2D skillTransform = frame.Get<Transform2D>(skillEntity);
        Transform2D* attackTransform = frame.Unsafe.GetPointer<Transform2D>(attackEntity);
        attackTransform->Position = skillTransform.Position;
        
        // Set attack properties
        Attack* attack = frame.Unsafe.GetPointer<Attack>(attackEntity);
        attack->Source = source;
        
        // Create growing circle collision
        CircleCollider2D* collider = frame.Unsafe.AddOrGetPointer<CircleCollider2D>(attackEntity);
        collider->Radius = Radius + (skill->TTL * GrowthRate);
        collider->Radius = FPMath.Min(collider->Radius, MaxRadius);
        
        // Initialize attack
        AttackData attackData = frame.FindAsset<AttackData>(attack->AttackData.Id);
        attackData.OnCreate(frame, attackEntity, source, attack);
        
        // Play effect
        frame.Events.SkillAction(skill->SkillData.Id);
        
        return attackEntity;
    }
}
```

## Best Practices

1. **Polymorphic Skill Design**: Use inheritance to create specialized skill behaviors
2. **Data-Driven Configuration**: Keep skill parameters in assets for easy tuning
3. **Entity-Based Skills**: Represent skills and attacks as entities in the ECS
4. **Clear Separation of Concerns**:
   - `SkillData`: Defines skill behavior
   - `SkillSystem`: Manages skill lifecycle
   - `AttackData`: Defines attack behavior
   - `AttackSystem`: Manages attack lifecycle
   - `HealthSystem`: Handles damage application
5. **Resource Management**: Tie skill usage to character resources
6. **Cooldown System**: Use timers for skill cooldowns
7. **Event-Based Visual Effects**: Use events to synchronize view effects

## Implementation Notes

1. Skills and attacks are separate concepts - skills create attacks
2. The polymorphic design allows for diverse skill behaviors 
3. The data-driven approach makes balancing and tuning easier
4. Both player and AI characters use the same skill system
5. All calculations are fully deterministic for network consistency
6. Event system synchronizes view effects with simulation