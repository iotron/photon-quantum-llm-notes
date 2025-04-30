# Quantum Motor Dome Input System

This document details the input system used in the Quantum Motor Dome project, covering how player input is defined, processed, and applied to ships within the deterministic simulation.

## Input Definition

The Quantum Motor Dome input structure is defined in `input.qtn` as follows:

```qtn
input
{
	FP steer;
	bool boost;
	bool brake;
}
```

This structure contains:
- **steer**: Analog value for steering the ship (-1 to 1)
- **boost**: Boolean for activating boost
- **brake**: Boolean for braking/slowing down

## Unity Input Collection

The Unity-side input is captured in the `LocalInput` class, which subscribes to Quantum's input polling callback:

```csharp
public class LocalInput : MonoBehaviour
{
	private void OnEnable()
	{
		QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
	}

	public void PollInput(CallbackPollInput callback)
	{
		Quantum.Input i = new()
		{
			steer = UnityEngine.Input.GetAxis("Horizontal").ToFP(),
			boost = UnityEngine.Input.GetButton("Boost"),
			brake = UnityEngine.Input.GetButton("Brake")
		};

		callback.SetInput(i, DeterministicInputFlags.Repeatable);
	}
}
```

Key aspects of this implementation:
1. **Subscription**: Subscribes to the `CallbackPollInput` event from Quantum
2. **Input Mapping**: Maps Unity input to Quantum input structure
3. **Conversion**: Converts Unity's float values to Quantum's deterministic FP type
4. **Flags**: Uses `DeterministicInputFlags.Repeatable` to ensure deterministic behavior

## Input Application

The input is applied in the `ShipMovementSystem`, which processes player input and updates ship movement:

```csharp
unsafe class ShipMovementSystem : SystemMainThreadFilter<ShipFilter>, IGameState_Game
{
    public override void Update(Frame f, ref ShipFilter filter)
    {
        if (f.Has<Delay>(filter.Entity)) return;

        // Get input from the player
        Input* input = f.GetPlayerInput(filter.Link->Player);

        // Update ship state based on input
        filter.Player->SteerAmount = FPMath.Clamp(input->steer, -1, 1);
        filter.Player->IsBoosting = input->boost && filter.Player->BoostAmount > 0;
        filter.Player->IsBraking = input->brake;

        // Apply steering
        FP steerRate = filter.Player->SteerAmount * spec.steerRate;
        if (filter.Player->IsBraking) steerRate /= 2; // Reduce steering rate when braking
        filter.Transform->Rotation *= FPQuaternion.AngleAxis(steerRate * f.DeltaTime, FPVector3.Up);
        
        // Calculate speed based on input
        FP speed = filter.Player->IsBoosting ? 
            spec.speedBoosting : 
            input->brake ? spec.speedBraking : spec.speedNormal;

        // Handle boost consumption
        if (filter.Player->IsBoosting)
        {
            filter.Player->BoostAmount -= spec.boostDrain * f.DeltaTime;
            if (filter.Player->BoostAmount < 0) filter.Player->BoostAmount = 0;
        }

        // Apply movement
        filter.Transform->Position += filter.Transform->Forward * speed * f.DeltaTime;
        
        // Implementation details for trail and orientation continue...
    }
}
```

Key aspects of input application:
1. **Input Retrieval**: Uses `f.GetPlayerInput(filter.Link->Player)` to get input for the specific player
2. **State Mapping**: Maps input values to ship state properties
3. **Conditional Logic**: Applies effects based on combinations of input (e.g., boosting requires both boost button and available boost energy)
4. **Resource Management**: Consumes boost resource when boost input is active

## Input Filters

The `ShipMovementSystem` uses a filter to process only entities with the required components:

```csharp
public struct ShipFilter
{
    public EntityRef Entity;
    public Transform3D* Transform;
    public Ship* Player;
    public PlayerLink* Link;
}
```

This ensures that input processing only happens for valid ships that have:
- A Transform3D component for position and rotation
- A Ship component for ship-specific properties
- A PlayerLink component to connect the ship to a player

## Player Commands

In addition to regular input polling, the game also supports command-based input for specific actions:

```csharp
public struct IntroFinishedCommand : ICommand
{
    public void Execute(Frame f)
    {
        foreach (var system in f.SystemsAll.OfType<IntroSystem>())
        {
            system.IntroFinished(f, this);
        }
    }
}
```

Commands are triggered from Unity:

```csharp
public void SendIntroFinishedCommand()
{
    if (QuantumRunner.Default?.Game?.PlayerIsLocal(LocalData.LocalPlayerRef) == true)
    {
        QuantumRunner.Default.Game.SendCommand(new IntroFinishedCommand());
    }
}
```

Key aspects of command-based input:
1. **Command Interface**: Implements the `ICommand` interface
2. **Targeted Execution**: Commands target specific systems
3. **Local Validation**: Only the local player sends commands
4. **Non-Continuous Actions**: Used for discrete actions rather than continuous input

## Pause and UI Input

The `LocalInput` class also handles input for UI and pausing:

```csharp
private void Update()
{
    if (UnityEngine.Input.GetKeyDown(KeyCode.P))
    {
        if (UIScreen.activeScreen == InterfaceManager.Instance.hudScreen)
            UIScreen.Focus(InterfaceManager.Instance.pauseScreen);
        else if (UIScreen.ScreenInHierarchy(InterfaceManager.Instance.hudScreen))
            UIScreen.activeScreen.BackTo(InterfaceManager.Instance.hudScreen);
    }
}
```

This approach separates UI/pausing input (handled in Unity) from gameplay input (sent to Quantum).

## Input Response Visualization

The Unity-side `ShipView` class visualizes the ship's response to input:

```csharp
public unsafe class ShipView : MonoBehaviour
{
    public float oversteerAmount = 10;
    public float rollAmount = 45;
    public float steerVisualRate = 20;
    
    private void Update()
    {
        Ship* player = game.Frames.Predicted.Unsafe.GetPointer<Ship>(EntityRef);
        
        // Apply visual steering effects
        Quaternion rollRot = Quaternion.AngleAxis(player->SteerAmount.AsFloat * -rollAmount, Vector3.forward);
        Quaternion oversteerRot = Quaternion.Euler(0, player->SteerAmount.AsFloat * oversteerAmount, 0);
        Quaternion tgtRot = oversteerRot * rollRot;
        Quaternion srcRot = pivot.localRotation;
        pivot.localRotation = Quaternion.RotateTowards(
            srcRot, 
            tgtRot, 
            Mathf.Sqrt(Quaternion.Angle(srcRot, tgtRot)) * steerVisualRate * Time.deltaTime
        );
        
        // Handle boost visualization
        if (player->IsBoosting && !wasBoosting) boostSrc.Play();
        else if (!player->IsBoosting && wasBoosting) boostSrc.Stop();
        wasBoosting = player->IsBoosting;
    }
}
```

Key aspects of input visualization:
1. **Steering Effects**: Applies roll and oversteer visual effects based on steering input
2. **Smoothing**: Smoothly interpolates between visual states
3. **Audio Feedback**: Plays audio effects when boost state changes
4. **State Tracking**: Tracks previous state to detect changes

## Input Configuration

Input sensitivities and effects are configured in the `ShipSpec` asset:

```csharp
public partial class ShipSpec : AssetObject
{
    public FP speedNormal;
    public FP speedBoosting;
    public FP speedBraking;
    public FP steerRate;
    public FP boostDrain;
}
```

This allows for adjustment of:
- **Movement Speeds**: Normal, boosting, and braking speeds
- **Steering Sensitivity**: How quickly the ship turns in response to input
- **Boost Consumption**: How quickly boost energy depletes when used

## Input Flow

The complete input flow in Quantum Motor Dome follows this sequence:

1. **Unity** captures raw input via `LocalInput.PollInput`
2. Input is converted to deterministic types and sent to Quantum
3. **Quantum** processes the input in `ShipMovementSystem.Update`
4. Ship state is updated based on input values
5. Physics calculations are applied based on the updated state
6. The ship's position, rotation, and other properties are updated
7. **Unity** retrieves the updated state from Quantum
8. **ShipView** updates the visual representation based on the ship state

## Best Practices

1. **Deterministic Conversion**: Always convert Unity input to deterministic types (FP) before sending to Quantum
2. **Input Validation**: Validate input ranges (e.g., clamp steer value between -1 and 1)
3. **Resource Checks**: Check resource availability before applying effects (e.g., boost requires energy)
4. **Separation of Concerns**: Keep gameplay input (Quantum) separate from UI input (Unity)
5. **Smooth Visualization**: Apply smoothing and visual enhancements to make input response feel natural
6. **Configurable Parameters**: Store input sensitivities and effects in configurable assets
7. **Command Pattern**: Use commands for discrete, non-continuous actions
8. **Contextual Behavior**: Adjust input response based on context (e.g., reduced steering while braking)
