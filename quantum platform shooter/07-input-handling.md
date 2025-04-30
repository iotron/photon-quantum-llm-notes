# Input Handling in Quantum Platform Shooter 2D

This document explains how player input is captured in Unity, transformed into Quantum's deterministic format, and processed in the simulation.

## Input Definition

The Platform Shooter 2D game uses a custom input structure defined in `Input.User.cs`:

```csharp
// Partial extension of the Quantum.Input struct
public partial struct QuantumDemoInputPlatformer2D
{
    public Boolean Left;
    public Boolean Right;
    public Boolean Jump;
    public Boolean Fire;
    public Boolean AltFire;
    public Boolean Use;
    public FPVector2 AimDirection;
}
```

This structure is automatically generated from the DSL definition and extended with additional methods.

## Input Polling in Unity

The input is captured on the Unity side through the `LocalQuantumInputPoller` component:

```csharp
namespace PlatformShooter2D
{
  using Photon.Deterministic;
  using UnityEngine;
  using QuantumMobileInputTools;
  using Quantum;

  public class LocalQuantumInputPoller : QuantumEntityViewComponent<CustomViewContext>
  {
    public float AimAssist = 20;
    public float AimSpeed = 2;
    private Vector2 _lastPlayerDirection;

    public override void OnInitialize()
    {
      _lastPlayerDirection = Vector2.left;
    }

    public override void OnActivate(Frame frame)
    {
      var playerLink = VerifiedFrame.Get<PlayerLink>(EntityRef);

      // Only subscribe to input polling for local player
      if (Game.PlayerIsLocal(playerLink.Player))
      {
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback),
          onlyIfActiveAndEnabled: true);
      }
    }

    public override void OnUpdateView()
    {
      var playerLink = VerifiedFrame.Get<PlayerLink>(EntityRef);
      if (Game.PlayerIsLocal(playerLink.Player))
      {
        // Store aim direction in view context for other view components
        ViewContext.LocalCharacterLastDirection = GetAimDirection();
      }
    }

    public void PollInput(CallbackPollInput callback)
    {
      QuantumDemoInputPlatformer2D input = default;

      if (callback.Game.GetLocalPlayers().Count == 0)
      {
        return;
      }
      
      var control = QuantumLocalInputValuesControl.Instance;

      // Get fire input
      input.Fire = control.GetControlValue(ControlMap.Fire).BoolValue;

      // Handle mobile-specific input
#if UNITY_MOBILE || UNITY_ANDROID
      var aimDirection = control.GetControlValue(ControlMap.Aim).Vector2Value;
      input.Fire = (aimDirection.magnitude >= 0.5f);
#endif

      // Get movement input
      var movement = GetMovement();
      input.Left = movement < 0;
      input.Right = movement > 0;

      // Get other inputs
      input.Jump = control.GetControlValue(ControlMap.Jump).BoolValue;
      input.AimDirection = GetAimDirection();
      input.Use = control.GetControlValue(ControlMap.ChangeWeapon).BoolValue;
      input.AltFire = control.GetControlValue(ControlMap.CastSkill).BoolValue;

      // Send input to Quantum with the Repeatable flag for determinism
      callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }

    private FP GetMovement()
    {
      var control = QuantumLocalInputValuesControl.Instance;
      FPVector2 directional = control.GetControlValue(ControlMap.Move).Vector2Value.ToFPVector2();
      return directional.X;
    }

    private FPVector2 GetAimDirection()
    {
      var control = QuantumLocalInputValuesControl.Instance;
      Vector2 direction = Vector2.zero;
      Frame frame = PredictedFrame;
      var isMobile = false;

#if !UNITY_STANDALONE && !UNITY_WEBGL
      isMobile = true;
#endif
      if (frame.TryGet<Transform2D>(EntityRef, out var characterTransform))
      {
        if (isMobile)
        {
          // Mobile aim handling with touch controls
          Vector2 directional = control.GetControlValue(ControlMap.Aim).Vector2Value;
          var controlDir = new Vector2(directional.x, directional.y);
          if (controlDir.sqrMagnitude > 0.1f)
          {
            direction = controlDir;
          }
          else if (Mathf.Abs(GetMovement().AsFloat) > 0.1f)
          {
            direction = new Vector2(GetMovement().AsFloat, 0);
          }
          else
          {
            direction = _lastPlayerDirection;
          }

          _lastPlayerDirection = direction;

          // Apply aim assist
          var minorAngle = AimAssist;
          var position = frame.Get<Transform2D>(EntityRef).Position;
          var targetDirection = position - characterTransform.Position;

          if (Vector2.Angle(direction, targetDirection.ToUnityVector2()) <= minorAngle)
          {
            direction = Vector2.Lerp(direction, targetDirection.ToUnityVector2(), Time.deltaTime * AimSpeed);
          }
        }
        else
        {
          // Desktop aim handling with mouse
          var localCharacterPosition = characterTransform.Position.ToUnityVector3();
          var localCharacterScreenPosition = Camera.main.WorldToScreenPoint(localCharacterPosition);
          var mousePos = control.GetControlValue(ControlMap.MousePosition).Vector2Value;
          if (!Application.isFocused)
          {
            mousePos = Vector2.zero;
          }

          direction = mousePos - new Vector2(localCharacterScreenPosition.x, localCharacterScreenPosition.y);
        }

        // Convert to Quantum's fixed point format
        return new FPVector2(FP.FromFloat_UNSAFE(direction.x), FP.FromFloat_UNSAFE(direction.y));
      }

      return FPVector2.Zero;
    }
  }
}
```

Key aspects:
1. Subscribes to Quantum's `CallbackPollInput` for the local player only
2. Collects input from Unity's input system via the `QuantumLocalInputValuesControl`
3. Handles platform-specific input differences (mobile vs. desktop)
4. Processes aim direction based on touch or mouse input
5. Provides aim assist for mobile players
6. Converts Unity vectors to Quantum's fixed point vectors
7. Sets input with the `Repeatable` flag to ensure determinism

## Input Controls Mapping

The game uses a control mapping system to abstract input sources:

```csharp
// Control mapping constants
public static class ControlMap
{
    public const string Jump = "Jump";
    public const string Fire = "Fire";
    public const string CastSkill = "CastSkill";
    public const string ChangeWeapon = "ChangeWeapon";
    public const string Move = "Move";
    public const string Aim = "Aim";
    public const string MousePosition = "MousePosition";
}
```

This allows for different input implementations while maintaining the same control interface.

## Standalone Input Implementation

For desktop platforms, the game uses a standalone input implementation:

```csharp
public class LocalGameplayInputStandalone : MonoBehaviour, ILocalInputValuesProvider
{
    // Input values cache
    private Dictionary<string, ControlValue> _controls = new Dictionary<string, ControlValue>();
    
    private void Awake()
    {
        // Register as input provider
        QuantumLocalInputValuesControl.Instance.RegisterProvider(this);
    }
    
    private void OnDestroy()
    {
        // Unregister on destruction
        QuantumLocalInputValuesControl.Instance.UnregisterProvider(this);
    }
    
    private void Update()
    {
        // Poll keyboard/mouse input
        _controls[ControlMap.Jump] = new ControlValue(Input.GetKey(KeyCode.Space));
        _controls[ControlMap.Fire] = new ControlValue(Input.GetMouseButton(0));
        _controls[ControlMap.CastSkill] = new ControlValue(Input.GetMouseButton(1));
        _controls[ControlMap.ChangeWeapon] = new ControlValue(Input.GetKeyDown(KeyCode.Q));
        
        // Movement
        float horizontal = Input.GetAxisRaw("Horizontal");
        _controls[ControlMap.Move] = new ControlValue(new Vector2(horizontal, 0));
        
        // Mouse position
        _controls[ControlMap.MousePosition] = new ControlValue(Input.mousePosition);
    }
    
    public ControlValue GetControlValue(string control)
    {
        if (_controls.TryGetValue(control, out var value))
        {
            return value;
        }
        return default;
    }
}
```

## Mobile Input Implementation

For mobile platforms, the game uses touch-based input with virtual controls:

```csharp
// Mobile input handling (simplified)
public class MobileInputHandler : MonoBehaviour, ILocalInputValuesProvider
{
    public Joystick MovementJoystick;
    public Joystick AimJoystick;
    public Button JumpButton;
    public Button FireButton;
    public Button SkillButton;
    public Button WeaponButton;
    
    private Dictionary<string, ControlValue> _controls = new Dictionary<string, ControlValue>();
    
    private void Awake()
    {
        QuantumLocalInputValuesControl.Instance.RegisterProvider(this);
    }
    
    private void Update()
    {
        // Update controls from UI elements
        _controls[ControlMap.Jump] = new ControlValue(JumpButton.IsPressed);
        _controls[ControlMap.Fire] = new ControlValue(FireButton.IsPressed);
        _controls[ControlMap.CastSkill] = new ControlValue(SkillButton.IsPressed);
        _controls[ControlMap.ChangeWeapon] = new ControlValue(WeaponButton.IsPressed);
        
        // Joystick values
        _controls[ControlMap.Move] = new ControlValue(new Vector2(MovementJoystick.Horizontal, 0));
        _controls[ControlMap.Aim] = new ControlValue(new Vector2(AimJoystick.Horizontal, AimJoystick.Vertical));
    }
    
    public ControlValue GetControlValue(string control)
    {
        if (_controls.TryGetValue(control, out var value))
        {
            return value;
        }
        return default;
    }
}
```

## Input Abstraction Layer

The `QuantumLocalInputValuesControl` serves as an abstraction layer between input providers and consumers:

```csharp
// Simplified QuantumLocalInputValuesControl
public class QuantumLocalInputValuesControl : MonoBehaviour
{
    public static QuantumLocalInputValuesControl Instance { get; private set; }
    
    private List<ILocalInputValuesProvider> _providers = new List<ILocalInputValuesProvider>();
    
    private void Awake()
    {
        Instance = this;
    }
    
    public void RegisterProvider(ILocalInputValuesProvider provider)
    {
        _providers.Add(provider);
    }
    
    public void UnregisterProvider(ILocalInputValuesProvider provider)
    {
        _providers.Remove(provider);
    }
    
    public ControlValue GetControlValue(string control)
    {
        // Query all providers, prioritizing the last registered one
        for (int i = _providers.Count - 1; i >= 0; i--)
        {
            var value = _providers[i].GetControlValue(control);
            if (value.IsSet)
            {
                return value;
            }
        }
        return default;
    }
}

public interface ILocalInputValuesProvider
{
    ControlValue GetControlValue(string control);
}

public struct ControlValue
{
    public bool IsSet;
    public bool BoolValue;
    public Vector2 Vector2Value;
    
    // Constructors for different value types
    public ControlValue(bool value) { ... }
    public ControlValue(Vector2 value) { ... }
}
```

This abstraction allows:
- Multiple input providers (keyboard/mouse, touch, gamepad, etc.)
- Seamless switching between different input methods
- Consistent interface for input consumers

## Simulation Input Processing

On the simulation side, the input is processed by various systems:

### Movement System

```csharp
public override void Update(Frame frame, ref Filter filter)
{
  if (filter.Status->IsDead) return;

  // Get player input
  QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
  
  // Apply input to KCC
  var config = frame.FindAsset(filter.KCC->Config);
  filter.KCC->Input = input;
  config.Move(frame, filter.Entity, filter.Transform, filter.KCC);
  
  // Update facing direction
  filter.MovementData->IsFacingRight = input.AimDirection.X > FP._0;
}
```

### Weapon System

```csharp
private void UpdateWeaponFire(Frame frame, ref Filter filter)
{
  // Get current weapon data
  var currentWeaponIndex = filter.WeaponInventory->CurrentWeaponIndex;
  var currentWeapon = filter.WeaponInventory->Weapons.GetPointer(currentWeaponIndex);
  var weaponData = frame.FindAsset(currentWeapon->WeaponData);

  // Get player input
  QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
  
  // Process fire input
  if (input.Fire)
  {
    // Check if weapon can fire
    if (currentWeapon->FireRateTimer.IsRunning(frame) == false 
        && !currentWeapon->IsRecharging 
        && currentWeapon->CurrentAmmo > 0)
    {
      SpawnBullet(frame, filter.Entity, currentWeapon, input.AimDirection);
      currentWeapon->FireRateTimer = FrameTimer.FromSeconds(frame, FP._1 / weaponData.FireRate);
    }
  }
}
```

### Weapon Inventory System

```csharp
public override void Update(Frame frame, ref Filter filter)
{
  if (filter.Status->IsDead) return;

  // Get player input
  QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
  
  // Process weapon switch input
  if (input.Use.WasPressed)
  {
    // Toggle between weapons
    filter.WeaponInventory->CurrentWeaponIndex = 
      filter.WeaponInventory->CurrentWeaponIndex == 0 ? 1 : 0;
    
    // Trigger event
    frame.Events.OnWeaponChanged(filter.Entity, filter.WeaponInventory->CurrentWeaponIndex);
  }
}
```

### Skill Inventory System

```csharp
public override void Update(Frame frame, ref Filter filter)
{
  if (filter.Status->IsDead) return;

  // Get player input
  QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);

  // Process skill cast input
  if (filter.SkillInventory->CastRateTimer.IsRunning(frame) == false)
  {
    if (input.AltFire.WasPressed)
    {
      CastSkill(frame, ref filter, input.AimDirection);
    }
  }
}
```

## Button Extension Methods

The game adds button state checking extension methods to the input struct:

```csharp
public partial struct QuantumDemoInputPlatformer2D
{
    // Button state properties
    public bool WasPressed => IsDown && !WasDown;
    public bool WasReleased => !IsDown && WasDown;
    
    private bool IsDown;
    private bool WasDown;
    
    // Update button state
    public void Update(Frame frame, bool value)
    {
        WasDown = IsDown;
        IsDown = value;
    }
}
```

These extension methods allow detecting button press and release events.

## Best Practices for Input Handling

1. **Use abstraction layers**: Separate input providers from input consumers
2. **Handle platform differences**: Provide different input implementations for different platforms
3. **Convert to fixed point early**: Convert Unity floating-point values to Quantum fixed point as soon as possible
4. **Use deterministic flags**: Always set input with the `Repeatable` flag
5. **Process input in systems**: Keep input processing in Quantum systems, not in Unity scripts
6. **Add convenience methods**: Add extension methods to make input state checking easier
7. **Use button state properties**: Add properties like `WasPressed` and `WasReleased` for event detection
8. **Keep input structures small**: Minimize the size of input structures for bandwidth efficiency
9. **Provide aim assistance**: Help mobile players with aim assistance without breaking determinism
10. **Update local state**: Store input state in the view context for access by other view components

These practices ensure consistent, deterministic input handling across all platforms while providing a good user experience.
