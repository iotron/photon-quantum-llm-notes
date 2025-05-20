# Unity Integration

Quantum is designed to work with Unity, providing a seamless integration between the deterministic simulation and Unity's rendering and input systems. This document explains how Quantum integrates with Unity and how to implement Unity-side components that work with Quantum.

## Core Integration Components

### QuantumRunnerBehaviour

The `QuantumRunnerBehaviour` is the main MonoBehaviour that manages the Quantum simulation in Unity:

```csharp
public class QuantumRunnerBehaviour : QuantumMonoBehaviour 
{
    public QuantumRunner Runner;
    
    // Update the Quantum simulation every frame
    public void Update() {
        Runner?.Update();
    }
    
    // Handle debug drawing
    public void OnPostRenderInternal(Camera camera) {
        if (Runner == null || Runner.Session == null || Runner.HideGizmos) {
            return;
        }
        
        DebugDraw.OnPostRender();
    }
}
```

### QuantumEntityView

The `QuantumEntityView` class connects Unity GameObjects to Quantum entities:

```csharp
public class QuantumEntityView : MonoBehaviour 
{
    public EntityRef EntityRef;
    public string EntityViewName;
    
    // Called when the entity view is activated
    public virtual void OnActivate(Frame frame) {
        // Override this to initialize your entity view
    }
    
    // Called every Unity frame to update the view
    public virtual void OnUpdateView() {
        // Override this to update your entity view
    }
    
    // Get a predicted component from the entity
    public T GetPredictedQuantumComponent<T>() where T : unmanaged, IComponent {
        // Returns the component from the predicted frame
    }
}
```

## Unity-Side View Components

View components in Unity update visual representations based on Quantum simulation data:

```csharp
public class CharacterView : QuantumEntityViewComponent
{
    private Animator _animator;
    private Transform _modelTransform;
    
    public override void OnActivate(Frame frame) {
        _animator = GetComponentInChildren<Animator>();
        _modelTransform = transform.Find("Model");
    }
    
    public override void OnUpdateView() {
        // Get transform data from Quantum
        var transform3D = GetPredictedQuantumComponent<Transform3D>();
        if (transform3D != null) {
            // Update Unity transform to match Quantum
            this.transform.position = transform3D.Position.ToUnityVector3();
            this.transform.rotation = transform3D.Rotation.ToUnityQuaternion();
        }
        
        // Get KCC data for animation
        var kcc = GetPredictedQuantumComponent<KCC>();
        if (kcc != null && _animator != null) {
            // Update animator parameters
            _animator.SetBool("IsGrounded", kcc.IsGrounded);
            _animator.SetFloat("Speed", kcc.Data.CharacterVelocity.Magnitude.AsFloat);
        }
    }
}
```

## Input Collection

Unity-side components collect player input and send it to Quantum:

```csharp
public class PlayerInput : QuantumEntityViewComponent
{
    private Quantum.Input _input;
    
    public override void OnActivate(Frame frame) {
        var playerLink = GetPredictedQuantumComponent<PlayerLink>();
        if (Game.PlayerIsLocal(playerLink.PlayerRef) == false) {
            enabled = false;
            return;
        }
        
        // Register to input poll callback
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }
    
    public override void OnUpdateView() {
        // Accumulate input from Unity
        var lookRotationDelta = new Vector2(-Input.GetAxisRaw("Mouse Y"), Input.GetAxisRaw("Mouse X"));
        _input.LookRotation = ClampLookRotation(_input.LookRotation + lookRotationDelta.ToFPVector2());
        
        var moveDirection = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
        _input.MoveDirection = moveDirection.normalized.ToFPVector2();
        
        _input.Fire = Input.GetButton("Fire1");
        _input.Jump = Input.GetButton("Jump");
        _input.Sprint = Input.GetButton("Sprint");
    }
    
    private void PollInput(CallbackPollInput callback) {
        // Send input to Quantum
        callback.SetInput(_input, DeterministicInputFlags.Repeatable);
    }
}
```

## Entity View Creation and Management

The `QuantumEntityViewUpdater` manages entity view creation and destruction:

```csharp
public class QuantumEntityViewUpdater : MonoBehaviour 
{
    public Dictionary<EntityRef, QuantumEntityView> EntityViews = new Dictionary<EntityRef, QuantumEntityView>();
    
    // Create views for entities
    private void OnEntityCreated(EntityViewCreationContext ctx) {
        // Find asset for the entity
        var prototype = ctx.FindAsset<EntityViewAsset>(ctx.EntityRef);
        if (prototype != null) {
            // Instantiate prefab
            var prefab = prototype.Prefab;
            var instance = Instantiate(prefab);
            
            // Set up entity view
            var view = instance.GetComponent<QuantumEntityView>();
            view.EntityRef = ctx.EntityRef;
            
            // Add to dictionary
            EntityViews.Add(ctx.EntityRef, view);
            
            // Activate the view
            view.OnActivate(ctx.PredictedFrame);
        }
    }
    
    // Remove views for destroyed entities
    private void OnEntityDestroyed(EntityViewDestructionContext ctx) {
        if (EntityViews.TryGetValue(ctx.EntityRef, out var view)) {
            EntityViews.Remove(ctx.EntityRef);
            Destroy(view.gameObject);
        }
    }
}
```

## Event Handling

Unity-side components can subscribe to Quantum events:

```csharp
public class EventHandler : MonoBehaviour 
{
    // Audio sources
    public AudioSource JumpSound;
    public AudioSource LandSound;
    
    void Start() {
        // Subscribe to events
        QuantumEvent.Subscribe<EventJumped>(this, OnJumped);
        QuantumEvent.Subscribe<EventLanded>(this, OnLanded);
    }
    
    void OnDestroy() {
        // Unsubscribe from events
        QuantumEvent.UnsubscribeListener<EventJumped>(this);
        QuantumEvent.UnsubscribeListener<EventLanded>(this);
    }
    
    private void OnJumped(EventJumped jumpEvent) {
        // Find view for entity
        var view = QuantumRunner.Default.Game.Frames.Predicted
            .FindViewForEntity(jumpEvent.Entity);
            
        // Play sound
        if (view != null) {
            JumpSound.Play();
        }
    }
    
    private void OnLanded(EventLanded landEvent) {
        // Find view for entity
        var view = QuantumRunner.Default.Game.Frames.Predicted
            .FindViewForEntity(landEvent.Entity);
            
        // Play sound
        if (view != null) {
            LandSound.Play();
        }
    }
}
```

## Unity GameObject to Quantum Entity Conversion

Unity GameObjects can be converted to Quantum entities at runtime:

```csharp
public class EntityPrototypeConverter : MonoBehaviour 
{
    public EntityPrototypeRef PrototypeRef;
    
    // Convert this GameObject to a Quantum entity
    public void ConvertToQuantumEntity() {
        var position = transform.position.ToFPVector3();
        var rotation = transform.rotation.ToFPQuaternion();
        
        // Create entity
        var entityRef = QuantumRunner.Default.Game.Frames.Predicted
            .Create(PrototypeRef, position, rotation);
            
        // Associate with this GameObject
        var view = GetComponent<QuantumEntityView>();
        if (view != null) {
            view.EntityRef = entityRef;
            QuantumRunner.Default.Game.EntityViews.AddView(entityRef, view);
        }
    }
}
```

## Map Loading

Quantum maps can be loaded from Unity scenes:

```csharp
public class QuantumMapLoader : MonoBehaviour 
{
    public void LoadQuantumMap(AssetRef<Map> mapRef) {
        // Create RuntimeConfig
        var config = new RuntimeConfig();
        config.Map = mapRef;
        config.Seed = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
        
        // Start Quantum game
        QuantumRunner.StartGame(new SessionRunner.Arguments {
            GameMode = DeterministicGameMode.Local,
            RunnerId = "LocalDebug",
            RuntimeConfig = config,
            PlayerCount = 1
        });
    }
}
```

## Asset Linking

Quantum assets are linked to Unity assets through asset references:

```csharp
// Define an asset reference in a MonoBehaviour
public class WeaponController : MonoBehaviour 
{
    public AssetRef<WeaponPrototype> WeaponRef;
    
    public void FireWeapon() {
        var frame = QuantumRunner.Default.Game.Frames.Predicted;
        var weaponAsset = frame.FindAsset<WeaponPrototype>(WeaponRef);
        
        // Use the weapon asset
        if (weaponAsset != null) {
            // ... weapon logic
        }
    }
}
```

## FP (Fixed-Point) Math Conversion

Quantum uses fixed-point math for determinism, requiring conversion with Unity's floating-point:

```csharp
// Convert Unity Vector3 to Quantum FPVector3
FPVector3 quantumPosition = unityPosition.ToFPVector3();

// Convert Quantum FPVector3 to Unity Vector3
Vector3 unityPosition = quantumPosition.ToUnityVector3();

// Convert Unity Quaternion to Quantum FPQuaternion
FPQuaternion quantumRotation = unityRotation.ToFPQuaternion();

// Convert Quantum FPQuaternion to Unity Quaternion
Quaternion unityRotation = quantumRotation.ToUnityQuaternion();
```

## Game Startup

Starting a Quantum game from Unity:

```csharp
public class GameStarter : MonoBehaviour 
{
    public MapAsset MapAsset;
    
    public void StartLocalGame() {
        // Create RuntimeConfig
        var config = new RuntimeConfig();
        config.Map = MapAsset.AssetRef;
        config.Seed = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
        
        // Start Quantum game
        QuantumRunner.StartGame(new SessionRunner.Arguments {
            GameMode = DeterministicGameMode.Local,
            RunnerId = "LocalDebug",
            RuntimeConfig = config,
            PlayerCount = 1,
            DeltaTimeType = SimulationUpdateTime.EngineDeltaTime
        });
    }
    
    public void StartMultiplayerGame() {
        // Create RuntimeConfig
        var config = new RuntimeConfig();
        config.Map = MapAsset.AssetRef;
        config.Seed = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
        
        // Start Quantum game
        QuantumRunner.StartGame(new SessionRunner.Arguments {
            GameMode = DeterministicGameMode.MultiplayerServer,
            RunnerId = "Server",
            RuntimeConfig = config,
            PlayerCount = 4,
            DeltaTimeType = SimulationUpdateTime.EngineDeltaTime
        });
    }
}
```

## Debug Visualization

Quantum provides debug visualization tools in Unity:

```csharp
// Enable debug drawing in QuantumGameGizmosSettings
public class DebugVisualizer : MonoBehaviour 
{
    public void EnableDebugVisuals() {
        var settings = QuantumGameGizmosSettingsScriptableObject.Global.Settings;
        settings.DebugDraw.Physics3D.DrawColliders = true;
        settings.DebugDraw.Physics3D.DrawContacts = true;
        settings.DebugDraw.Physics3D.DrawRaycasts = true;
        settings.DebugDraw.NavMesh.DrawPathfinderPath = true;
    }
}
```

## Best Practices

1. **Keep simulation and view separated**: Let Quantum handle all game logic, while Unity handles visualization
2. **Use QuantumEntityViewComponent for views**: Extend this class for all entity views for consistency
3. **Convert between Unity and Quantum vectors carefully**: Always use the provided conversion methods
4. **Use events for communication**: Communicate from Quantum to Unity using events
5. **Cache components in OnActivate**: Get and store references to Unity components for performance
6. **Use interpolation for smoother visuals**: Interpolate between physics frames for smoother rendering
7. **Handle local vs. remote players appropriately**: Disable input collection for remote players
8. **Handle entity lifecycle properly**: Create and destroy Unity objects to match Quantum entities

By following these integration patterns, you can create a clean separation between Quantum's deterministic simulation and Unity's rendering and input systems, leading to more maintainable and robust multiplayer games.
