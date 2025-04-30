# Input System in Quantum Simple FPS

This document explains how player input is defined, captured in Unity, transformed into Quantum's deterministic format, and processed in the simulation for the Quantum Simple FPS game.

## Input Definition

In Quantum Simple FPS, the input structure is defined in `Input.qtn`:

```qtn
input
{
    FPVector2 MoveDirection;
    FPVector2 LookRotationDelta;
    byte      InterpolationOffset;
    byte      InterpolationAlphaEncoded;
    byte      Weapon;
    button    Jump;
    button    Fire;
    button    Reload;
    button    Spray;
}
```

Key components of this input structure:
- `MoveDirection`: Character movement direction (normalized 2D vector)
- `LookRotationDelta`: Mouse/controller look rotation change
- `InterpolationOffset/Alpha`: Used for smooth client-side interpolation
- `Weapon`: Selected weapon slot (1-based index)
- Button states: `Jump`, `Fire`, `Reload`, `Spray`

## Input Extensions

The input definition is extended in `Input.cs` to add helper properties:

```csharp
partial struct Input
{
    // The interpolation alpha is encoded to a single byte for bandwidth optimization
    public FP InterpolationAlpha
    {
        get => ((FP)InterpolationAlphaEncoded) / 255;
        set
        {
            FP clamped = FPMath.Clamp(value * 255, 0, 255);
            InterpolationAlphaEncoded = (byte)clamped.AsInt;
        }
    }
}
```

This extension converts between a full FP value and a byte-encoded value to optimize network bandwidth.

## Input Polling in Unity

The input is captured on the Unity side through the `CharacterInputPoller` component. Here's a simplified version of the implementation:

```csharp
namespace QuantumDemo
{
    // Attached to the character view prefab
    public class CharacterInputPoller : QuantumEntityViewComponent
    {
        // Mouse sensitivity settings
        public float MouseHorizontalSensitivity = 0.8f;
        public float MouseVerticalSensitivity = 0.5f;
        
        // Camera reference
        public Transform CameraTransform;
        
        // Input state
        private Vector2 _lookInput;
        private Vector2 _moveInput;
        private float _rotation;
        private int _lastWeaponIndex;
        
        public override void OnActivate(Frame frame)
        {
            // Only poll input for the local player
            var player = frame.Get<Player>(EntityRef);
            if (frame.PlayerIsLocal(player.PlayerRef))
            {
                QuantumCallback.Subscribe(this, (CallbackPollInput callback) => 
                {
                    PollInput(callback);
                });
            }
        }
        
        private void PollInput(CallbackPollInput callback)
        {
            var input = new Input();
            
            // Movement input
            _moveInput.x = UnityEngine.Input.GetAxisRaw("Horizontal");
            _moveInput.y = UnityEngine.Input.GetAxisRaw("Vertical");
            input.MoveDirection = _moveInput.ToFPVector2();
            
            // Look rotation input
            if (Cursor.lockState == CursorLockMode.Locked)
            {
                _lookInput.x = Input.GetAxis("Mouse X") * MouseHorizontalSensitivity;
                _lookInput.y = Input.GetAxis("Mouse Y") * MouseVerticalSensitivity;
            }
            
            // Convert to Quantum's fixed point format
            input.LookRotationDelta = _lookInput.ToFPVector2();
            
            // Button inputs
            input.Jump = Input.GetKey(KeyCode.Space);
            input.Fire = Input.GetMouseButton(0);
            input.Reload = Input.GetKey(KeyCode.R);
            input.Spray = Input.GetMouseButton(1);
            
            // Weapon selection
            if (Input.GetKeyDown(KeyCode.Alpha1)) _lastWeaponIndex = 1;
            if (Input.GetKeyDown(KeyCode.Alpha2)) _lastWeaponIndex = 2;
            if (Input.GetKeyDown(KeyCode.Alpha3)) _lastWeaponIndex = 3;
            if (Input.GetKeyDown(KeyCode.Alpha4)) _lastWeaponIndex = 4;
            
            input.Weapon = (byte)_lastWeaponIndex;
            
            // Interpolation timing
            input.InterpolationOffset = (byte)callback.InterpolationTarget;
            input.InterpolationAlpha = FP.FromFloat_UNSAFE(callback.InterpolationAlpha);
            
            // Send input to Quantum with the Repeatable flag for determinism
            callback.SetInput(input, DeterministicInputFlags.Repeatable);
        }
    }
}
```

Key aspects of this implementation:
1. It only subscribes to input polling for the local player
2. Captures movement from keyboard (WASD/arrows)
3. Captures look rotation from mouse movement
4. Handles weapon selection via number keys
5. Converts Unity floating-point values to Quantum's fixed-point format
6. Sends the input with the `Repeatable` flag to ensure determinism

## Input Processing in Simulation

The input is processed by various systems in the Quantum simulation:

### Player System

The `PlayerSystem` processes movement input to control the character:

```csharp
[Preserve]
public unsafe class PlayerSystem : SystemMainThreadFilter<PlayerSystem.Filter>
{
    public override void Update(Frame frame, ref Filter filter)
    {
        var player = filter.Player;
        if (player->PlayerRef.IsValid == false)
            return;

        var kcc = filter.KCC;
        var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
        
        // Don't process input when the game is finished
        if (gameplay->State == EGameplayState.Finished)
        {
            kcc->SetInputDirection(FPVector3.Zero);
            return;
        }

        var input = frame.GetPlayerInput(player->PlayerRef);

        if (filter.Health->IsAlive)
        {
            // Apply look rotation
            kcc->AddLookRotation(input->LookRotationDelta.X, input->LookRotationDelta.Y);
            
            // Convert 2D input to 3D movement vector based on current rotation
            kcc->SetInputDirection(kcc->Data.TransformRotation * input->MoveDirection.XOY);
            kcc->SetKinematicSpeed(player->MoveSpeed);

            // Process jump input
            if (input->Jump.WasPressed && kcc->IsGrounded)
            {
                kcc->Jump(FPVector3.Up * player->JumpForce);
            }
        }
        else
        {
            // Dead players don't move
            kcc->SetInputDirection(FPVector3.Zero);
        }
    }

    public struct Filter
    {
        public EntityRef Entity;
        public Player*   Player;
        public Health*   Health;
        public KCC*      KCC;
    }
}
```

The `KCC` (Kinematic Character Controller) handles the actual movement physics, collision detection, and ground checking.

### Weapons System

The `WeaponsSystem` processes weapon-related input:

```csharp
public override void Update(Frame frame, ref Filter filter)
{
    if (filter.Health->IsAlive == false)
        return;
    if (filter.Player->PlayerRef.IsValid == false)
        return;

    var input = frame.GetPlayerInput(filter.Player->PlayerRef);
    var currentWeapon = frame.Unsafe.GetPointer<Weapon>(filter.Weapons->CurrentWeapon);

    UpdateWeaponSwitch(frame, ref filter);
    UpdateReload(frame, ref filter, currentWeapon);

    filter.Weapons->FireCooldown -= frame.DeltaTime;

    // Process weapon selection input
    if (input->Weapon >= 1)
    {
        TryStartWeaponSwitch(frame, ref filter, (byte)(input->Weapon - 1));
    }

    // Process fire input
    if (input->Fire.IsDown)
    {
        TryFire(frame, ref filter, currentWeapon, input->Fire.WasPressed);

        // Cancel after-spawn immortality when player starts shooting
        filter.Health->StopImmortality();
    }

    // Process reload input
    if (input->Reload.IsDown || currentWeapon->ClipAmmo <= 0)
    {
        TryStartReload(frame, ref filter, currentWeapon);
    }
}
```

## Button State Handling

The `button` type in Quantum provides built-in state tracking for input buttons. Each button has the following states:

- `IsDown`: Whether the button is currently pressed
- `WasPressed`: Whether the button was just pressed this frame
- `WasReleased`: Whether the button was just released this frame

These states are automatically updated by Quantum based on the current and previous input values.

## Input Interpolation

The Simple FPS game uses client-side interpolation to create smooth movement. The input structure includes:

- `InterpolationOffset`: Identifies which historical frame to use for interpolation
- `InterpolationAlpha`: Specifies the blend factor between frames

These values are used by the view layer to interpolate between physics states, creating smooth visual movement while maintaining deterministic simulation.

## Best Practices for FPS Input Handling

1. **Separate look and movement**: Process look rotation and movement independently
2. **Use fixed sensitivities**: Apply consistent sensitivity scaling for different input devices
3. **Convert to fixed point early**: Convert Unity floating-point values to Quantum fixed point as soon as possible
4. **Use deterministic flags**: Always set input with the `Repeatable` flag
5. **Process input in systems**: Keep input processing in Quantum systems, not in Unity scripts
6. **Use button state properties**: Use `WasPressed` and `WasReleased` for one-time actions
7. **Handle dead states**: Disable input processing for dead players
8. **Optimize bandwidth**: Use techniques like byte encoding to minimize input size

These practices ensure consistent, deterministic input handling for a responsive FPS experience across all clients, even with network latency.
