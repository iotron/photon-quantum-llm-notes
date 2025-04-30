# Movement System in Quantum Platform Shooter 2D

This document explains the implementation of the Movement System in the Platform Shooter 2D sample project, focusing on the 2D platformer controls and character movement.

## Movement Components

The movement system relies on several components:

```qtn
// Character.qtn
component MovementData
{
    Boolean IsFacingRight;
}
```

Additionally, the movement system uses built-in Quantum components:
- `Transform2D`: Handles position and rotation
- `KCC2D`: Kinematic Character Controller for 2D movement, manages platformer physics
- `PhysicsCollider2D`: For collision detection

## Movement System Implementation

The `MovementSystem` handles character movement based on player input:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;
  
  [Preserve]
  public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>
  {
    public struct Filter
    {
      public EntityRef Entity;
      public Transform2D* Transform;
      public PlayerLink* PlayerLink;
      public Status* Status;
      public MovementData* MovementData;
      public KCC2D* KCC;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
      // Skip movement for dead characters
      if (filter.Status->IsDead == true)
      {
        return;
      }

      // Get player input
      QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
      
      // Get KCC configuration
      var config = frame.FindAsset(filter.KCC->Config);
      
      // Apply input to the KCC
      filter.KCC->Input = input;
      
      // Process movement through KCC system
      config.Move(frame, filter.Entity, filter.Transform, filter.KCC);
      
      // Update facing direction
      UpdateIsFacingRight(frame, ref filter, input);
    }

    private void UpdateIsFacingRight(Frame frame, ref Filter filter, QuantumDemoInputPlatformer2D input)
    {
      // Update facing direction based on aim
      filter.MovementData->IsFacingRight = input.AimDirection.X > FP._0;
    }
  }
}
```

Key aspects:
1. Filter selects entities with all required components
2. Retrieve player input for the associated player
3. Pass input to the KCC2D component
4. Call the KCC's Move method to handle the actual movement
5. Update the facing direction based on aim input

## KCC2D Configuration

The KCC2D (Kinematic Character Controller) is configured through an asset:

```csharp
// Simplified KCC2D configuration
public class KCCSettings2D : AssetObject
{
    // Movement parameters
    public FP AccelerationGround;
    public FP AccelerationAir;
    public FP MaxSpeedGround;
    public FP MaxSpeedAir;
    
    // Jump parameters
    public FP JumpVelocity;
    public int MaxJumpCount;
    public FP JumpCooldown;
    
    // Gravity parameters
    public FP GravityFallMultiplier;
    public FP GravityMultiplier;
    
    // Physics parameters
    public FP GroundedTolerance;
    public FP SkinWidth;
    
    // Additional parameters
    public LayerMask GroundLayers;
    public Boolean AllowJumpingWhenSliding;
    public Boolean ResetJumpCountOnGround;
    
    public void Move(Frame frame, EntityRef entity, Transform2D* transform, KCC2D* kcc) {
        // Implementation handles the actual movement logic
        // ...
    }
}
```

## Input Structure

The movement system uses a specialized input structure:

```csharp
// Defined in Input.User.cs
public struct QuantumDemoInputPlatformer2D
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

## Input Handling

The input is collected from the Unity side using the `LocalQuantumInputPoller` component:

```csharp
namespace PlatformShooter2D
{
  using Photon.Deterministic;
  using UnityEngine;
  using QuantumMobileInputTools;
  using Quantum;

  public class LocalQuantumInputPoller : QuantumEntityViewComponent<CustomViewContext>
  {
    // ... other fields
    
    public void PollInput(CallbackPollInput callback)
    {
      QuantumDemoInputPlatformer2D input = default;

      if (callback.Game.GetLocalPlayers().Count == 0)
      {
        return;
      }
      
      var control = QuantumLocalInputValuesControl.Instance;

      // Get input from UI controls
      input.Fire = control.GetControlValue(ControlMap.Fire).BoolValue;
      
      // Handle mobile-specific input
#if UNITY_MOBILE || UNITY_ANDROID
      var aimDirection = control.GetControlValue(ControlMap.Aim).Vector2Value;
      input.Fire = (aimDirection.magnitude >= 0.5f);
#endif

      // Get horizontal movement
      var movement = GetMovement();
      input.Left = movement < 0;
      input.Right = movement > 0;

      // Get other inputs
      input.Jump = control.GetControlValue(ControlMap.Jump).BoolValue;
      input.AimDirection = GetAimDirection();
      input.Use = control.GetControlValue(ControlMap.ChangeWeapon).BoolValue;
      input.AltFire = control.GetControlValue(ControlMap.CastSkill).BoolValue;

      // Send input to Quantum
      callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }

    private FP GetMovement()
    {
      var control = QuantumLocalInputValuesControl.Instance;
      FPVector2 directional = control.GetControlValue(ControlMap.Move).Vector2Value.ToFPVector2();
      return directional.X;
    }

    // ... other methods including GetAimDirection()
  }
}
```

The input polling process:
1. Subscribes to Quantum's `CallbackPollInput` event
2. Collects input from Unity's input system
3. Handles platform-specific input differences (mobile vs. desktop)
4. Converts Unity vectors to Quantum's fixed point vectors
5. Sends the input to Quantum with the `Repeatable` flag to ensure determinism

## Character View Integration

The view side updates the character's visual representation based on the movement state:

```csharp
public class CharacterView : QuantumEntityViewComponent<CustomViewContext>
{
  // ... other fields and methods
  
  public override void OnUpdateView()
  {
    // Get the facing direction from animator parameter
    if (CharacterAnimator.GetBool(IsFacingRight))
    {
      // Rotate to face right
      Body.localRotation = Quaternion.Euler(_rightRotation);
      LookDirection = 1;
    }
    else
    {
      // Rotate to face left
      Body.localRotation = Quaternion.Euler(_leftRotation);
      LookDirection = -1;
    }
  }
}
```

## Animation Control

The character's animations are driven by the `CharacterAnimatorObserver`:

```csharp
// Simplified CharacterAnimatorObserver
public class CharacterAnimatorObserver : QuantumEntityViewComponent
{
  public Animator Animator;
  private static readonly int IsGrounded = Animator.StringToHash("IsGrounded");
  private static readonly int IsFacingRight = Animator.StringToHash("IsFacingRight");
  private static readonly int IsMoving = Animator.StringToHash("IsMoving");
  private static readonly int IsJumping = Animator.StringToHash("IsJumping");
  private static readonly int IsDead = Animator.StringToHash("IsDead");

  public override void OnUpdateView()
  {
    // Get components from the simulation
    KCC2D kcc = VerifiedFrame.Get<KCC2D>(EntityRef);
    Status status = VerifiedFrame.Get<Status>(EntityRef);
    MovementData movementData = VerifiedFrame.Get<MovementData>(EntityRef);
    
    // Update animator parameters based on simulation state
    Animator.SetBool(IsGrounded, kcc.Grounded);
    Animator.SetBool(IsFacingRight, movementData.IsFacingRight);
    Animator.SetBool(IsMoving, Mathf.Abs(kcc.Velocity.X.AsFloat) > 0.1f);
    Animator.SetBool(IsJumping, kcc.Velocity.Y.AsFloat > 0);
    Animator.SetBool(IsDead, status.IsDead);
  }
}
```

## Physics Integration

The movement system leverages Quantum's deterministic physics engine:
- The `KCC2D` component handles platformer movement
- `PhysicsCollider2D` defines the collision shape
- Quantum's physics engine ensures deterministic collision detection and response

The KCC2D component handles advanced platformer features:
- Ground detection and slopes
- Jump mechanics including double jump
- Air control
- Variable jump height
- Collision resolution and sliding

## Best Practices for Movement Implementation

1. **Use KCC components**: Leverage Quantum's built-in Kinematic Character Controller
2. **Keep input simple**: Convert complex inputs to simple boolean and vector values
3. **Use fixed point math**: All calculations use Quantum's deterministic fixed point types
4. **Separate movement from visuals**: Keep movement logic in the simulation, visual representation in Unity
5. **Use asset references for configuration**: Store movement parameters in assets for easy tuning
6. **Handle platform-specific inputs**: Account for different input methods (keyboard/mouse vs. touch)
7. **Use filters for efficiency**: Only process entities that have all required components

These practices ensure deterministic movement behavior across all clients while maintaining flexibility and performance.
