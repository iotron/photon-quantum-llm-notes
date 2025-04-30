# Quantum Input System

## Introduction

Input is a crucial component of Quantum's core architecture. In a deterministic networking library:
- The output is fixed and predetermined given a certain input
- When input is the same across all clients in the network, the output will also be the same

## Defining Input in DSL

Input can be defined in any [DSL](/quantum/current/manual/quantum-ecs/dsl) file. For example:

```qtn
input
{
    button Jump;
    FPVector3 Direction;
}
```

The server is responsible for batching and sending input confirmations for full tick-sets (all players' input). Therefore, this struct should be kept as small as possible.

## Commands vs. Input

While regular input is sent every frame, [Deterministic Commands](/quantum/current/manual/commands) provide another input path that:
- Can have arbitrary data and size
- Are ideal for special types of inputs (buy item, teleport, etc.)

## Polling Input in Unity

To send input to the Quantum simulation, you poll for it inside Unity by subscribing to the `PollInput` callback:

```csharp
private void OnEnable() 
{
  QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
}
```

Then, in the callback function, read from the input source and populate the input struct:

```csharp
public void PollInput(CallbackPollInput callback)
{
  Quantum.Input i = new Quantum.Input(); 
  
  var direction = new Vector3();
  direction.x = UnityEngine.Input.GetAxisRaw("Horizontal");
  direction.y = UnityEngine.Input.GetAxisRaw("Vertical");
  
  i.Jump = UnityEngine.Input.GetKey(KeyCode.Space);
  
  // convert to fixed point
  i.Direction = direction.ToFPVector3();
  
  callback.SetInput(i, DeterministicInputFlags.Repeatable);
}
```

**Note**: The float to fixed point conversion is deterministic because it is done before being shared with the simulation.

## Optimization Techniques

Although Quantum 3 uses delta-compression for input, it's still a good practice to make the raw `Input` data as compact as possible for optimal bandwidth.

### Using Buttons

The `button` type is used inside the Input DSL definition instead of booleans:
- Only uses one bit per instance in network transmission
- Locally contains more game state

```qtn
input
{
    button Jump;
}
```

Important notes on buttons:
- When polling from Unity, you should poll the *current button state* (whether it's pressed at the current frame)
- Quantum automatically sets up internal properties that allow checking specific states in simulation code:
  - `WasPressed`
  - `IsDown`
  - `WasReleased`
- Do not use Unity's `GetKeyUp()` or `GetKeyDown()` which would be problematic due to different update rates

Example of correctly polling button state in Unity:

```csharp
// In Unity, when polling a player's input
input.Jump = UnityEngine.Input.GetKey(KeyCode.Space);
```

For updating button state in Quantum simulation code (e.g., for bots):

```csharp
// In Quantum code, must be updated every frame
input.button.Update(frame, value);
```

### Encoded Direction

Movement is often represented using a direction vector:

```qtn
input
{
    FPVector2 Direction;
}
```

However, `FPVector2` comprises two 'FP' values, which takes up 16 bytes of data. For optimization, you can extend the `Input` struct and encode the directional vector into a `Byte` instead of sending the full vector every time.

Implementation example:

1. First, define the input with a `Byte` for encoded direction:

```qtn
input
{
    Byte EncodedDirection;
}
```

2. Then, extend the input struct (similar to extending a component):

```csharp
namespace Quantum
{
    partial struct Input
    {
        public FPVector2 Direction
        {
            get
            {
                if (EncodedDirection == default) 
                    return default;
                
                Int32 angle = ((Int32)EncodedDirection - 1) * 2;
            
                return FPVector2.Rotate(FPVector2.Up, angle * FP.Deg2Rad);
            }
            set
            {
                if (value == default)
                {
                    EncodedDirection = default;
                        return;
                }
               
                var angle = FPVector2.RadiansSigned(FPVector2.Up, value) * FP.Rad2Deg;
                
                angle = (((angle + 360) % 360) / 2) + 1;
            
                EncodedDirection = (Byte) (angle.AsInt);
            }
        }
    }
}
```

This implementation allows for the same usage as before but only takes up a single byte instead of 16 bytes. It works by utilizing a `Direction` property that automatically encodes and decodes the value from `EncodedDirection`.

## Best Practices

1. **Minimize Input Size**: Keep the input struct as small as possible to reduce network traffic.
   
2. **Use Buttons**: Prefer the `button` type over booleans for input actions.
   
3. **Consider Encoding**: For vectors and other large data types, consider encoding into smaller formats.
   
4. **Separate Occasional Inputs**: Use Commands for inputs that don't need to be sent every frame.
   
5. **Consistent Polling**: Make sure input is polled consistently for all players to maintain determinism.
   
6. **Test Network Conditions**: Test your input system under various network conditions to ensure it remains responsive.
