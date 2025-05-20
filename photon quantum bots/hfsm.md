# Hierarchical Finite State Machine (HFSM)

## Introduction

The Hierarchical Finite State Machine (HFSM) is one of the AI models offered by the Quantum Bot SDK. An HFSM consists of states, actions, and transitions that define the behavior of an AI agent. The "hierarchical" aspect allows states to contain sub-states, creating a multi-level organization that helps manage complex AI logic.

## Key Components

### States
- Represent distinct behavioral modes for an agent
- Can contain actions (on enter, on update, on exit)
- Can have child states (creating hierarchical levels)
- One state is designated as the "initial state" at each hierarchy level

### Transitions
- Links between states that define how an agent can change states
- Include conditions (decisions) that determine when a transition occurs
- Can be triggered by events from outside the HFSM
- Have priorities that determine evaluation order

### Actions
- Logic executed when entering, updating, or exiting a state
- Directly affect game state (e.g., moving an entity, using abilities)
- Can be chained sequentially for complex behaviors

## Special Transition Types

### Transition Sets
- Group multiple transitions for reuse and organization
- Help simplify complex transition logic

### ANY Transitions
- Apply to all states at the same hierarchy level
- Create universal transitions without defining them for each state
- Can include or exclude specific states

### Portal Transitions
- Force state changes across hierarchy levels
- Allow jumping between distant parts of the HFSM

## Decision Logic

### Basic Decisions
- Predefined decisions include `TrueDecision`, `FalseDecision`, etc.
- Custom decisions can be created by inheriting from `HFSMDecision`

### Composed Decisions
- Logic operators (AND, OR, NOT) to create complex conditions
- Chain decisions together for more sophisticated branching

## Events

- Named triggers that can cause transitions when fired
- Can be triggered from anywhere in the code
- Useful for responding to external game events
- Can be combined with decision conditions

## HFSM Implementation

### Creating an HFSM Document
1. Open the Bot SDK editor
2. Create a new HFSM document
3. Define states and transitions visually
4. Compile to generate Quantum assets

### Coding HFSM Components
```csharp
// Custom HFSM Decision
[System.Serializable]
public unsafe class CustomDecision : HFSMDecision
{
    public override unsafe bool Decide(Frame frame, EntityRef entity)
    {
        // Custom decision logic here
        return true;
    }
}

// Custom HFSM Action
[System.Serializable]
public unsafe class CustomAction : AIAction
{
    public override void Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Custom action logic here
    }
}
```

### Initializing and Updating HFSM
```csharp
// Initialize HFSM
var hfsmRootAsset = frame.FindAsset<HFSMRoot>(hfsmRoot.Id);
HFSMManager.Init(frame, entityRef, hfsmRootAsset);

// Update HFSM
HFSMManager.Update(frame, frame.DeltaTime, entityRef);
```

## Debugging HFSM

The Bot SDK includes a visual debugger for HFSMs that:
- Highlights current states and recent transitions
- Shows the hierarchy of states
- Requires enabling the `BotSDKDebuggerSystem`
- Can be activated during gameplay

## Pros and Cons

### Pros
- **Performance**: Efficient for large numbers of agents
- **Memory Usage**: Low memory footprint per agent
- **Ease of Understanding**: Clear state transitions
- **Tight Control**: Precise definition of behavior

### Cons
- **Maintenance**: Complex HFSMs can be difficult to maintain
- **Spaghetti States**: Can become tangled with many transitions
- **Flexibility**: Less dynamic than some other AI approaches

## Best Practices

1. Use hierarchy effectively to organize related states
2. Keep state actions focused on specific behaviors
3. Use comments and naming to clarify the HFSM structure
4. Test transitions thoroughly, especially complex compositions
5. Consider using events for external communication
6. Use the debugger to visualize and validate behavior
7. Leverage transition priorities to ensure correct evaluation order
