# Utility Theory (UT)

## Introduction

Utility Theory in the Quantum Bot SDK provides a mathematical approach to AI decision-making. Rather than using explicit states or hierarchical decisions, UT evaluates the "utility" (usefulness) of various actions using mathematical curves and scoring. This creates more dynamic, responsive AI that can adapt to changing game conditions in less predictable ways.

## Core Concepts

### Considerations
- Main building blocks of Utility Theory
- Represent potential actions or behaviors
- Contain Response Curves that determine utility scores
- Include Actions to execute when chosen
- Can be linked hierarchically

### Response Curves
- Mathematical functions that map inputs to utility scores
- Created using Unity's AnimationCurve editor
- Output normalized values (0-1) that get multiplied together
- Can create complex decision surfaces when combined

### Actions
- Define what happens when a Consideration is chosen
- Split into three categories:
  - **On Enter**: When a Consideration begins execution
  - **On Update**: While a Consideration continues to be chosen
  - **On Exit**: When a different Consideration becomes more useful

### Ranking
- Provides absolute priority between Considerations
- Considerations with higher Rank are evaluated first
- Lower-ranked Considerations are ignored if higher ones exist
- Useful for performance and logical organization

### Momentum
- Mechanism to reduce "jittery" decision-making
- Increases the Rank of a chosen Consideration temporarily
- Can decay over time using `Momentum Decay`
- Can be canceled by specific conditions using Commitment

## Implementation Details

### Creating a Utility Theory Document
1. Open Bot SDK editor window
2. Create a new Utility Theory document
3. Define Considerations with Response Curves
4. Set up Actions, Ranking, and Momentum
5. Compile to generate Quantum assets

### Nested Considerations
- Create hierarchy by linking Considerations
- Child Considerations only evaluated when parent is chosen
- Reduces computation by only evaluating relevant subtrees
- Helps organize Considerations into logical groups

### Response Curve Examples
- **Linear**: Utility increases proportionally with input
- **Exponential**: Utility increases/decreases exponentially
- **Threshold**: Binary utility (0 or 1) at specific input value
- **Bell Curve**: Highest utility at specific value, lower elsewhere

### Coding UT Components

#### Custom Input Functions
```csharp
[System.Serializable]
public unsafe class CustomUtilityInput : AIFunction<FP>
{
    public override FP Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Calculate and return a value between 0-1
        // This value will be used as input for a Response Curve
        return FP._0_50;
    }
}
```

#### Agent Initialization
```csharp
// Initialize UTAgent
UTManager.Init(frame, &utAgent->UtilityReasoner, utRoot, entity);

// Update UTAgent
UTManager.Update(frame, &utAgent->UtilityReasoner, entity);
```

## Advanced Features

### Commitment
- Mechanism to cancel Momentum based on conditions
- Created by inheriting from `AIFunctionBool`
- Returns true when Momentum should be canceled
- Useful for stopping persistent behaviors when conditions change

### Base Score
- Fixed utility value added to Response Curves result
- Provides minimum utility for a Consideration
- Useful for ensuring some behaviors have baseline preference

### Cooldown
- Time-based restriction on re-selecting a Consideration
- Prevents rapid switching between behaviors
- Can be configured to cancel Momentum or wait for it to end

## Pros and Cons

### Pros
- **Immersive Behavior**: More natural, less predictable decision-making
- **Smooth Transitions**: Gradual changes between behaviors
- **Adaptability**: Responds dynamically to changing game conditions
- **Mathematical Control**: Fine-tune behavior with curve adjustments

### Cons
- **Sequence Difficulty**: Harder to define strict action sequences
- **Predictability**: Less direct control over exact behavior
- **Tuning Complexity**: Many variables to balance for optimal behavior
- **Learning Curve**: More abstract concept compared to state machines

## Best Practices

1. Normalize Response Curve outputs (0-1) for proper multiplication
2. Use Ranking effectively to create priority groups
3. Balance Momentum and Cooldown to prevent behavior thrashing
4. Organize Considerations in logical hierarchies
5. Design curves carefully to express desired decision surfaces
6. Start with simple utility functions and iterate
7. Consider performance impact of too many complex Response Curves
8. Use good naming conventions for clarity
