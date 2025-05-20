# Behavior Tree Implementation in Quantum Bot SDK

This document details the implementation of Behavior Trees (BT) in the Photon Quantum Bot SDK.

## Core Components

### BTAgent

The `BTAgent` is a component attached to entities that run behavior trees:

```csharp
public unsafe partial struct BTAgent : IComponent
{
    // References the BT definition asset
    public AssetRef<BTRoot> Tree;
    
    // Runtime data for the BT execution
    public BTAgentData Data;
}
```

### BTRoot

A `BTRoot` is an asset that defines the structure of a behavior tree:

```csharp
public class BTRoot : AssetObject
{
    // Root node of the behavior tree
    public BTNode RootNode;
    
    // Global blackboard variables
    public List<BTVariable> GlobalVariables;
}
```

### BTNode

`BTNode` is the base class for all behavior tree nodes:

```csharp
public abstract class BTNode
{
    public string Name;
    public BTNode[] Children;
    
    // Execute this node
    public abstract BTStatus OnUpdate(BTParams p, ref AIContext aiContext);
}
```

### Node Types

The BT system implements standard node types:

1. **Composite Nodes** - Have multiple children
   - `BTSequence` - Executes children in order until one fails
   - `BTSelector` - Executes children in order until one succeeds
   - `BTParallel` - Executes all children simultaneously
   - `BTSelectorRandom` - Randomly selects a child to execute

2. **Decorator Nodes** - Have a single child and modify its behavior
   - `BTInverter` - Inverts the child's result
   - `BTRepeater` - Repeats the child a specified number of times
   - `BTReturnSuccess` - Always returns success
   - `BTReturnFailure` - Always returns failure

3. **Leaf Nodes** - Perform actual actions
   - Custom leaf nodes implement game-specific behaviors
   - `FindCollectible`, `PickupCollectible`, etc. in the sample

## Execution Flow

### Initialization

The `BotSDKSystem` handles the initialization of BT agents:

```csharp
public void OnAdded(Frame frame, EntityRef entity, BTAgent* component)
{
  if (component->Tree != default)
  {
    var btRoot = frame.FindAsset<BTRoot>(component->Tree.Id);
    BTManager.Init(frame, entity, btRoot);
  }
}
```

### Update

The `BTManager` static class manages BT execution. The main update flow is:

```csharp
public static unsafe BTStatus Tick(Frame f, EntityRef entity)
{
    var agent = f.Unsafe.GetPointer<BTAgent>(entity);
    var rootNode = f.FindAsset<BTRoot>(agent->Tree.Id).RootNode;
    
    var p = new BTParams(f, entity);
    var aiContext = new AIContext();
    
    return rootNode.OnUpdate(p, ref aiContext);
}
```

### Node Execution

Each node's `OnUpdate` method returns a `BTStatus`:
- `BTStatus.Success` - Node succeeded
- `BTStatus.Failure` - Node failed
- `BTStatus.Running` - Node is still executing

## Example Implementation

From the Collectors Sample, here's an example leaf node:

```csharp
public unsafe partial class FindCollectible : BTLeaf
{
  protected override BTStatus OnUpdate(BTParams p, ref AIContext aiContext)
  {
    var f = p.Frame;
    var e = p.Entity;

    var collectibles = f.GetComponentIterator<Collectible>();
    var guyTransform = f.Unsafe.GetPointer<Transform2D>(e);

    EntityRef closestCollectible = default;
    FP min = FP.UseableMax;
    
    foreach (var (entity, collectible) in collectibles)
    {
      var collTransform = f.Get<Transform2D>(entity);
      var distance = FPVector2.Distance(guyTransform->Position, collTransform.Position);

      if (closestCollectible == default || distance < min)
      {
        closestCollectible = entity;
        min = distance;
      }
    }

    if (closestCollectible != default)
    {
      f.Unsafe.GetPointer<Collector>(e)->DesiredCollectible = closestCollectible;
      return BTStatus.Success;
    }
    else
    {
      return BTStatus.Failure;
    }
  }
}
```

## Creating Custom Nodes

To create a custom BT node:

1. Create a class that inherits from the appropriate node type:
   - `BTComposite` for composite nodes
   - `BTDecorator` for decorator nodes
   - `BTLeaf` for leaf nodes

2. Implement the `OnUpdate` method to define the node's behavior

3. Return the appropriate status:
   - `BTStatus.Success` when the node has completed successfully
   - `BTStatus.Failure` when the node has failed
   - `BTStatus.Running` when the node is still executing

## Best Practices

1. **Keep nodes focused** - Each node should do one thing well
2. **Use blackboard for shared data** - Store shared data in the blackboard to avoid coupling
3. **Manage complexity** - Use sub-trees for complex behaviors
4. **Use decorators** - Decorators can modify node behavior without changing the node itself
5. **Optimize performance** - Keep node execution lightweight for real-time performance
6. **Consider determinism** - Ensure random decisions use Quantum's deterministic random
