# Unity Integration in Quantum Platform Shooter 2D

This document explains how the Platform Shooter 2D sample project integrates Quantum simulation with Unity for visualization and input handling.

## View-Simulation Separation

Quantum's architecture strictly separates the simulation (Quantum) from the view (Unity):

```
Simulation (Quantum) → Events → View (Unity)
             ↑           ↓
             └─ Input ───┘
```

This separation ensures:
- Deterministic simulation across all clients
- No Unity-specific code in the simulation
- Clear communication paths between layers

## View Context

The Platform Shooter 2D uses a custom view context to store shared view-side information:

```csharp
namespace PlatformShooter2D
{
  using Quantum;
  using UnityEngine;

  // Custom context available to all EntityViews
  public class CustomViewContext : QuantumContext
  {
    // Reference to the local player's character view
    public CharacterView LocalCharacterView;
    
    // Last known aim direction of the local player
    public Vector2 LocalCharacterLastDirection;
  }
}
```

The view context allows sharing information between different view components, such as providing the local character's view to the camera system.

## Entity View Components

The game uses Quantum's entity view system to connect entities with Unity GameObjects:

### Base QuantumEntityViewComponent

All view components inherit from `QuantumEntityViewComponent<CustomViewContext>`:

```csharp
namespace PlatformShooter2D
{
  using Quantum;
  using UnityEngine;

  public class CharacterView : QuantumEntityViewComponent<CustomViewContext>
  {
    public Transform Body;
    public Animator CharacterAnimator;
    [HideInInspector] public int LookDirection;

    private readonly Vector3 _rightRotation = Vector3.zero;
    private readonly Vector3 _leftRotation = new(0, 180, 0);
    private static readonly int IsFacingRight = Animator.StringToHash("IsFacingRight");

    public override void OnActivate(Frame frame)
    {
      // Set up local player reference if applicable
      PlayerLink playerLink = VerifiedFrame.Get<PlayerLink>(EntityRef);

      if (Game.PlayerIsLocal(playerLink.Player))
      {
        ViewContext.LocalCharacterView = this;
      }
    }

    public override void OnUpdateView()
    {
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
}
```

Key methods in entity view components:
- `OnActivate(Frame frame)`: Called when the entity view is first linked to a Quantum entity
- `OnUpdateView()`: Called every frame to update the visual representation
- `OnEntityDestroyed()`: Called when the linked entity is destroyed

### Component Access

View components can access Quantum component data in these ways:

```csharp
// Safe access with explicit frame reference
Transform2D transform = frame.Get<Transform2D>(EntityRef);

// Safe access using VerifiedFrame (ensures we have a valid frame)
Status status = VerifiedFrame.Get<Status>(EntityRef);

// Unsafe direct pointer access (for performance-critical code)
var kcc = frame.Unsafe.GetPointer<KCC2D>(EntityRef);
```

## Event Subscriptions

View components use Quantum's event system to receive notifications from the simulation:

```csharp
public class WeaponView : QuantumEntityViewComponent
{
    public ParticleSystem MuzzleFlash;
    
    public override void OnEnable()
    {
        // Subscribe to events
        QuantumEvent.Subscribe<EventOnWeaponShoot>(this, OnWeaponShoot);
    }
    
    private void OnWeaponShoot(EventOnWeaponShoot e)
    {
        if (e.Character == EntityRef)
        {
            // Play muzzle flash effect
            MuzzleFlash.Play();
        }
    }
    
    public override void OnDisable()
    {
        // Unsubscribe from events (automatic, but explicit here for clarity)
        QuantumEvent.UnsubscribeListener(this);
    }
}
```

Event subscription options:
- `once`: Event is received only once, then unsubscribed
- `onlyIfActiveAndEnabled`: Only received if the GameObject is active
- `runnerId`: Only for a specific runner instance
- `filter`: Custom filter function for event reception

## Character Animation

The `CharacterAnimatorObserver` bridges Quantum state to Unity's animation system:

```csharp
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

## Camera Integration

The `LocalPlayerCameraFollow` component controls the camera to follow the local player:

```csharp
public class LocalPlayerCameraFollow : MonoBehaviour
{
    public float SmoothTime = 0.3f;
    
    private Transform _target;
    private Vector3 _velocity = Vector3.zero;
    
    void Update()
    {
        if (CustomViewContext.Instance?.LocalCharacterView != null)
        {
            if (_target == null)
            {
                _target = CustomViewContext.Instance.LocalCharacterView.transform;
            }
            
            if (_target != null)
            {
                // Follow the target with smooth damping
                Vector3 targetPosition = new Vector3(
                    _target.position.x, 
                    _target.position.y, 
                    transform.position.z);
                    
                transform.position = Vector3.SmoothDamp(
                    transform.position, 
                    targetPosition, 
                    ref _velocity, 
                    SmoothTime);
            }
        }
    }
}
```

## Visual Effects

Visual effects are triggered through event handlers:

```csharp
// Simplified BulletFxController
public class BulletFxController : QuantumCallbacks
{
    public GameObject BulletHitPrefab;
    
    public override void OnEnable()
    {
        QuantumEvent.Subscribe<EventOnBulletDestroyed>(this, OnBulletDestroyed);
    }
    
    private void OnBulletDestroyed(EventOnBulletDestroyed e)
    {
        // Create hit effect at bullet position
        var hitEffect = Instantiate(
            BulletHitPrefab, 
            e.BulletPosition.ToUnityVector3(), 
            Quaternion.identity);
            
        // Destroy after delay
        Destroy(hitEffect, 2f);
    }
}
```

## Audio Integration

Audio is handled through a centralized `SfxController`:

```csharp
// Simplified SfxController
public class SfxController : MonoBehaviour
{
    public static SfxController Instance { get; private set; }
    
    public AudioClip ShootSound;
    public AudioClip HitSound;
    public AudioClip JumpSound;
    
    private AudioSource _audioSource;
    
    void Awake()
    {
        Instance = this;
        _audioSource = GetComponent<AudioSource>();
    }
    
    public void PlaySound(SoundType type)
    {
        switch (type)
        {
            case SoundType.Shoot:
                _audioSource.PlayOneShot(ShootSound);
                break;
            case SoundType.Hit:
                _audioSource.PlayOneShot(HitSound);
                break;
            case SoundType.Jump:
                _audioSource.PlayOneShot(JumpSound);
                break;
        }
    }
}
```

Character-specific audio is handled by dedicated components:

```csharp
public class CharacterAudioController : QuantumEntityViewComponent
{
    public AudioSource AudioSource;
    
    public AudioClip DamageSound;
    public AudioClip DeathSound;
    
    public override void OnEnable()
    {
        QuantumEvent.Subscribe<EventOnCharacterDamaged>(this, OnCharacterDamaged);
        QuantumEvent.Subscribe<EventOnCharacterDied>(this, OnCharacterDied);
    }
    
    private void OnCharacterDamaged(EventOnCharacterDamaged e)
    {
        if (e.Character == EntityRef)
        {
            AudioSource.PlayOneShot(DamageSound);
        }
    }
    
    private void OnCharacterDied(EventOnCharacterDied e)
    {
        if (e.Character == EntityRef)
        {
            AudioSource.PlayOneShot(DeathSound);
        }
    }
}
```

## UI Integration

The game includes various UI components that observe Quantum state:

### Player UI

```csharp
public class PlayerUI : QuantumEntityViewComponent
{
    public Image HealthBar;
    
    public override void OnUpdateView()
    {
        if (EntityRef.IsValid)
        {
            Status status = VerifiedFrame.Get<Status>(EntityRef);
            var statusData = frame.FindAsset(status.StatusData);
            
            // Update health bar
            float healthPercent = status.CurrentHealth.AsFloat / statusData.MaxHealth.AsFloat;
            HealthBar.fillAmount = healthPercent;
        }
    }
}
```

### Weapon HUD

```csharp
public class ChangeWeaponHud : QuantumEntityViewComponent
{
    public Image[] WeaponIcons;
    
    public override void OnEnable()
    {
        QuantumEvent.Subscribe<EventOnWeaponChanged>(this, OnWeaponChanged);
    }
    
    private void OnWeaponChanged(EventOnWeaponChanged e)
    {
        if (e.Character == EntityRef)
        {
            // Update weapon icons
            for (int i = 0; i < WeaponIcons.Length; i++)
            {
                WeaponIcons[i].color = (i == e.WeaponIndex) ? Color.white : Color.gray;
            }
        }
    }
}
```

## Entity Prototype Integration

Entity prototypes are defined in Unity and used by Quantum:

1. Create a GameObject with desired components
2. Add `QuantumEntityPrototype` component
3. Configure Quantum components in the Inspector
4. Create a prefab from the GameObject
5. Reference the prefab in simulation code

The `EntityPrototypeLinker` automatically links Unity prefabs to Quantum entities during instantiation.

## Unity Utils Extensions

The project includes utility extension methods to convert between Unity and Quantum types:

```csharp
// Extension methods
public static class QuantumUnityExtensions
{
    public static Vector2 ToUnityVector2(this FPVector2 vector)
    {
        return new Vector2(vector.X.AsFloat, vector.Y.AsFloat);
    }
    
    public static Vector3 ToUnityVector3(this FPVector2 vector)
    {
        return new Vector3(vector.X.AsFloat, vector.Y.AsFloat, 0);
    }
    
    public static FPVector2 ToFPVector2(this Vector2 vector)
    {
        return new FPVector2(FP.FromFloat_UNSAFE(vector.x), FP.FromFloat_UNSAFE(vector.y));
    }
    
    public static FPVector2 ToFPVector2(this Vector3 vector)
    {
        return new FPVector2(FP.FromFloat_UNSAFE(vector.x), FP.FromFloat_UNSAFE(vector.y));
    }
}
```

## Best Practices for Unity Integration

1. **Keep simulation and view separate**: Never reference Unity types in simulation code
2. **Use events for communication**: Use events to notify the view about simulation changes
3. **Use entity view components**: Extend `QuantumEntityViewComponent` for entity-linked behavior
4. **Centralize common functionality**: Use a custom ViewContext to share information
5. **Use safe access patterns**: Use `VerifiedFrame` for component access
6. **Handle entity destruction**: Properly clean up resources in `OnEntityDestroyed`
7. **Pool frequently created objects**: Use object pooling for effects and projectiles
8. **Use extension methods**: Create extensions for type conversion between Unity and Quantum
9. **Access components efficiently**: Use appropriate access patterns based on performance requirements
10. **Use entity prototype linker**: Automatically link Unity prefabs to Quantum entities

These practices ensure clean separation between simulation and view while maintaining visual fidelity and performance.
