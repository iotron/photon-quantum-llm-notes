# Behavior Trees (BT)

## Introduction

Behavior Trees (BT) are a popular AI technique in game development, implemented in the Quantum Bot SDK as a hierarchical structure of nodes. The execution flows from the root node through the tree based on the status of each node. The Bot SDK's implementation is stateful and event-driven, making it efficient and responsive.

## Core Concepts

### Node Status
Every node in a BT has a status that determines the flow of execution:
- **Success**: Node completed its task successfully
- **Failure**: Node failed to complete its task
- **Running**: Node needs more time to complete its task
- **Inactive**: Node hasn't been visited in the current execution (internal use)

### Node Types

#### Root Node
- Starting point of the tree
- Can only have one child node
- Used to create the main asset for the BTAgent component

#### Composite Nodes
- Control flow of the tree by managing multiple child nodes
- Execute children from left to right (priority order)
- Types include:
  - **Selector**: Returns Success if ANY child succeeds (OR logic)
  - **Sequence**: Returns Success if ALL children succeed (AND logic)
  - **Selector Random**: Randomly picks a child node with even distribution

#### Decorator Nodes
- Condition nodes that can block or allow execution of subtrees
- Return Success or Failure based on condition evaluation
- Attached to Composite or Leaf nodes
- Examples: HasAmmo, IsTargetVisible, Cooldown

#### Leaf Nodes
- Bottom-level nodes that perform actual game actions
- Examples: Chase, Attack, Wait, Reload
- Primary nodes for changing game state

#### Service Nodes
- Helper nodes for periodic tasks
- Don't affect tree flow directly
- Execute at intervals defined by `Interval In Sec`
- Can execute on subtree entry with `Run On Enter`

## Interruption Mechanisms

### Dynamic Composite Nodes
- Re-check decorators every frame while part of the current subtree
- Interrupt running leaves if decorators fail
- Defined by toggling the `IsDynamic` field

### Reactive Decorators
- "Watch" for changes in Blackboard entries
- React when values change without constant checking
- Support different abort types:
  - **Self**: Stop current node and resume from interrupting node
  - **Lower Priority**: Continue current node but skip siblings
  - **Both**: Apply both logics

## Implementation Details

### Creating a Behavior Tree
1. Open Bot SDK editor window
2. Create a new Behavior Tree document
3. Add and connect nodes visually
4. Define node parameters and conditions
5. Compile to generate Quantum assets

### Coding BT Components

```csharp
// Custom Decorator
[System.Serializable]
public unsafe class CustomDecorator : BTDecorator
{
    public override bool CheckConditions(BTParams p)
    {
        // Custom condition logic
        return true;
    }
}

// Custom Leaf Node
[System.Serializable]
public unsafe class CustomLeaf : BTLeaf
{
    public override BTStatus OnUpdate(BTParams p)
    {
        // Custom action logic
        return BTStatus.Success;
    }
}

// Custom Service
[System.Serializable]
public unsafe class CustomService : BTService
{
    public override void OnUpdate(BTParams p)
    {
        // Custom service logic
    }
}
```

### BTAgent Lifecycle

```csharp
// Initialize BTAgent
var btRootAsset = frame.FindAsset<BTRoot>(btRoot.Id);
BTManager.Init(frame, entity, btRootAsset);

// Update BTAgent
BTManager.Update(frame, entity);
```

### Node Data Storage
- Use `BTDataIndex` for node-specific data
- Allocate in the `Init` method:
  ```csharp
  btAgent->AddFPData(frame, initialValue);
  ```
- Access with:
  ```csharp
  p.BtAgent->GetFPData(frame, dataIndex.Index);
  ```

## Debugging Behavior Trees

The Bot SDK provides a visual debugger for Behavior Trees that:
- Highlights the current execution path
- Color-codes nodes by status (blue=running, green=success, red=failure)
- Shows progress of services
- Requires enabling the `BotSDKDebuggerSystem`
- Can be activated during gameplay

## Pros and Cons

### Pros
- **Performance**: Stateful design for optimal execution
- **Responsiveness**: Event-driven for quick reactions
- **Readability**: Clear visualization of decision flows
- **Control**: Precise definition of behavior priorities

### Cons
- **Memory Usage**: Higher per-agent memory compared to HFSM
- **Setup Complexity**: Requires careful planning of tree structure
- **Scalability**: Less efficient for very large numbers of agents

## Best Practices

1. Organize nodes with priority (left to right) in mind
2. Use service nodes for periodic tasks to optimize performance
3. Balance between dynamic checking and reactive approach
4. Leverage interruption mechanisms for responsive behavior
5. Use the debugger to visualize and validate behavior
6. Consider the memory cost when using many BT agents
7. Reuse subtrees where appropriate for consistent behavior
