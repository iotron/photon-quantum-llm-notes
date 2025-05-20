# Utility Theory (UT) Implementation

This document details the implementation of Utility Theory in the Photon Quantum Bot SDK.

## Core Components

### UTAgent

The `UTAgent` is a component attached to entities that use Utility Theory:

```csharp
public unsafe partial struct UTAgent : IComponent
{
    // Runtime data for the UT system
    public UTReasoner UtilityReasoner;
}
```

### UTReasoner

`UTReasoner` is the core utility reasoning system:

```csharp
public struct UTReasoner
{
    // Reference to the utility theory definition
    public AssetRef<UTRoot> UTRoot;
    
    // Currently selected action
    public AssetRef<UTAction> CurrentAction;
    
    // Runtime data for utility calculations
    public UTReasonerData Data;
    
    // Initialize the reasoner
    public void Init(Frame frame, AssetRef<UTRoot> root, EntityRef entity);
    
    // Update utility scores and select action
    public void Update(Frame frame, EntityRef entity);
    
    // Execute the selected action
    public void ExecuteSelectedAction(Frame frame, EntityRef entity);
}
```

### UTRoot

`UTRoot` is an asset that defines the utility theory structure:

```csharp
public class UTRoot : AssetObject
{
    // List of available actions to choose from
    public List<UTAction> Actions;
    
    // How frequently to re-evaluate (in frames)
    public int ReevaluationFrequency;
    
    // Minimum score change to force re-selection
    public FP MinScoreChangeThreshold;
}
```

### UTAction

Each `UTAction` represents a possible action with utility considerations:

```csharp
public class UTAction : AssetObject
{
    // Name for debugging
    public string ActionName;
    
    // Utility considerations that determine score
    public List<UTConsideration> Considerations;
    
    // Action to execute when selected
    public AIAction Action;
    
    // Calculate total utility score based on considerations
    public FP CalculateUtilityScore(Frame frame, EntityRef entity);
    
    // Execute the action
    public void Execute(Frame frame, EntityRef entity);
}
```

### UTConsideration

`UTConsideration` evaluates a specific aspect of utility:

```csharp
public class UTConsideration
{
    // Function that provides input value
    public AIFunction<FP> InputFunction;
    
    // Response curve that maps input to utility score
    public UTResponseCurve ResponseCurve;
    
    // Weight of this consideration (0-1)
    public FP Weight;
    
    // Calculate normalized utility score
    public FP CalculateUtility(Frame frame, EntityRef entity);
}
```

### UTResponseCurve

`UTResponseCurve` defines how input values map to utility scores:

```csharp
public abstract class UTResponseCurve
{
    // Maps a normalized input (0-1) to a utility value (0-1)
    public abstract FP Evaluate(FP x);
}
```

Common response curves include:
- Linear
- Exponential
- Logistic
- Logarithmic
- Sine

## Execution Flow

### Initialization

The `UTManager` handles the initialization of UT agents:

```csharp
public static void Init(Frame frame, UTReasoner* reasoner, AssetRef<UTRoot> root, EntityRef entity)
{
    reasoner->UTRoot = root;
    reasoner->Data.LastEvaluationFrame = -1;
    reasoner->Data.ActionScores = new FP[root.Actions.Count];
    
    // Calculate initial scores and select action
    Update(frame, entity, reasoner);
}
```

### Update

The UT system updates and selects actions based on utility scores:

```csharp
public static void Update(Frame frame, EntityRef entity, UTReasoner* reasoner)
{
    var root = frame.FindAsset<UTRoot>(reasoner->UTRoot.Id);
    
    // Check if reevaluation is needed
    if (ShouldReevaluate(frame, reasoner))
    {
        // Calculate scores for all actions
        for (int i = 0; i < root.Actions.Count; i++)
        {
            var action = root.Actions[i];
            reasoner->Data.ActionScores[i] = action.CalculateUtilityScore(frame, entity);
        }
        
        // Find action with highest score
        int bestActionIndex = -1;
        FP bestScore = FP._0;
        
        for (int i = 0; i < reasoner->Data.ActionScores.Length; i++)
        {
            if (reasoner->Data.ActionScores[i] > bestScore)
            {
                bestScore = reasoner->Data.ActionScores[i];
                bestActionIndex = i;
            }
        }
        
        // Update selected action
        if (bestActionIndex >= 0)
        {
            reasoner->CurrentAction = new AssetRef<UTAction>(root.Actions[bestActionIndex]);
        }
        
        reasoner->Data.LastEvaluationFrame = frame.Number;
    }
}
```

### Action Execution

When an action is selected, it is executed through the AIAction system:

```csharp
public static void ExecuteSelectedAction(Frame frame, EntityRef entity, UTReasoner* reasoner)
{
    if (reasoner->CurrentAction == default)
        return;
        
    var action = frame.FindAsset<UTAction>(reasoner->CurrentAction.Id);
    var aiContext = new AIContext();
    
    action.Action.Execute(frame, entity, ref aiContext);
}
```

## Utility Score Calculation

The `CalculateUtilityScore` method in `UTAction` combines scores from multiple considerations:

```csharp
public FP CalculateUtilityScore(Frame frame, EntityRef entity)
{
    if (Considerations.Count == 0)
        return FP._1;
        
    FP score = FP._1;
    
    foreach (var consideration in Considerations)
    {
        FP considerationScore = consideration.CalculateUtility(frame, entity);
        score *= considerationScore;
    }
    
    // Apply compensation factor - prevents one low score from dominating
    FP compensation = FP._1 - (FP._1 / Considerations.Count);
    FP compensatedScore = score + (FP._1 - score) * compensation;
    
    return compensatedScore;
}
```

## Example Implementation

An example UT consideration function:

```csharp
public class DistanceToTargetFunction : AIFunction<FP>
{
    public override FP Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        var transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        var collector = frame.Unsafe.GetPointer<Collector>(entity);
        
        if (collector->TargetPosition == null)
            return FP._0;
            
        FP distance = FPVector2.Distance(transform->Position, collector->TargetPosition.Value);
        
        // Normalize to 0-1 range (assuming max distance of 50)
        return FPMath.Clamp01(distance / 50);
    }
}
```

An example response curve:

```csharp
public class LinearDecreasingCurve : UTResponseCurve
{
    public override FP Evaluate(FP x)
    {
        // Return 1-x (closer is better)
        return FP._1 - x;
    }
}
```

## Creating Custom UT Components

### Custom Input Functions

To create a custom input function:

```csharp
[Serializable]
public class MyCustomInputFunction : AIFunction<FP>
{
    // Optional parameters
    public FP Threshold;
    
    public override FP Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Calculate and return normalized value between 0-1
        return normalizedValue;
    }
}
```

### Custom Response Curves

To create a custom response curve:

```csharp
[Serializable]
public class MyCustomResponseCurve : UTResponseCurve
{
    // Optional parameters
    public FP Exponent;
    
    public override FP Evaluate(FP x)
    {
        // Map input x (0-1) to output (0-1)
        return mappedValue;
    }
}
```

## Best Practices

1. **Design considerations carefully** - Each consideration should measure one aspect of utility
2. **Normalize inputs properly** - Input functions should return values in the 0-1 range
3. **Choose appropriate response curves** - Different curves produce different behaviors
4. **Use compensation factor** - It prevents one low score from dominating
5. **Tune reevaluation frequency** - Balance responsiveness and performance
6. **Understand weighting** - Weights affect how considerations combine
7. **Test different configurations** - Utility systems often need experimentation
8. **Visualize utility scores** - Use the debugger to see how scores change over time
