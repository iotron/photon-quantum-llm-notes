# Implementing a Sample Bot

This document provides a complete example of implementing a specific bot type in the twin stick shooter game.

## Archer Bot Implementation

In this example, we'll implement a complete Archer bot that specializes in ranged combat and mobility.

### Bot Prototype

First, we define the Archer bot prototype:

```csharp
[CreateAssetMenu(menuName = "Quantum/EntityPrototype/ArcherBot")]
public class ArcherBotPrototype : BotPrototype
{
    [Header("Archer Specific Properties")]
    public FP PreferredRange = FP._8;
    public FP KitingDistance = FP._4;
    public FP SpecialAttackRange = FP._10;
    
    public override unsafe EntityRef Create(Frame frame)
    {
        EntityRef entity = base.Create(frame);
        
        // Get components
        Character* character = frame.Unsafe.GetPointer<Character>(entity);
        character->CharacterClass = CharacterClass.Archer;
        
        // Set up combat properties
        AttackComponent* attackComponent = frame.Unsafe.GetPointer<AttackComponent>(entity);
        attackComponent->AttackRange = PreferredRange;
        attackComponent->SpecialAttackRange = SpecialAttackRange;
        
        // Add archer-specific properties to blackboard
        if (frame.Has<AIBlackboardComponent>(entity))
        {
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            blackboard->Set("PreferredRange", PreferredRange);
            blackboard->Set("KitingDistance", KitingDistance);
            blackboard->Set("SpecialAttackRange", SpecialAttackRange);
        }
        
        return entity;
    }
}
```

### Archer HFSM

Next, we define the Archer's decision-making structure:

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/HFSM/ArcherBotHFSM")]
public class ArcherBotHFSM : HFSMRoot
{
    public override HFSMGraphTree BuildGraph()
    {
        HFSMGraphTree graph = new HFSMGraphTree();
        
        // Root state
        string rootState = graph.CreateHFSMNode("Root", null, null, null);
        
        // Main behavior states
        string combatState = graph.CreateHFSMNode("Combat", null, null, null);
        string collectState = graph.CreateHFSMNode("Collect", null, null, null);
        string retreatState = graph.CreateHFSMNode("Retreat", null, null, null);
        
        // Connect main states to root
        graph.ConnectChildToParent(rootState, combatState);
        graph.ConnectChildToParent(rootState, collectState);
        graph.ConnectChildToParent(rootState, retreatState);
        
        // Set up transitions between main states
        graph.CreateTransition(combatState, retreatState, "HealthLow");
        graph.CreateTransition(retreatState, combatState, "HealthRecovered");
        graph.CreateTransition(combatState, collectState, "NoTargetsInRange");
        graph.CreateTransition(collectState, combatState, "TargetInRange");
        
        // Combat sub-states (archer-specific)
        string engageState = graph.CreateNode("Engage", EngageLeaf);
        string kitingState = graph.CreateNode("Kiting", KitingLeaf);
        string attackState = graph.CreateNode("Attack", AttackLeaf);
        string specialAttackState = graph.CreateNode("SpecialAttack", SpecialAttackLeaf);
        string repositionState = graph.CreateNode("Reposition", RepositionLeaf);
        
        // Connect combat sub-states
        graph.ConnectChildToParent(combatState, engageState);
        graph.ConnectChildToParent(combatState, kitingState);
        graph.ConnectChildToParent(combatState, attackState);
        graph.ConnectChildToParent(combatState, specialAttackState);
        graph.ConnectChildToParent(combatState, repositionState);
        
        // Set up combat sub-state transitions
        graph.CreateTransition(engageState, attackState, "InAttackRange");
        graph.CreateTransition(engageState, kitingState, "EnemyTooClose");
        graph.CreateTransition(attackState, engageState, "AttackFinished");
        graph.CreateTransition(kitingState, attackState, "ReachedSafeDistance");
        graph.CreateTransition(engageState, specialAttackState, "CanUseSpecialAttack");
        graph.CreateTransition(specialAttackState, engageState, "AttackFinished");
        graph.CreateTransition(engageState, repositionState, "NeedsBetterPosition");
        graph.CreateTransition(repositionState, engageState, "RepositionComplete");
        
        // Collection sub-states
        string findCollectibleState = graph.CreateNode("FindCollectible", FindCollectibleLeaf);
        string moveToCollectibleState = graph.CreateNode("MoveToCollectible", MoveToCollectibleLeaf);
        
        // Connect collection sub-states
        graph.ConnectChildToParent(collectState, findCollectibleState);
        graph.ConnectChildToParent(collectState, moveToCollectibleState);
        
        // Set up collection sub-state transitions
        graph.CreateTransition(findCollectibleState, moveToCollectibleState, "CollectibleFound");
        graph.CreateTransition(moveToCollectibleState, findCollectibleState, "CollectibleReached");
        
        // Retreat sub-states
        string findCoverState = graph.CreateNode("FindCover", FindCoverLeaf);
        string moveToCoverState = graph.CreateNode("MoveToCover", MoveToCoverLeaf);
        
        // Connect retreat sub-states
        graph.ConnectChildToParent(retreatState, findCoverState);
        graph.ConnectChildToParent(retreatState, moveToCoverState);
        
        // Set up retreat sub-state transitions
        graph.CreateTransition(findCoverState, moveToCoverState, "CoverFound");
        graph.CreateTransition(moveToCoverState, findCoverState, "CoverReached");
        
        // Set default nodes
        graph.SetDefaultNode(rootState, combatState);
        graph.SetDefaultNode(combatState, engageState);
        graph.SetDefaultNode(collectState, findCollectibleState);
        graph.SetDefaultNode(retreatState, findCoverState);
        
        return graph;
    }
    
    // Leaf node implementations
    private System.Type EngageLeaf => typeof(ArcherEngagementSteering);
    private System.Type KitingLeaf => typeof(ArcherKiting);
    private System.Type AttackLeaf => typeof(ArcherAttack);
    private System.Type SpecialAttackLeaf => typeof(ArcherSpecialAttack);
    private System.Type RepositionLeaf => typeof(ArcherRepositioning);
    private System.Type FindCollectibleLeaf => typeof(SelectCollectible);
    private System.Type MoveToCollectibleLeaf => typeof(ChaseCollectible);
    private System.Type FindCoverLeaf => typeof(FindCoverSpot);
    private System.Type MoveToCoverLeaf => typeof(RunToCoverSpot);
}
```

### Archer-Specific HFSM Nodes

Now we implement the archer-specific behavior nodes:

```csharp
// Archer engagement steering behavior
public class ArcherEngagementSteering : HFSMNode
{
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        AISteering* steering = frame.Unsafe.GetPointer<AISteering>(entity);
        
        // Get target and preferred range
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
        
        // Enable steering to maintain preferred range
        steering->SetContextSteeringEntry(frame, entity, targetEntity, 
            runDistance: preferredRange * FP._0_5,     // Run if closer than half preferred range
            threatDistance: preferredRange * FP._1_5); // Approach if further than 1.5x preferred range
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
        
        // Calculate line of sight
        bool hasLineOfSight = CheckLineOfSight(frame, transform->Position, targetTransform->Position);
        blackboard->Set("HasLineOfSight", hasLineOfSight);
        
        // Update target distance
        FP targetDistance = FPVector2.Distance(transform->Position, targetTransform->Position);
        blackboard->Set("TargetDistance", targetDistance);
    }
    
    private bool CheckLineOfSight(Frame frame, FPVector2 start, FPVector2 end)
    {
        var hit = frame.Physics2D.Raycast(start, (end - start).Normalized, FPVector2.Distance(start, end), frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
        return !hit.HasValue;
    }
}

// Archer kiting behavior
public class ArcherKiting : HFSMNode
{
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Get target
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Set up navigation to move away from target
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        // Calculate direction away from target
        FPVector2 dirFromTarget = (transform->Position - targetTransform->Position).Normalized;
        
        // Get kiting distance
        FP kitingDistance = blackboard->GetOrDefault<FP>("KitingDistance", FP._4);
        
        // Calculate kiting position
        FPVector2 kitingPosition = transform->Position + dirFromTarget * kitingDistance;
        
        // Ensure the kiting position is valid
        NavMeshPathfinder* pathfinder = frame.Unsafe.GetPointer<NavMeshPathfinder>(entity);
        
        // Try to find a valid position for kiting
        if (!IsPositionPathable(frame, kitingPosition))
        {
            // Try alternative directions
            FPVector2 rightDir = new FPVector2(dirFromTarget.Y, -dirFromTarget.X);
            FPVector2 leftDir = new FPVector2(-dirFromTarget.Y, dirFromTarget.X);
            
            FPVector2 rightPos = transform->Position + rightDir * kitingDistance;
            FPVector2 leftPos = transform->Position + leftDir * kitingDistance;
            
            if (IsPositionPathable(frame, rightPos))
            {
                kitingPosition = rightPos;
            }
            else if (IsPositionPathable(frame, leftPos))
            {
                kitingPosition = leftPos;
            }
            else
            {
                // No valid kiting direction found, just try to move randomly
                FP randomAngle = frame.RNG->NextFloat(0, 2 * 3.14159f);
                FPVector2 randomDir = new FPVector2(FPMath.Cos(randomAngle), FPMath.Sin(randomAngle));
                kitingPosition = transform->Position + randomDir * kitingDistance;
            }
        }
        
        // Store kiting position
        blackboard->Set("KitingPosition", kitingPosition);
        
        // Set up navmesh pathfinding
        pathfinder->UpdatePath(frame, entity, kitingPosition);
        
        // Switch to navmesh steering
        AISteering* steering = frame.Unsafe.GetPointer<AISteering>(entity);
        steering->SetNavMeshSteeringEntry(frame, entity);
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
        
        // Update aim direction while kiting
        bot->Input.AimDirection = dirToTarget;
        
        // Check if we've reached a safe distance
        FP targetDistance = FPVector2.Distance(transform->Position, targetTransform->Position);
        blackboard->Set("TargetDistance", targetDistance);
        
        FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
        
        if (targetDistance >= preferredRange)
        {
            blackboard->Set("ReachedSafeDistance", true);
            HasFinished = true;
        }
    }
    
    private bool IsPositionPathable(Frame frame, FPVector2 position)
    {
        return !frame.Physics2D.OverlapCircle(position, FP._0_5, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics).HasValue;
    }
}

// Archer attack behavior
public class ArcherAttack : HFSMNode
{
    private FP _attackDuration = FP._0_5;
    private FP _attackTimer;
    private FP _attackCooldown = FP._0_5;
    private FP _cooldownTimer;
    private bool _isAttacking;
    
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Reset attack state
        _attackTimer = _attackDuration;
        _cooldownTimer = FP._0;
        _isAttacking = true;
        
        // Check if we have a target
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
        
        // Start attack
        bot->Input.Attack = true;
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Update target direction
        if (blackboard->Has("TargetEntity"))
        {
            EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
            
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
            
            FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
            bot->Input.AimDirection = dirToTarget;
            
            // Update target distance
            FP targetDistance = FPVector2.Distance(transform->Position, targetTransform->Position);
            blackboard->Set("TargetDistance", targetDistance);
            
            // Check for better position if target distance changes too much
            FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
            if (targetDistance < preferredRange * FP._0_5 || targetDistance > preferredRange * FP._1_5)
            {
                blackboard->Set("NeedsBetterPosition", true);
            }
        }
        
        // Update attack state
        if (_isAttacking)
        {
            _attackTimer -= deltaTime;
            
            if (_attackTimer <= 0)
            {
                // Finish attack
                bot->Input.Attack = false;
                _isAttacking = false;
                _cooldownTimer = _attackCooldown;
            }
        }
        else
        {
            _cooldownTimer -= deltaTime;
            
            if (_cooldownTimer <= 0)
            {
                // Attack cooldown finished
                blackboard->Set("AttackFinished", true);
                HasFinished = true;
            }
        }
    }
    
    protected override void OnExit(Frame frame, EntityRef entity)
    {
        base.OnExit(frame, entity);
        
        // Stop attack
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        bot->Input.Attack = false;
    }
}

// Archer special attack behavior
public class ArcherSpecialAttack : HFSMNode
{
    private FP _attackDuration = FP._0_5;
    private FP _attackTimer;
    
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Reset attack timer
        _attackTimer = _attackDuration;
        
        // Start special attack
        bot->Input.SpecialAttack = true;
        
        // Set cooldown in blackboard
        blackboard->Set("SpecialAttackCooldown", FP._8);
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        
        // Update aim direction
        if (blackboard->Has("TargetEntity"))
        {
            EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
            
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
            
            FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
            bot->Input.AimDirection = dirToTarget;
        }
        
        // Update attack timer
        _attackTimer -= deltaTime;
        
        if (_attackTimer <= 0)
        {
            // Finish attack
            blackboard->Set("AttackFinished", true);
            HasFinished = true;
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

// Archer repositioning behavior
public class ArcherRepositioning : HFSMNode
{
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Get target
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Calculate a good position for attacking
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        // Get preferred range
        FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
        
        // Calculate current direction to target
        FPVector2 dirToTarget = (targetTransform->Position - transform->Position).Normalized;
        
        // Try to find a position at the preferred range
        FPVector2 idealPosition = targetTransform->Position - dirToTarget * preferredRange;
        
        // Check if the ideal position is pathable
        if (!IsPositionPathable(frame, idealPosition))
        {
            // Try alternative positions
            for (int i = 0; i < 8; i++)
            {
                // Try positions at different angles
                FP angle = i * FP.Deg2Rad * 45;
                FPVector2 dir = new FPVector2(FPMath.Cos(angle), FPMath.Sin(angle));
                
                FPVector2 alternatePosition = targetTransform->Position + dir * preferredRange;
                
                if (IsPositionPathable(frame, alternatePosition))
                {
                    idealPosition = alternatePosition;
                    break;
                }
            }
        }
        
        // Store the reposition target
        blackboard->Set("RepositionTarget", idealPosition);
        
        // Set up navmesh pathfinding
        NavMeshPathfinder* pathfinder = frame.Unsafe.GetPointer<NavMeshPathfinder>(entity);
        pathfinder->UpdatePath(frame, entity, idealPosition);
        
        // Switch to navmesh steering
        AISteering* steering = frame.Unsafe.GetPointer<AISteering>(entity);
        steering->SetNavMeshSteeringEntry(frame, entity);
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Get required components
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        
        // Check if we've reached the target position
        if (blackboard->Has("RepositionTarget"))
        {
            FPVector2 repositionTarget = blackboard->Get<FPVector2>("RepositionTarget");
            
            FP distanceSquared = FPVector2.DistanceSquared(transform->Position, repositionTarget);
            
            if (distanceSquared < FP._1_5 * FP._1_5)
            {
                // Reached target position
                blackboard->Set("RepositionComplete", true);
                blackboard->Set("NeedsBetterPosition", false);
                HasFinished = true;
            }
        }
        else
        {
            // No target position
            HasFinished = true;
        }
    }
    
    private bool IsPositionPathable(Frame frame, FPVector2 position)
    {
        return !frame.Physics2D.OverlapCircle(position, FP._0_5, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics).HasValue;
    }
}
```

### Archer Decision Conditions

Now we implement the decision conditions for the Archer's HFSM:

```csharp
// Check if health is low
public class HealthLow : HFSMDecision
{
    public FP Threshold = FP._0_25; // 25% health
    
    public override bool Decide(Frame frame, EntityRef entity)
    {
        Health* health = frame.Unsafe.GetPointer<Health>(entity);
        return health->CurrentHealth / health->MaxHealth < Threshold;
    }
}

// Check if health has recovered
public class HealthRecovered : HFSMDecision
{
    public FP Threshold = FP._0_5; // 50% health
    
    public override bool Decide(Frame frame, EntityRef entity)
    {
        Health* health = frame.Unsafe.GetPointer<Health>(entity);
        return health->CurrentHealth / health->MaxHealth >= Threshold;
    }
}

// Check if a target is in range
public class TargetInRange : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->GetOrDefault<bool>("TargetVisible");
    }
}

// Check if no targets are in range
public class NoTargetsInRange : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return !blackboard->GetOrDefault<bool>("TargetVisible");
    }
}

// Check if target is in attack range
public class InAttackRange : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        if (!blackboard->Has("TargetEntity") || !blackboard->Has("TargetDistance"))
            return false;
        
        FP targetDistance = blackboard->Get<FP>("TargetDistance");
        FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
        
        // Check if distance is near preferred range
        bool inRange = FPMath.Abs(targetDistance - preferredRange) < preferredRange * FP._0_2;
        
        // Also check line of sight
        bool hasLineOfSight = blackboard->GetOrDefault<bool>("HasLineOfSight");
        
        return inRange && hasLineOfSight;
    }
}

// Check if enemy is too close for archer comfort
public class EnemyTooClose : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        if (!blackboard->Has("TargetEntity") || !blackboard->Has("TargetDistance"))
            return false;
        
        FP targetDistance = blackboard->Get<FP>("TargetDistance");
        FP preferredRange = blackboard->GetOrDefault<FP>("PreferredRange", FP._8);
        
        return targetDistance < preferredRange * FP._0_5;
    }
}

// Check if kiting has reached a safe distance
public class ReachedSafeDistance : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->GetOrDefault<bool>("ReachedSafeDistance");
    }
}

// Check if attack has finished
public class AttackFinished : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->GetOrDefault<bool>("AttackFinished");
    }
}

// Check if special attack can be used
public class CanUseSpecialAttack : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Check cooldown
        if (blackboard->Has("SpecialAttackCooldown"))
            return false;
        
        // Check if we have a target at the right distance
        if (!blackboard->Has("TargetEntity") || !blackboard->Has("TargetDistance"))
            return false;
        
        FP targetDistance = blackboard->Get<FP>("TargetDistance");
        FP specialAttackRange = blackboard->GetOrDefault<FP>("SpecialAttackRange", FP._10);
        
        bool inRange = targetDistance <= specialAttackRange;
        
        // Also check line of sight
        bool hasLineOfSight = blackboard->GetOrDefault<bool>("HasLineOfSight");
        
        // Add some randomness to decision
        FP useChance = FP._0_3; // 30% chance to use special when possible
        
        return inRange && hasLineOfSight && frame.RNG->Next() < useChance;
    }
}

// Check if archer needs to reposition
public class NeedsBetterPosition : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->GetOrDefault<bool>("NeedsBetterPosition");
    }
}

// Check if repositioning is complete
public class RepositionComplete : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->GetOrDefault<bool>("RepositionComplete");
    }
}
```

### Archer Bot Creator

Finally, we create a utility method to create Archer bots:

```csharp
public static class BotCreator
{
    public static EntityRef CreateArcherBot(Frame frame, FPVector2 position, int teamId, int difficultyLevel = 1)
    {
        // Find the archer bot prototype
        var botPrototype = frame.FindAsset<ArcherBotPrototype>("ArcherBot");
        
        // Create the bot
        EntityRef bot = frame.Create(botPrototype);
        
        // Set position
        frame.Unsafe.GetPointer<Transform2D>(bot)->Position = position;
        
        // Set team
        frame.Unsafe.GetPointer<TeamInfo>(bot)->Index = teamId;
        
        // Set difficulty level
        if (frame.Has<AIBlackboardComponent>(bot))
        {
            frame.Unsafe.GetPointer<AIBlackboardComponent>(bot)->Set("DifficultyLevel", difficultyLevel);
        }
        
        // Activate bot
        AISetupHelper.Botify(frame, bot);
        
        return bot;
    }
}
```

### Usage Example

Here's an example of using the Archer bot in a game:

```csharp
public class GameManager : SystemMainThread, ISignalOnGameStart
{
    public void OnGameStart(Frame frame)
    {
        // Create teams
        FPVector2 team1Spawn = new FPVector2(FP._5, FP._5);
        FPVector2 team2Spawn = new FPVector2(FP._15, FP._15);
        
        // Create archer bots
        for (int i = 0; i < 2; i++)
        {
            // Team 1 archers
            FPVector2 position1 = team1Spawn + new FPVector2(FP._1 * i, FP._0);
            BotCreator.CreateArcherBot(frame, position1, 0, 2); // Medium difficulty
            
            // Team 2 archers
            FPVector2 position2 = team2Spawn + new FPVector2(FP._1 * i, FP._0);
            BotCreator.CreateArcherBot(frame, position2, 1, 1); // Easy difficulty
        }
    }
}
```

This example demonstrates a complete implementation of an Archer bot for the twin stick shooter game. The bot features specialized behavior for ranged combat, including maintaining optimal distance, kiting when enemies get too close, and repositioning for better shots. The HFSM structure allows the bot to make intelligent decisions based on the current game state, creating realistic and challenging behavior.

The implementation can be used as a template for other bot types, such as melee fighters or support characters, by replacing the specialized behaviors and decision conditions with appropriate alternatives for those character types.
