# Prediction and Rollback

Quantum uses prediction and rollback to provide a responsive gameplay experience even in the presence of network latency. This document explains how the prediction and rollback system works in Quantum and how to optimize it for your game.

## Core Prediction Concepts

### How Prediction Works

1. **Local Prediction**: Clients predict game state based on local inputs
2. **Input Collection**: Local inputs are sent to the server
3. **Authoritative Confirmation**: The server collects inputs from all clients and distributes them
4. **Verification**: Clients verify if their predictions match the authoritative state
5. **Rollback**: If predictions don't match, clients roll back and resimulate

### Prediction Buffer

Quantum maintains a buffer of frames for prediction:

- **Verified Frame**: The last frame with confirmed inputs from all players
- **Predicted Frames**: Frames simulated beyond the verified frame using predicted inputs
- **Prediction Buffer Size**: Typically ranges from 2-10 frames depending on network conditions

## Frame Types in Quantum

Quantum maintains several frame types in its simulation:

```
QuantumGame.Frames.Verified       // Last confirmed frame from the server
QuantumGame.Frames.Predicted      // Latest predicted frame (for rendering)
QuantumGame.Frames.RollbackStart  // Frame to start rollback from if needed
```

## Implementing Prediction-Friendly Code

### Deterministic Code

All simulation code must be deterministic:

```csharp
public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>
{
    public override void Update(Frame frame, ref Filter filter)
    {
        // Use Quantum's fixed-point math for determinism
        var direction = new FPVector2(input->MoveDirection.X, input->MoveDirection.Y);
        
        // Don't use Unity's non-deterministic math
        // BAD: var direction = new Vector2(input.moveX, input.moveY).normalized;
        
        // Don't use random without using frame.RNG
        // BAD: var random = UnityEngine.Random.value;
        // GOOD: var random = frame.RNG->Next();
    }
}
```

### Working with Predicted and Verified Frames

Different frame types are used for different purposes:

```csharp
// In a Unity view component
public override void OnUpdateView()
{
    // Use predicted frame for rendering
    var predicted = QuantumRunner.Default.Game.Frames.Predicted;
    var transform3D = predicted.Get<Transform3D>(EntityRef);
    
    // Update position based on predicted frame
    transform.position = transform3D.Position.ToUnityVector3();
    transform.rotation = transform3D.Rotation.ToUnityQuaternion();
    
    // For important gameplay decisions, consider using verified frame
    var verified = QuantumRunner.Default.Game.Frames.Verified;
    var health = verified.Get<Health>(EntityRef);
    
    // Update UI based on verified frame
    if (healthBar != null) {
        healthBar.value = health.Current.AsFloat / health.Max.AsFloat;
    }
}
```

## Prediction Culling

Quantum offers a prediction culling feature to optimize performance by only predicting entities near the player:

```csharp
// In a system that manages the prediction area
public unsafe class PredictionCullingSystem : SystemBase
{
    public override void OnInit(Frame f)
    {
        // Set initial prediction area
        f.SetPredictionArea(FPVector3.Zero, FP._20);
    }
    
    public override void Update(Frame f)
    {
        // Find local player
        var localPlayerRef = GetLocalPlayerRef(f);
        if (localPlayerRef.IsValid) {
            var transform = f.Get<Transform3D>(localPlayerRef);
            if (transform != null) {
                // Update prediction area around player with radius of 20 FP units
                f.SetPredictionArea(transform.Position, FP._20);
            }
        }
    }
}
```

### Testing if an Entity is in Prediction Area

```csharp
public unsafe class AISystem : SystemMainThreadFilter<AISystem.Filter>
{
    public override void Update(Frame f, ref Filter filter)
    {
        // Check if entity is in prediction area
        if (f.IsPredicted && !f.InPredictionArea(filter.Transform->Position)) {
            // Skip expensive AI for entities far from player during prediction
            return;
        }
        
        // Run full AI logic
        RunAILogic(f, ref filter);
    }
}
```

## Rollback Optimization

### Minimizing Rollback Impact

```csharp
public unsafe class ExpensiveSystem : SystemMainThreadFilter<ExpensiveSystem.Filter>
{
    public override void Update(Frame f, ref Filter filter)
    {
        // For expensive operations, consider only running on verified frames
        if (f.IsVerified) {
            RunExpensiveOperation(f, ref filter);
        }
        // Or run a simplified version during prediction
        else if (f.IsPredicted) {
            RunSimplifiedOperation(f, ref filter);
        }
    }
}
```

### Using Flags for Optimizing Rollbacks

```csharp
// In your component definition
component ParticleEmitter {
    bool NeedsReset;
    FP EmissionRate;
    FP Timer;
}

// In your system
public unsafe class ParticleSystem : SystemMainThreadFilter<ParticleSystem.Filter>
{
    public override void Update(Frame f, ref Filter filter)
    {
        // Set flag for view to reset particles after rollback
        if (f.IsRollback) {
            filter.ParticleEmitter->NeedsReset = true;
        }
        
        // Update timer
        filter.ParticleEmitter->Timer += f.DeltaTime;
    }
}

// In your view component
public override void OnUpdateView()
{
    var emitter = GetPredictedQuantumComponent<ParticleEmitter>();
    if (emitter != null && emitter.NeedsReset) {
        // Reset particle system after rollback
        _particleSystem.Clear();
        _particleSystem.Play();
    }
}
```

## Handling Input During Prediction

```csharp
public class PlayerInput : QuantumEntityViewComponent
{
    private Quantum.Input _input;
    private Quantum.Input _confirmedInput;
    
    // Poll input for Quantum
    private void PollInput(CallbackPollInput callback)
    {
        var flags = DeterministicInputFlags.Repeatable;
        
        // If this is for a verified frame, save the input
        if (callback.IsVerified) {
            _confirmedInput = _input;
        }
        // If we're predicting and have confirmed input for this player, use it
        else if (callback.InputProtocol.Tick <= callback.PreviouslyConfirmedTick) {
            callback.SetInput(_confirmedInput, flags);
            return;
        }
        
        // Otherwise, use the current input
        callback.SetInput(_input, flags);
    }
}
```

## Debugging Prediction and Rollback

Quantum provides tools for debugging prediction and rollback:

```csharp
// Subscribe to rollback debugging
QuantumCallback.Subscribe(this, (CallbackRollbackBegin cb) => {
    Debug.Log($"Rollback beginning from tick {cb.From} to {cb.To}");
});

QuantumCallback.Subscribe(this, (CallbackRollbackEnd cb) => {
    Debug.Log($"Rollback ended, resimulated {cb.FrameCount} frames");
});

// Use frame debug flags
var flags = DumpFlag_AssetDBCheckums | DumpFlag_ComponentChecksums;
var dump = QuantumRunner.Default.Game.Frames.Verified.DumpFrame(flags);
Debug.Log(dump);
```

## Performance Monitoring

```csharp
// Subscribe to simulation statistics
QuantumCallback.Subscribe(this, (CallbackSimulationStatistics cb) => {
    Debug.Log($"Avg. simulation time: {cb.AverageExecutionTime}ms");
    Debug.Log($"Predicted frames: {cb.PredictedFrameCount}");
    Debug.Log($"Rollbacks: {cb.RollbackCount}");
});
```

## Visualizing Prediction and Rollback

```csharp
// In a MonoBehaviour
public class PredictionVisualizer : MonoBehaviour
{
    public Text PredictionBufferText;
    public Text RollbackCountText;
    
    private int _rollbackCount;
    
    void Start()
    {
        QuantumCallback.Subscribe(this, (CallbackRollbackEnd cb) => {
            _rollbackCount++;
        });
    }
    
    void Update()
    {
        if (QuantumRunner.Default?.Game != null)
        {
            var game = QuantumRunner.Default.Game;
            var predictedTick = game.Frames.Predicted.Number;
            var verifiedTick = game.Frames.Verified.Number;
            var bufferSize = predictedTick - verifiedTick;
            
            PredictionBufferText.text = $"Prediction Buffer: {bufferSize} frames";
            RollbackCountText.text = $"Rollbacks: {_rollbackCount}";
        }
    }
}
```

## Best Practices

### Optimize for Prediction

1. **Keep expensive operations in the verified frame**: Heavy pathfinding, complex AI decisions
2. **Simplify during prediction**: Use simpler algorithms during prediction
3. **Use prediction culling**: Only predict entities near the player
4. **Be careful with random numbers**: Always use `frame.RNG` for deterministic randomness
5. **Use checksums**: Compare checksums to debug prediction mismatches

### Reduce Rollback Frequency and Impact

1. **Optimize input collection**: Collect inputs consistently and efficiently
2. **Use interpolation for visuals**: Interpolate between physics steps for smoother rendering
3. **Maintain a reasonable prediction buffer**: Balance responsiveness with stability
4. **Handle rollback visually**: Reset visual effects smoothly during rollbacks
5. **Use rollback callbacks**: React to rollbacks appropriately in your UI/effects

### Debug Effectively

1. **Monitor prediction buffer size**: Keep an eye on the gap between verified and predicted frames
2. **Track rollback statistics**: Monitor how often rollbacks occur
3. **Use frame dumps**: Compare frame state dumps to find determinism issues
4. **Enable checksums**: Verify determinism with checksums
5. **Test with artificial latency**: Verify behavior under varying network conditions

By understanding and optimizing for Quantum's prediction and rollback system, you can create multiplayer games that feel responsive even in challenging network conditions.
