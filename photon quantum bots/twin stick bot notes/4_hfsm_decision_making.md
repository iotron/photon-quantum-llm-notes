# HFSM Decision Making System

This document details the Hierarchical Finite State Machine (HFSM) decision-making system used for bots in the twin stick shooter game.

## HFSM Overview

The HFSM (Hierarchical Finite State Machine) system is the "brain" of the bot, responsible for making decisions about:
- Which targets to pursue
- When to attack
- When to retreat
- Which collectibles to gather
- How to navigate the environment

The HFSM is organized as a tree of states, where:
- Parent states represent high-level behaviors
- Child states represent specific actions
- Transitions between states are governed by conditions

## Core Components

### HFSMAgent Component

```csharp
public unsafe struct HFSMAgent
{
    public EntityRef CurrentStateEntity;
    public DynamicAssetRef<AIConfig> Config;
    // Other internal fields...
}
```

This component stores the current state and configuration for the bot's HFSM.

### HFSMRoot Asset

```csharp
public abstract class HFSMRoot : AssetObject
{
    public abstract HFSMGraphTree BuildGraph();
}
```

This asset defines the structure of the HFSM graph. Each bot type has its own HFSMRoot asset.

### HFSMNode Class

```csharp
public abstract class HFSMNode
{
    protected bool HasFinished = false;
    
    protected virtual void OnEnter(Frame frame, EntityRef entity) {}
    protected virtual void OnExit(Frame frame, EntityRef entity) {}
    protected virtual void OnUpdate(Frame frame, FP deltaTime, EntityRef entity) {}
}
```

Base class for all state behaviors. States can implement:
- OnEnter: Called when entering the state
- OnUpdate: Called every frame while in the state
- OnExit: Called when exiting the state

### HFSMDecision Class

```csharp
public abstract class HFSMDecision
{
    public abstract bool Decide(Frame frame, EntityRef entity);
}
```

Base class for all transition conditions. The Decide method returns true if the transition should be taken.

## HFSM Manager

The HFSMManager is a static class that handles HFSM initialization and updates:

```csharp
public static class HFSMManager
{
    public static void Init(Frame frame, EntityRef entity, HFSMRoot root)
    {
        // Implementation...
    }
    
    public static void Update(Frame frame, FP deltaTime, EntityRef entity)
    {
        // Implementation...
    }
}
```

### Init Method

```csharp
public static void Init(Frame frame, EntityRef entity, HFSMRoot root)
{
    // Create state entities for each node in the graph
    HFSMGraphTree graphTree = root.BuildGraph();
    
    // Create an entity for the HFSM root
    EntityRef rootEntity = frame.Create();
    
    // Create entities for states and transitions
    foreach (var state in graphTree.States)
    {
        EntityRef stateEntity = frame.Create();
        // Configure state entity...
    }
    
    foreach (var transition in graphTree.Transitions)
    {
        // Configure transitions...
    }
    
    // Set the initial state
    HFSMAgent* agent = frame.Unsafe.GetPointer<HFSMAgent>(entity);
    agent->CurrentStateEntity = rootEntity;
}
```

This method:
1. Builds the HFSM graph from the root asset
2. Creates entities for states and transitions
3. Configures the relationships between states
4. Sets the initial state

### Update Method

```csharp
public static void Update(Frame frame, FP deltaTime, EntityRef entity)
{
    HFSMAgent* agent = frame.Unsafe.GetPointer<HFSMAgent>(entity);
    EntityRef currentStateEntity = agent->CurrentStateEntity;
    
    // Check if the current state is finished
    bool stateFinished = frame.Get<HFSMStateComponent>(currentStateEntity).HasFinished;
    
    // Check transitions
    if (!stateFinished)
    {
        var transitions = frame.ResolveList(frame.Get<HFSMStateComponent>(currentStateEntity).Transitions);
        for (int i = 0; i < transitions.Count; i++)
        {
            HFSMTransition transition = frame.Get<HFSMTransition>(transitions[i]);
            if (EvaluateTransition(frame, entity, transition))
            {
                // Transition to the target state
                ChangeState(frame, entity, transition.TargetState);
                return;
            }
        }
    }
    else
    {
        // Return to parent state
        EntityRef parentState = frame.Get<HFSMStateComponent>(currentStateEntity).ParentState;
        if (parentState != default)
        {
            ChangeState(frame, entity, parentState);
            return;
        }
    }
    
    // Update the current state
    UpdateState(frame, deltaTime, entity, currentStateEntity);
}
```

This method:
1. Checks if the current state is finished
2. Evaluates all transitions from the current state
3. If a transition condition is met, changes to the target state
4. If no transitions are taken, updates the current state

## Example HFSM Implementation

Below is an example of how an HFSM might be implemented for a twin stick shooter bot:

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/HFSM/TwinStickBot")]
public class TwinStickBotHFSM : HFSMRoot
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
        
        // Set up transitions
        graph.CreateTransition(combatState, retreatState, "HealthLow");
        graph.CreateTransition(retreatState, combatState, "HealthRecovered");
        graph.CreateTransition(combatState, collectState, "NoTargetsInRange");
        graph.CreateTransition(collectState, combatState, "TargetInRange");
        
        // Combat sub-states
        string engageState = graph.CreateNode("Engage", EngageLeaf);
        string attackState = graph.CreateNode("Attack", AttackLeaf);
        
        // Connect combat sub-states
        graph.ConnectChildToParent(combatState, engageState);
        graph.ConnectChildToParent(combatState, attackState);
        
        // Set up combat sub-state transitions
        graph.CreateTransition(engageState, attackState, "InAttackRange");
        graph.CreateTransition(attackState, engageState, "OutOfAttackRange");
        
        // Collect sub-states
        string findCollectibleState = graph.CreateNode("FindCollectible", FindCollectibleLeaf);
        string moveToCollectibleState = graph.CreateNode("MoveToCollectible", MoveToCollectibleLeaf);
        
        // Connect collect sub-states
        graph.ConnectChildToParent(collectState, findCollectibleState);
        graph.ConnectChildToParent(collectState, moveToCollectibleState);
        
        // Set up collect sub-state transitions
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
    private System.Type EngageLeaf => typeof(EngagementSteering);
    private System.Type AttackLeaf => typeof(HoldAttack);
    private System.Type FindCollectibleLeaf => typeof(SelectCollectible);
    private System.Type MoveToCollectibleLeaf => typeof(ChaseCollectible);
    private System.Type FindCoverLeaf => typeof(FindCoverSpot);
    private System.Type MoveToCoverLeaf => typeof(RunToCoverSpot);
}
```

This HFSM defines:
1. Three main behavior states: Combat, Collect, and Retreat
2. Sub-states for each main behavior
3. Transitions between states based on conditions
4. Leaf node implementations for specific actions

## Example Decision Classes

Here are examples of decision classes used for HFSM transitions:

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

// Check if a target is in attack range
public class InAttackRange : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        if (!blackboard->Has("TargetEntity"))
            return false;
            
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        FP attackRange = blackboard->Get<FP>("AttackRange");
        
        FPVector2 position = frame.Get<Transform2D>(entity).Position;
        FPVector2 targetPosition = frame.Get<Transform2D>(targetEntity).Position;
        
        return FPVector2.Distance(position, targetPosition) <= attackRange;
    }
}

// Check if a collectible has been found
public class CollectibleFound : HFSMDecision
{
    public override bool Decide(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        return blackboard->Has("TargetCollectible");
    }
}
```

## Example Action Classes

Here are examples of action classes that implement state behaviors:

```csharp
// Engage with a target
public class EngagementSteering : HFSMNode
{
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get the target from the blackboard
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        if (!blackboard->Has("TargetEntity"))
            return;
            
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Set context steering to move toward the target
        AISteering* steering = frame.Unsafe.GetPointer<AISteering>(entity);
        steering->SetContextSteeringEntry(frame, entity, targetEntity, FP._2, FP._5);
    }
    
    protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
    {
        base.OnUpdate(frame, deltaTime, entity);
        
        // Check if we still have a target
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        if (!blackboard->Has("TargetEntity"))
        {
            HasFinished = true;
            return;
        }
        
        // Continue moving toward the target
    }
    
    protected override void OnExit(Frame frame, EntityRef entity)
    {
        base.OnExit(frame, entity);
        
        // Clean up any state
    }
}

// Attack a target
public class HoldAttack : HFSMNode
{
    protected override void OnEnter(Frame frame, EntityRef entity)
    {
        base.OnEnter(frame, entity);
        
        // Get the target from the blackboard
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        if (!blackboard->Has("TargetEntity"))
            return;
            
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Aim at the target
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
        
        FPVector2 direction = (targetTransform->Position - transform->Position).Normalized;
        bot->Input.AimDirection = direction;
        
        // Start attacking
        bot->Input.Attack = true;
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

## Blackboard System

The HFSM interacts with the bot's blackboard to read sensor data and store state information:

```csharp
// Example of reading from and writing to the blackboard
protected override void OnUpdate(Frame frame, FP deltaTime, EntityRef entity)
{
    base.OnUpdate(frame, deltaTime, entity);
    
    AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
    
    // Read a value
    bool hasTarget = blackboard->Has("TargetEntity");
    
    if (hasTarget)
    {
        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
        
        // Do something with the target
        
        // Write a value
        blackboard->Set("LastTargetPosition", frame.Get<Transform2D>(targetEntity).Position);
    }
}
```

The blackboard is the primary means of communication between sensors, the HFSM, and other bot systems.

## Integration with Other Systems

The HFSM integrates with:
- **Sensors**: Read perception data from the blackboard
- **Steering**: Control movement by setting steering parameters
- **Input**: Control attacks and other actions through the Bot's Input component
- **Memory**: Read and write to the bot's memory for long-term information

This integration allows the HFSM to make informed decisions based on the game state and execute actions through the bot's systems.
