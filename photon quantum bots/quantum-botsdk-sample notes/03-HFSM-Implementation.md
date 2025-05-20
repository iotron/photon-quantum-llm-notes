# Hierarchical Finite State Machine (HFSM) Implementation

This document details the implementation of Hierarchical Finite State Machines (HFSM) in the Photon Quantum Bot SDK.

## Core Components

### HFSMAgent

The `HFSMAgent` is a component attached to entities that use HFSMs:

```csharp
public unsafe partial struct HFSMAgent : IComponent
{
    // Runtime data for the HFSM execution
    public HFSMData Data;
}
```

### HFSMData

`HFSMData` contains the runtime state of the HFSM:

```csharp
public struct HFSMData
{
    // Reference to the root state
    public AssetRef<HFSMRoot> Root;
    
    // Current state of the HFSM
    public AssetRef<HFSMState> CurrentState;
    
    // When state was entered (for timing transitions)
    public long CurrentStateEnterTimestamp;
}
```

### HFSMRoot

An `HFSMRoot` is an asset that defines the structure of an HFSM:

```csharp
public class HFSMRoot : AssetObject
{
    // Initial state of the HFSM
    public AssetRef<HFSMState> InitialState;
    
    // Global parameters shared between states
    public List<AIParam> GlobalParams;
}
```

### HFSMState

Each `HFSMState` represents a state in the HFSM:

```csharp
public class HFSMState : AssetObject
{
    // Name of the state for debugging
    public string StateName;
    
    // Actions executed when entering this state
    public List<AIAction> EntryActions;
    
    // Actions executed when in this state
    public List<AIAction> StateActions;
    
    // Actions executed when exiting this state
    public List<AIAction> ExitActions;
    
    // Transitions to other states
    public List<HFSMTransition> Transitions;
    
    // Child states if this is a parent state
    public List<HFSMState> ChildStates;
    
    // Parent state reference
    public HFSMState ParentState;
}
```

### HFSMTransition

`HFSMTransition` defines state transitions in the HFSM:

```csharp
public class HFSMTransition
{
    // The decision condition that triggers this transition
    public HFSMDecision Decision;
    
    // The state to transition to if the decision returns true
    public AssetRef<HFSMState> TrueState;
    
    // The state to transition to if the decision returns false
    public AssetRef<HFSMState> FalseState;
}
```

### HFSMDecision

`HFSMDecision` is a condition that determines state transitions:

```csharp
public abstract class HFSMDecision : AssetObject
{
    // Evaluate the decision
    public abstract bool Decide(Frame frame, EntityRef entity, ref AIContext aiContext);
}
```

## Execution Flow

### Initialization

The `HFSMManager` handles HFSM initialization:

```csharp
public static void Init(Frame frame, EntityRef entity, HFSMRoot root)
{
    var agent = frame.Unsafe.GetPointer<HFSMAgent>(entity);
    
    agent->Data.Root = new AssetRef<HFSMRoot>(root);
    agent->Data.CurrentState = root.InitialState;
    agent->Data.CurrentStateEnterTimestamp = frame.Number;
    
    // Execute entry actions for initial state
    var state = frame.FindAsset<HFSMState>(root.InitialState.Id);
    ExecuteActions(frame, entity, state.EntryActions);
}
```

### Update

The HFSM update flow is managed by the `HFSMManager`:

```csharp
public static void Update(Frame frame, EntityRef entity)
{
    var agent = frame.Unsafe.GetPointer<HFSMAgent>(entity);
    var currentState = frame.FindAsset<HFSMState>(agent->Data.CurrentState.Id);
    
    // Execute state actions
    ExecuteActions(frame, entity, currentState.StateActions);
    
    // Check transitions
    CheckTransitions(frame, entity, currentState);
}
```

### State Transitions

State transitions are evaluated based on decisions:

```csharp
private static void CheckTransitions(Frame frame, EntityRef entity, HFSMState currentState)
{
    var agent = frame.Unsafe.GetPointer<HFSMAgent>(entity);
    var aiContext = new AIContext();
    
    foreach (var transition in currentState.Transitions)
    {
        bool result = transition.Decision.Decide(frame, entity, ref aiContext);
        
        AssetRef<HFSMState> nextState = result ? transition.TrueState : transition.FalseState;
        
        if (nextState != default && nextState != agent->Data.CurrentState)
        {
            // Execute exit actions for current state
            ExecuteActions(frame, entity, currentState.ExitActions);
            
            // Update state
            agent->Data.CurrentState = nextState;
            agent->Data.CurrentStateEnterTimestamp = frame.Number;
            
            // Execute entry actions for new state
            var newState = frame.FindAsset<HFSMState>(nextState.Id);
            ExecuteActions(frame, entity, newState.EntryActions);
            
            break;
        }
    }
}
```

## Example Implementation

From the Collectors Sample, here's an example HFSM action:

```csharp
public unsafe partial class ChooseCollectibleAction : AIAction
{
    public override unsafe void Execute(Frame frame, EntityRef e, ref AIContext aiContext)
    {
        var collectibles = frame.GetComponentIterator<Collectible>();
        var guyTransform = frame.Unsafe.GetPointer<Transform2D>(e);

        EntityRef closestCollectible = default;
        FP min = FP.UseableMax;

        foreach (var (entity, collectible) in collectibles)
        {
            var collTransform = frame.Get<Transform2D>(entity);
            var distance = (guyTransform->Position - collTransform.Position).SqrMagnitude;

            if (closestCollectible == default || distance < min)
            {
                closestCollectible = entity;
                min = distance;
            }
        }

        if (closestCollectible != null)
        {
            frame.Unsafe.GetPointer<Collector>(e)->DesiredCollectible = closestCollectible;
        }
    }
}
```

And an example HFSM decision:

```csharp
public class HasCollectibleDecision : HFSMDecision
{
    public override unsafe bool Decide(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        var collector = frame.Unsafe.GetPointer<Collector>(entity);
        return collector->HasCollectible;
    }
}
```

## Hierarchical Structure

The "Hierarchical" in HFSM enables nesting states within parent states:

1. Child states inherit transitions from parent states
2. Parent states can have entry/exit actions that apply to all child states
3. The hierarchy can be used to model complex state transitions more cleanly

## Creating Custom HFSM Components

### Custom Actions

To create a custom action:

```csharp
[Serializable]
public class MyCustomAction : AIAction
{
    // Optional parameters
    public FP Speed;
    
    public override void Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Implementation
    }
}
```

### Custom Decisions

To create a custom decision:

```csharp
[Serializable]
public class MyCustomDecision : HFSMDecision
{
    // Optional parameters
    public FP Threshold;
    
    public override bool Decide(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Evaluation logic
        return result;
    }
}
```

## Best Practices

1. **Organize states hierarchically** - Use parent states for common behavior
2. **Keep actions focused** - Each action should do one thing well
3. **Use the AIContext** - Store temporary data in the AIContext to pass between actions
4. **Design clear transitions** - Make state transitions intuitive with well-named decisions
5. **Avoid deep hierarchies** - Too many nesting levels can be hard to debug
6. **Consider performance** - Keep actions and decisions lightweight for real-time performance
