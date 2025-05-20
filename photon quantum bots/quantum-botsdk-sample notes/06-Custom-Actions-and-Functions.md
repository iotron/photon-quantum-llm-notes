# Creating Custom AI Actions and Functions

This document provides a detailed guide on creating custom AI actions and functions for the Photon Quantum Bot SDK.

## Overview

The Bot SDK provides extensible mechanisms for creating custom AI behaviors through:

1. **AI Actions** - Executable behaviors that can modify the game state
2. **AI Functions** - Methods that compute and return values for decision making

These components are used across all three AI paradigms (BT, HFSM, UT) and allow developers to extend the AI system with game-specific logic.

## AI Actions

### Core Concept

`AIAction` is the base class for all executable behaviors in the Bot SDK. Actions perform game-specific logic and can modify the state of entities.

### Base Class Definition

```csharp
[Serializable]
public abstract class AIAction : AssetObject
{
    // Execute the action
    public abstract void Execute(Frame frame, EntityRef entity, ref AIContext aiContext);
}
```

### Creating a Custom Action

To create a custom action:

1. Create a new class that inherits from `AIAction`
2. Implement the `Execute` method
3. Add any configuration parameters as public fields

Example of a custom movement action:

```csharp
[Serializable]
public unsafe class MoveToPositionAction : AIAction
{
    // Configuration parameters
    public AIParam<FPVector2> TargetPosition;
    public FP Speed = 5;
    
    public override void Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get required components
        var transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        var physicsBehavior = frame.Unsafe.GetPointer<PhysicsBehavior>(entity);
        
        // Get target position (could be from param or blackboard)
        FPVector2 targetPos;
        if (TargetPosition != null)
        {
            targetPos = TargetPosition.GetValue(frame, entity, ref aiContext);
        }
        else
        {
            // Get from blackboard as fallback
            var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            var boardAsset = frame.FindAsset<AIBlackboard>(blackboard->Board.Id);
            int targetPosId = boardAsset.GetKeyId("TargetPosition");
            targetPos = blackboard->GetVector2(frame, targetPosId);
        }
        
        // Calculate direction to target
        FPVector2 direction = targetPos - transform->Position;
        FP distance = direction.Magnitude;
        
        // If close enough, stop
        if (distance < FP._0_10)
        {
            physicsBehavior->LinearVelocity = FPVector2.Zero;
            return;
        }
        
        // Normalize direction and apply speed
        direction = direction.Normalized;
        physicsBehavior->LinearVelocity = direction * Speed;
    }
}
```

### Using Actions in Different AI Systems

Actions can be used in all three AI paradigms:

#### In Behavior Trees

```csharp
public class MoveToTargetNode : BTLeaf
{
    // Instance of our custom action
    public MoveToPositionAction MoveAction = new MoveToPositionAction();
    
    protected override BTStatus OnUpdate(BTParams p, ref AIContext aiContext)
    {
        // Execute the action
        MoveAction.Execute(p.Frame, p.Entity, ref aiContext);
        
        // This is a continuous action, so return Running
        return BTStatus.Running;
    }
}
```

#### In HFSM

```csharp
// Define a state that uses the action
public class MoveToTargetState : HFSMState
{
    public MoveToTargetState()
    {
        StateName = "Move To Target";
        
        // Add the action to the state's action list
        StateActions.Add(new MoveToPositionAction
        {
            Speed = 5
        });
    }
}
```

#### In Utility Theory

```csharp
// Define a UT action that uses our custom action
public class MoveToTargetUTAction : UTAction
{
    public MoveToTargetUTAction()
    {
        ActionName = "Move To Target";
        
        // Set the action to execute
        Action = new MoveToPositionAction
        {
            Speed = 5
        };
        
        // Add considerations
        Considerations.Add(new UTConsideration
        {
            InputFunction = new DistanceToTargetFunction(),
            ResponseCurve = new LinearDecreasingCurve(),
            Weight = FP._1
        });
    }
}
```

## AI Functions

### Core Concept

`AIFunction<T>` is the base class for functions that compute and return values of a specific type. Functions are used for decision making and parameter retrieval.

### Base Class Definition

```csharp
[Serializable]
public abstract class AIFunction<T> : AssetObject
{
    // Execute the function and return a value
    public abstract T Execute(Frame frame, EntityRef entity, ref AIContext aiContext);
}
```

Common specializations include:
- `AIFunction<bool>` - Returns a boolean value
- `AIFunction<FP>` - Returns a fixed-point number
- `AIFunction<FPVector2>` - Returns a 2D vector
- `AIFunction<FPVector3>` - Returns a 3D vector
- `AIFunction<EntityRef>` - Returns an entity reference

### Creating a Custom Function

To create a custom function:

1. Create a new class that inherits from `AIFunction<T>` with the appropriate type
2. Implement the `Execute` method to compute and return the value
3. Add any configuration parameters as public fields

Example of a custom distance function:

```csharp
[Serializable]
public unsafe class DistanceToEntityFunction : AIFunction<FP>
{
    // Configuration parameters
    public AIParam<EntityRef> TargetEntity;
    
    public override FP Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get source position
        var sourceTransform = frame.Unsafe.GetPointer<Transform2D>(entity);
        FPVector2 sourcePosition = sourceTransform->Position;
        
        // Get target entity
        EntityRef targetEntity;
        if (TargetEntity != null)
        {
            targetEntity = TargetEntity.GetValue(frame, entity, ref aiContext);
        }
        else
        {
            // Get from blackboard as fallback
            var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            var boardAsset = frame.FindAsset<AIBlackboard>(blackboard->Board.Id);
            int targetEntityId = boardAsset.GetKeyId("TargetEntity");
            targetEntity = blackboard->GetEntity(frame, targetEntityId);
        }
        
        // If target is invalid, return max distance
        if (targetEntity == default)
            return FP.UseableMax;
        
        // Get target position
        var targetTransform = frame.Get<Transform2D>(targetEntity);
        FPVector2 targetPosition = targetTransform.Position;
        
        // Calculate and return distance
        return FPVector2.Distance(sourcePosition, targetPosition);
    }
}
```

Example of a boolean function:

```csharp
[Serializable]
public unsafe class IsEntityInRangeFunction : AIFunction<bool>
{
    // Configuration parameters
    public AIParam<EntityRef> TargetEntity;
    public FP Range = 5;
    
    public override bool Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get the distance
        var distanceFunction = new DistanceToEntityFunction
        {
            TargetEntity = TargetEntity
        };
        
        FP distance = distanceFunction.Execute(frame, entity, ref aiContext);
        
        // Return true if within range
        return distance <= Range;
    }
}
```

### Using Functions in Different AI Systems

Functions can be used in all three AI paradigms:

#### In Behavior Trees

```csharp
public class IsTargetInRangeNode : BTDecorator
{
    // Instance of our custom function
    public IsEntityInRangeFunction RangeCheckFunction = new IsEntityInRangeFunction
    {
        Range = 5
    };
    
    protected override BTStatus OnUpdate(BTParams p, ref AIContext aiContext)
    {
        // Check if target is in range
        bool inRange = RangeCheckFunction.Execute(p.Frame, p.Entity, ref aiContext);
        
        if (inRange)
        {
            // Run child if in range
            return Children[0].OnUpdate(p, ref aiContext);
        }
        else
        {
            // Fail if not in range
            return BTStatus.Failure;
        }
    }
}
```

#### In HFSM

```csharp
public class TargetInRangeDecision : HFSMDecision
{
    // Instance of our custom function
    public IsEntityInRangeFunction RangeCheckFunction = new IsEntityInRangeFunction
    {
        Range = 5
    };
    
    public override bool Decide(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Return the result of the function
        return RangeCheckFunction.Execute(frame, entity, ref aiContext);
    }
}
```

#### In Utility Theory

```csharp
// Use function as input to a consideration
public class DistanceConsideration : UTConsideration
{
    public DistanceConsideration()
    {
        // Use our distance function
        InputFunction = new DistanceToEntityFunction();
        
        // Use a linear decreasing curve (closer is better)
        ResponseCurve = new LinearDecreasingCurve();
        
        // Set weight
        Weight = FP._1;
    }
    
    public override FP CalculateUtility(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get raw distance
        FP distance = InputFunction.Execute(frame, entity, ref aiContext);
        
        // Normalize to 0-1 range (assuming max distance of 50)
        FP normalizedInput = FPMath.Clamp01(distance / 50);
        
        // Map through response curve
        return ResponseCurve.Evaluate(normalizedInput);
    }
}
```

## AI Parameters (AIParam)

### Core Concept

`AIParam<T>` is a wrapper that can hold either a static value or a function that computes a value. This allows for flexible configuration of actions and functions.

### Base Class Definition

```csharp
[Serializable]
public class AIParam<T>
{
    // Static value
    public T Value;
    
    // Function to compute value
    public AIFunction<T> Function;
    
    // Check if using function
    public bool UseFunction;
    
    // Get the value (static or computed)
    public T GetValue(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        if (UseFunction && Function != null)
            return Function.Execute(frame, entity, ref aiContext);
        else
            return Value;
    }
}
```

### Using AIParam

AIParam allows actions and functions to accept either static values or dynamic values from functions:

```csharp
[Serializable]
public unsafe class MoveToPositionAction : AIAction
{
    // Use AIParam to accept either a static position or a function
    public AIParam<FPVector2> TargetPosition = new AIParam<FPVector2>();
    
    public override void Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get the value (either static or computed)
        FPVector2 targetPos = TargetPosition.GetValue(frame, entity, ref aiContext);
        
        // Use the value
        // ...
    }
}
```

This allows for flexible configuration in the editor:

```csharp
// Configure with static value
var moveAction = new MoveToPositionAction
{
    TargetPosition = new AIParam<FPVector2>
    {
        UseFunction = false,
        Value = new FPVector2(10, 20)
    }
};

// Configure with function
var moveAction = new MoveToPositionAction
{
    TargetPosition = new AIParam<FPVector2>
    {
        UseFunction = true,
        Function = new GetEnemyPositionFunction()
    }
};
```

## Best Practices

### For Actions

1. **Keep actions focused** - Each action should do one thing well
2. **Use AIParam for flexibility** - Accept both static and dynamic values
3. **Handle edge cases** - Check for null references and invalid entities
4. **Optimize performance** - Keep actions lightweight for real-time execution
5. **Use the AIContext** - Store temporary data in the context to avoid allocations

### For Functions

1. **Return normalized values** - For utility functions, return values in the 0-1 range
2. **Cache computations** - Avoid redundant calculations
3. **Handle invalid inputs** - Return sensible defaults for edge cases
4. **Compose functions** - Build complex functions by combining simpler ones
5. **Document parameters** - Clearly document what each parameter does

### General Tips

1. **Test with different scenarios** - Ensure functions and actions work in all cases
2. **Use the debugger** - Visualize function outputs and action effects
3. **Deterministic code** - Ensure all random decisions use Quantum's deterministic random
4. **Reuse code** - Create utility functions for common operations
5. **Safety checks** - Validate input data before using it
