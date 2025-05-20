# Bot Combat and Attack System

This document details how bots make combat decisions and execute attacks in the twin stick shooter game.

## Combat Decision Making

Bots make combat decisions through a combination of sensor data, HFSM states, and tactical evaluation. The combat system follows this general flow:

1. **Target Detection**: Sensors identify potential targets
2. **Target Evaluation**: Tactical sensors evaluate target priority
3. **Combat State Selection**: HFSM selects an appropriate combat state
4. **Attack Execution**: Selected state executes the appropriate attack

## Target Detection and Evaluation

### SensorEyes for Target Detection

```csharp
public class SensorEyes : Sensor
{
    public FP DetectionRange = FP._10;
    public FP FieldOfView = FP._120; // In degrees
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(entity);
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            
            // Find and evaluate all visible characters
            var allCharacters = frame.Filter<Character, TeamInfo, Transform2D, Health>();
            
            EntityRef bestTarget = default;
            FP bestScore = FP._0;
            
            while (allCharacters.Next(out EntityRef characterRef, out Character character, out TeamInfo targetTeamInfo, out Transform2D targetTransform, out Health targetHealth))
            {
                // Skip allies, self, and dead targets
                if (teamInfo->Index == targetTeamInfo.Index || characterRef == entity || targetHealth.IsDead)
                    continue;
                
                // Check if target is within detection range
                FP distanceSq = FPVector2.DistanceSquared(transform->Position, targetTransform.Position);
                if (distanceSq > DetectionRange * DetectionRange)
                    continue;
                
                // Check if target is within field of view
                FPVector2 dirToTarget = (targetTransform.Position - transform->Position).Normalized;
                FP angleToTarget = FPVector2.Angle(transform->Up, dirToTarget);
                if (angleToTarget > FieldOfView * FP._0_5)
                    continue;
                
                // Check line of sight
                if (!CheckLineOfSight(frame, transform->Position, targetTransform.Position))
                    continue;
                
                // Calculate target score based on distance, health, and other factors
                FP distanceFactor = FP._1 - FPMath.Sqrt(distanceSq) / DetectionRange;
                FP healthFactor = FP._1 - targetHealth.CurrentHealth / targetHealth.MaxHealth;
                
                // Optional: Check if target is attacking us or allies
                bool isAttackingUs = IsTargetAttackingUs(frame, entity, characterRef);
                FP threatFactor = isAttackingUs ? FP._2 : FP._1;
                
                FP targetScore = distanceFactor * FP._0_4 + healthFactor * FP._0_3 + threatFactor * FP._0_3;
                
                // Select the highest-scored target
                if (targetScore > bestScore)
                {
                    bestTarget = characterRef;
                    bestScore = targetScore;
                }
            }
            
            // Update the blackboard with the best target
            if (bestTarget != default)
            {
                blackboard->Set("TargetEntity", bestTarget);
                blackboard->Set("TargetVisible", true);
                blackboard->Set("TargetScore", bestScore);
                
                // Calculate additional target information
                Transform2D targetTransform = frame.Get<Transform2D>(bestTarget);
                FPVector2 dirToTarget = (targetTransform.Position - transform->Position).Normalized;
                FP distanceToTarget = FPVector2.Distance(transform->Position, targetTransform.Position);
                
                blackboard->Set("TargetDirection", dirToTarget);
                blackboard->Set("TargetDistance", distanceToTarget);
            }
            else
            {
                blackboard->Set("TargetVisible", false);
            }
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
    
    private bool CheckLineOfSight(Frame frame, FPVector2 start, FPVector2 end)
    {
        var hit = frame.Physics2D.Raycast(start, (end - start).Normalized, FPVector2.Distance(start, end), frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
        return !hit.HasValue;
    }
    
    private bool IsTargetAttackingUs(Frame frame, EntityRef entity, EntityRef targetEntity)
    {
        // Check if the target is currently attacking us or our allies
        // This could be based on recent attacks, aim direction, etc.
        return false; // Simplified for this example
    }
}
```

The SensorEyes component is responsible for:
1. Detecting potential targets within range and field of view
2. Checking line of sight to ensure the target is visible
3. Evaluating targets based on distance, health, and threat level
4. Updating the blackboard with information about the best target

## Combat HFSM States

### Engage State

```csharp
public class EngagementSteering : HFSMNode
{
    public FP OptimalCombatDistance = FP._5;
    public FP DistanceTolerance = FP._1;
    
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        AISteering* steering = frame.Unsafe.GetPointer<AISteering>(entity);
        
        // Get the target from the blackboard
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Enable context steering for combat
        steering->SetContextSteeringEntry(frame, entity, targetEntity, 
            runDistance: FP._2, 
            threatDistance: OptimalCombatDistance + DistanceTolerance);
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Check if we have a target
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Get target position and direction
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
        
        // Update aim direction
        bot->Input.AimDirection = dirToTarget;
    }
}
```

The EngagementSteering state handles movement during combat:
1. Sets up context steering to maintain optimal combat distance
2. Updates the bot's aim direction to face the target
3. Monitors target availability and finishes if the target is lost

### Attack State

```csharp
public class HoldAttack : HFSMNode
{
    public FP AttackDuration = FP._1;
    private FP _attackTimer;
    
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Reset attack timer
        _attackTimer = AttackDuration;
        
        // Start attacking
        bot->Input.Attack = true;
        
        // Get the target from the blackboard
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Aim at the target
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
        bot->Input.AimDirection = dirToTarget;
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Update attack timer
        _attackTimer -= deltaTime;
        if (_attackTimer <= 0)
        {
            HasFinished = true;
            return;
        }
        
        // Check if we still have a target
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Update aim direction
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
        bot->Input.AimDirection = dirToTarget;
    }
    
    protected override void OnExit(Frame frame, EntityRef entity)
    {
        base.OnExit(frame, entity);
        
        // Stop attacking
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        bot->Input.Attack = false;
    }
}
```

The HoldAttack state executes a basic attack:
1. Activates the attack input
2. Aims at the target
3. Maintains the attack for a specified duration
4. Deactivates the attack input when exiting

### Special Attack State

```csharp
public class SpecialAttack : HFSMNode
{
    public FP AttackDuration = FP._0_5;
    public FP CooldownDuration = FP._5;
    private FP _attackTimer;
    
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Reset attack timer
        _attackTimer = AttackDuration;
        
        // Start special attack
        bot->Input.SpecialAttack = true;
        
        // Get the target from the blackboard
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Aim at the target
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
        bot->Input.AimDirection = dirToTarget;
        
        // Set cooldown in blackboard
        blackboard->Set("SpecialAttackCooldown", CooldownDuration);
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Update attack timer
        _attackTimer -= deltaTime;
        if (_attackTimer <= 0)
        {
            HasFinished = true;
            return;
        }
        
        // Continue updating aim direction
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        if (blackboard->Has("TargetEntity"))
        {
            EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
            
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
            
            FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
            bot->Input.AimDirection = dirToTarget;
        }
    }
    
    protected override void OnExit(Frame frame, EntityRef entity)
    {
        base.OnExit(frame, entity);
        
        // Stop special attack
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        bot->Input.SpecialAttack = false;
    }
}
```

The SpecialAttack state executes a special attack:
1. Activates the special attack input
2. Aims at the target
3. Maintains the attack for a specified duration
4. Sets a cooldown in the blackboard
5. Deactivates the special attack input when exiting

## Attack Decision Conditions

### InAttackRange

```csharp
public class InAttackRange : HFSMDecision
{
    public FP AttackRange = FP._4;
    
    public override bool Decide(Frame frame, EntityRef entity)
    {
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Check if we have a target
        if (!blackboard->Has("TargetEntity"))
            return false;
        
        // Check if target is in range
        FP targetDistance = blackboard->GetOrDefault<FP>("TargetDistance");
        return targetDistance <= AttackRange;
    }
}
```

This decision checks if the target is within attack range.

### CanUseSpecialAttack

```csharp
public class CanUseSpecialAttack : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Check if special attack is on cooldown
        if (blackboard->Has("SpecialAttackCooldown"))
        {
            FP cooldown = blackboard->Get<FP>("SpecialAttackCooldown");
            if (cooldown > 0)
                return false;
        }
        
        // Check if we have a target
        if (!blackboard->Has("TargetEntity"))
            return false;
        
        // Check if target is in range
        FP targetDistance = blackboard->GetOrDefault<FP>("TargetDistance");
        if (targetDistance > FP._5) // Special attack range
            return false;
        
        // Check mana/energy if applicable
        // ...
        
        // Add RNG-based decision based on difficulty
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        AIConfig aiConfig = frame.FindAsset<AIConfig>(frame.Get<HFSMAgent>(entity).Config.Id);
        FP decisionThreshold = GetSpecialAttackThreshold(aiConfig.DifficultyLevel);
        
        return frame.RNG->Next() < decisionThreshold;
    }
    
    private FP GetSpecialAttackThreshold(int difficultyLevel)
    {
        switch (difficultyLevel)
        {
            case 0: return FP._0_10; // Beginner: 10% chance
            case 1: return FP._0_25; // Easy: 25% chance
            case 2: return FP._0_50; // Medium: 50% chance
            case 3: return FP._0_75; // Hard: 75% chance
            default: return FP._0_25;
        }
    }
}
```

This decision determines if the bot can use a special attack based on:
1. Cooldown status
2. Target presence and range
3. Resource availability
4. Randomized decision based on difficulty level

## Special Ability Usage

### CooldownManager

```csharp
public class CooldownManager : SystemMainThread
{
    public override void Update(Frame f)
    {
        var bots = f.Filter<Bot, AIBlackboardComponent>();
        while (bots.NextUnsafe(out EntityRef entity, out Bot* bot, out AIBlackboardComponent* blackboard))
        {
            if (bot->IsActive == false)
                continue;
            
            // Update special attack cooldown
            if (blackboard->Has("SpecialAttackCooldown"))
            {
                FP cooldown = blackboard->Get<FP>("SpecialAttackCooldown");
                cooldown -= f.DeltaTime;
                
                if (cooldown <= 0)
                {
                    blackboard->Remove("SpecialAttackCooldown");
                }
                else
                {
                    blackboard->Set("SpecialAttackCooldown", cooldown);
                }
            }
            
            // Update other ability cooldowns
            // ...
        }
    }
}
```

The CooldownManager system updates ability cooldowns for all bots.

## Combat HFSM Structure

```csharp
public override HFSMGraphTree BuildGraph()
{
    HFSMGraphTree graph = new HFSMGraphTree();
    
    // Root and main states
    string rootState = graph.CreateHFSMNode("Root", null, null, null);
    string combatState = graph.CreateHFSMNode("Combat", null, null, null);
    // Other main states...
    
    // Combat sub-states
    string engageState = graph.CreateNode("Engage", EngageLeaf);
    string attackState = graph.CreateNode("Attack", AttackLeaf);
    string specialAttackState = graph.CreateNode("SpecialAttack", SpecialAttackLeaf);
    
    // Connect combat sub-states
    graph.ConnectChildToParent(combatState, engageState);
    graph.ConnectChildToParent(combatState, attackState);
    graph.ConnectChildToParent(combatState, specialAttackState);
    
    // Set up transitions
    graph.CreateTransition(engageState, attackState, "InAttackRange");
    graph.CreateTransition(engageState, specialAttackState, "CanUseSpecialAttack");
    graph.CreateTransition(attackState, engageState, "AttackFinished");
    graph.CreateTransition(specialAttackState, engageState, "AttackFinished");
    
    // Set default node for combat state
    graph.SetDefaultNode(combatState, engageState);
    
    // Return the graph
    return graph;
}
```

This HFSM structure defines the combat behavior flow:
1. Engage state for positioning
2. Attack state for basic attacks
3. SpecialAttack state for special abilities
4. Transitions based on range, cooldowns, and attack completion

## Aim Prediction and Accuracy

```csharp
public class AimPrediction : HFSMNode
{
    public FP ProjectileSpeed = FP._15;
    public FP AimAccuracy = FP._0_75; // 0.0 to 1.0
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        
        // Check if we have a target
        if (!blackboard->Has("TargetEntity"))
            return;
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Get target position and velocity
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        FPVector2 targetPosition = targetTransform->Position;
        
        // Get target velocity if it has KCC
        FPVector2 targetVelocity = default;
        if (frame.Has<KCC>(targetEntity))
        {
            KCC* targetKCC = frame.Unsafe.GetPointer<KCC>(targetEntity);
            targetVelocity = targetKCC->Velocity;
        }
        
        // Calculate interception point
        FPVector2 interceptPoint = CalculateInterceptPoint(
            transform->Position,
            targetPosition,
            targetVelocity,
            ProjectileSpeed);
        
        // Apply accuracy factor
        FPVector2 perfectAimDirection = (interceptPoint - transform->Position).Normalized;
        FPVector2 directAimDirection = (targetPosition - transform->Position).Normalized;
        
        // Get difficulty-based accuracy
        AIConfig aiConfig = frame.FindAsset<AIConfig>(frame.Get<HFSMAgent>(entity).Config.Id);
        FP accuracyFactor = aiConfig.DifficultyLevel >= 3 ? FP._1 : AimAccuracy;
        
        // Add randomness based on accuracy
        FP randomAngle = (FP._1 - accuracyFactor) * FP._30 * (frame.RNG->Next() * FP._2 - FP._1);
        FP angleRadians = randomAngle * FP.Deg2Rad;
        FPVector2 randomizedDirection = new FPVector2(
            perfectAimDirection.X * FPMath.Cos(angleRadians) - perfectAimDirection.Y * FPMath.Sin(angleRadians),
            perfectAimDirection.X * FPMath.Sin(angleRadians) + perfectAimDirection.Y * FPMath.Cos(angleRadians));
        
        // Interpolate between perfect aim and randomized aim based on accuracy
        bot->Input.AimDirection = FPVector2.Lerp(randomizedDirection, perfectAimDirection, accuracyFactor);
    }
    
    private FPVector2 CalculateInterceptPoint(FPVector2 shooterPosition, FPVector2 targetPosition, FPVector2 targetVelocity, FP projectileSpeed)
    {
        // Calculate time to intercept
        FPVector2 relativePosition = targetPosition - shooterPosition;
        FP a = FPVector2.Dot(targetVelocity, targetVelocity) - projectileSpeed * projectileSpeed;
        FP b = 2 * FPVector2.Dot(targetVelocity, relativePosition);
        FP c = FPVector2.Dot(relativePosition, relativePosition);
        
        FP discriminant = b * b - 4 * a * c;
        
        if (discriminant < 0 || FPMath.Abs(a) < FP._0_001)
        {
            // No solution, return direct aim
            return targetPosition;
        }
        
        FP time1 = (-b + FPMath.Sqrt(discriminant)) / (2 * a);
        FP time2 = (-b - FPMath.Sqrt(discriminant)) / (2 * a);
        
        FP interceptTime = FPMath.Min(time1, time2);
        if (interceptTime < 0)
        {
            interceptTime = FPMath.Max(time1, time2);
        }
        
        if (interceptTime < 0)
        {
            // No valid solution, return direct aim
            return targetPosition;
        }
        
        // Calculate intercept position
        return targetPosition + targetVelocity * interceptTime;
    }
}
```

The AimPrediction functionality:
1. Calculates an interception point based on target velocity and projectile speed
2. Applies accuracy based on difficulty level
3. Adds randomness based on accuracy
4. Interpolates between perfect aim and randomized aim

## Integration with Attack System

```csharp
public class AttackSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Process bot attacks
        var bots = frame.Filter<Bot, Transform2D>();
        while (bots.NextUnsafe(out EntityRef entity, out Bot* bot, out Transform2D* transform))
        {
            if (bot->IsActive == false)
                continue;
            
            // Process basic attack
            if (bot->Input.Attack)
            {
                // Check if the bot has the required components
                if (frame.Has<Character>(entity) && frame.Has<TeamInfo>(entity))
                {
                    Character* character = frame.Unsafe.GetPointer<Character>(entity);
                    TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(entity);
                    
                    // Create attack based on character type
                    CreateAttack(frame, entity, character, teamInfo, transform, bot->Input.AimDirection, false);
                }
            }
            
            // Process special attack
            if (bot->Input.SpecialAttack)
            {
                // Check if the bot has the required components
                if (frame.Has<Character>(entity) && frame.Has<TeamInfo>(entity))
                {
                    Character* character = frame.Unsafe.GetPointer<Character>(entity);
                    TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(entity);
                    
                    // Create special attack based on character type
                    CreateAttack(frame, entity, character, teamInfo, transform, bot->Input.AimDirection, true);
                }
            }
        }
    }
    
    private void CreateAttack(Frame frame, EntityRef entity, Character* character, TeamInfo* teamInfo, Transform2D* transform, FPVector2 direction, bool isSpecial)
    {
        // Get character data
        CharacterInfo characterInfo = frame.FindAsset<CharacterInfo>(character->CharacterInfo.Id);
        
        // Get attack data
        AssetRef attackDataRef = isSpecial ? characterInfo.SpecialAttackData : characterInfo.BasicAttackData;
        SkillData attackData = frame.FindAsset<SkillData>(attackDataRef.Id);
        
        // Create attack
        frame.Signals.OnCreateSkill(entity, transform->Position, attackData, direction);
    }
}
```

The AttackSystem processes bot attack inputs:
1. Checks for basic and special attack inputs
2. Gets character and attack data
3. Creates attacks based on character type and input direction
4. Signals the creation of skills and attacks

This combat system allows bots to make intelligent targeting decisions, execute appropriate attacks, and adapt their combat behavior based on the situation and difficulty level.
