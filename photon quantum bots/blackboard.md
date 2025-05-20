# Blackboard System

## Introduction

The Blackboard system in Quantum Bot SDK provides a flexible data storage mechanism that AI agents can read from and write to. It serves as a central repository for information sharing between different AI components and systems. The Blackboard is particularly useful for storing dynamic data that changes during gameplay and needs to be accessible across multiple parts of the AI system.

## Key Components

### 1. AIBlackboardComponent
- Quantum component that can be added to entities
- Contains the runtime storage for dynamic data
- Each entity has its own instance with independent data

### 2. AIBlackboard Asset
- Unity asset created during compilation
- Defines the data layout (types and keys)
- Reusable across multiple entities

### 3. AIBlackboardInitializer
- Unity asset created during compilation
- Stores initial values for Blackboard entries
- Optional but useful for setting default values

## Supported Data Types

The Blackboard supports these data types:
1. Boolean
2. Byte
3. Integer
4. FP (fixed-point number)
5. FPVector2
6. FPVector3
7. EntityRef
8. AssetRef

## Using the Blackboard

### In the Visual Editor

1. Access the Blackboard Variables panel in the left sidebar
2. Create new variables using the + button
3. Define properties for each variable:
   - Name (used to generate the access key)
   - Type (from supported types)
   - Has Initial Value flag
   - Initial Value (if applicable)
4. Drag-and-drop variables into the graph as Blackboard Nodes
5. Use the Key slot to connect to AIBlackboardValueKey fields
6. Use the Value slot to connect to fields of matching type

### In Quantum Code

#### Initializing the Blackboard
```csharp
// Create the blackboard component
var blackboardComponent = new AIBlackboardComponent();

// Find the Blackboard Initializer asset
var bbInitializerAsset = frame.FindAsset<AIBlackboardInitializer>(blackboardAsset.BlackboardInitializer.Id);

// Initialize with values from the asset
AIBlackboardInitializer.InitializeBlackboard(frame, &blackboardComponent, bbInitializerAsset);

// Add to entity
frame.Set(entity, blackboardComponent);
```

#### Reading and Writing Data
```csharp
// Read values (typed getters)
int value = blackboardComponent->GetInteger(frame, "CounterKey");
FP health = blackboardComponent->GetFP(frame, "HealthKey");
EntityRef target = blackboardComponent->GetEntityRef(frame, "TargetKey");

// Write values (generic setter)
blackboardComponent->Set(frame, "CounterKey", 42);
blackboardComponent->Set(frame, "HealthKey", FP._0_75);
blackboardComponent->Set(frame, "TargetKey", targetEntity);

// Using keys from Blackboard nodes
public AIBlackboardValueKey HealthKey;
FP health = blackboardComponent->GetFP(frame, HealthKey.Key);
```

#### Memory Management
```csharp
// When destroying an entity, free memory to avoid leaks
blackboardComponent->Free(frame);
```

## Blackboard and Reactive Systems

### In Behavior Trees
- Reactive Decorators can "watch" Blackboard entries
- Trigger evaluation when values change
- Create responsive behavior without constant checking

```csharp
// Register a Decorator to watch a Blackboard entry
p.Blackboard->RegisterReactiveDecorator(p.Frame, BlackboardKey.Key, this);

// Trigger Decorators when updating a value
blackboard->Set(frame, "VariableKey", value)->TriggerDecorators(p);
```

### In Utility Theory
- Response Curves can take Blackboard values as input
- Changes in Blackboard values affect utility calculations
- Create dynamic decision-making based on current data

## Advantages of Blackboard

1. **Central data repository** for all AI components
2. **Type safety** with specialized getters
3. **Visual Editor integration** for easy setup
4. **Initial value support** for consistent startup
5. **Reactive capability** for event-driven behavior

## Limitations and Considerations

1. **Memory usage**: All entries use the size of the largest type (8 bytes)
2. **Performance**: Dictionary lookups have some overhead
3. **Best for dynamic data**: Static data might be better in assets

## Best Practices

1. Use the Blackboard for data that changes during gameplay
2. Keep keys consistent across systems
3. Use AIBlackboardValueKey fields for type safety
4. Free memory when destroying entities
5. Consider reactivity for event-driven behavior
6. Use meaningful names for Blackboard entries
7. Group related variables with naming conventions
