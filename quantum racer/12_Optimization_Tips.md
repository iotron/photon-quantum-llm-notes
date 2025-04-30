# Quantum Racer 2.5D Optimization Tips

This document provides guidance on performance optimization for the Quantum Racer 2.5D game. Following these principles will help maintain smooth gameplay, especially in multiplayer scenarios.

## Deterministic Simulation Optimization

### 1. Component Access Patterns

Use the most efficient component access pattern for each situation:

```csharp
// GOOD: Fastest access when frequently accessing same component
if (f.Unsafe.TryGetPointer(entity, out Racer* racer))
{
    // Direct pointer access is fastest
    var config = f.FindAsset(racer->Config);
    racer->Energy -= damage;
}

// GOOD: For one-time safe access
if (f.TryGet(entity, out Racer racer))
{
    // Safe struct access
    var config = f.FindAsset(racer.Config);
}

// BAD: Repeated GetComponent calls
var racer1 = f.Get<Racer>(entity);  // Gets copy 1
var racer2 = f.Get<Racer>(entity);  // Gets copy 2
racer1.Energy -= damage;
f.Set(entity, racer1);  // Must manually update
```

### 2. System Filter Selection

Choose the right system filter for better performance:

```csharp
// GOOD: Filter with explicit component requirements
public class RacerSystem : SystemMainThreadFilter<RacerSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public PhysicsBody2D* Body;
        public Racer* Vehicle;
    }
}

// BAD: Filter entities manually in update
public class SlowSystem : SystemMainThread 
{
    public override void Update(Frame f)
    {
        // Manual filtering is slow
        var entities = f.GetEntityArray();
        foreach (var entity in entities)
        {
            if (f.Has<Racer>(entity) && f.Has<Transform2D>(entity))
            {
                // Process entity...
            }
        }
    }
}
```

### 3. Memory Allocation

Avoid runtime allocations in simulation code:

```csharp
// GOOD: Pre-allocate collections
public override void OnInit(Frame f)
{
    f.GetOrAddSingleton<RaceManager>();
    if (f.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
    {
        manager->Vehicles = f.AllocateList<EntityRef>();
    }
}

// BAD: Allocating collections during runtime
public override void Update(Frame f)
{
    // Avoid creating new collections each frame
    var newList = new List<EntityRef>();
    // ...
}
```

## Network Synchronization

### 1. Input Prediction Configuration

Optimize input settings in SessionConfig.asset:

```
InputDelayFrames: 2-3 frames for most games
PredictionFrames: 2-3 frames for smooth visual experience
RollbackFrames: 6-12 frames based on expected network conditions
```

### 2. Snapshot Optimization

Balance performance and bandwidth:

```
SnapshotSendRate: 20-30 per second (lower for larger player counts)
InputSendRate: 60 per second for responsive controls
```

### 3. Deterministic RNG

Always use the frame's RNG for random values:

```csharp
// GOOD: Use deterministic RNG
var randomIndex = f.Global->RngSession.Next(0, count);

// BAD: Using non-deterministic random
var randomIndex = UnityEngine.Random.Range(0, count); // NEVER do this!
```

## Physics Optimizations

### 1. Collision Layer Management

Properly configure physics layers to minimize collision checks:

```csharp
// Set specific collision layers
body->Layer = (byte)PhysicsLayer.Vehicle;

// Configure layer collision matrix in physics settings
// Vehicles collide with: Track, Obstacles, Vehicles, Triggers
// But not with: Effects, UI, etc.
```

### 2. Physics Body Types

Use appropriate body types:

```csharp
// Dynamic bodies for vehicles
body->IsKinematic = false;
body->Mass = 2;

// Kinematic bodies for moving platforms/obstacles
trigger->IsKinematic = true;
trigger->IsTrigger = false;

// Trigger volumes for checkpoints and modifiers
checkpoint->IsTrigger = true;
```

### 3. Efficient Collision Shapes

Choose optimal collision shapes:

```csharp
// For vehicles: Use circle or capsule shapes
var collider = new CircleCollider2D() {
    Center = FPVector2.Zero,
    Radius = FP._0_50
};

// For track pieces: Use box or polygon shapes
var trackCollider = new BoxCollider2D() {
    Size = new FPVector2(10, 1),
    Center = FPVector2.Zero
};

// For complex shapes: Use compound colliders
var compound = new CompoundCollider2D();
compound.Colliders = new List<Collider2D>() {
    new CircleCollider2D() { Center = new FPVector2(0, 1), Radius = FP._0_50 },
    new BoxCollider2D() { Center = FPVector2.Zero, Size = new FPVector2(2, 0.5) }
};
```

## View Synchronization

### 1. Prediction Area Management

Optimize network traffic with precise prediction areas:

```csharp
// In camera controller:
Game.SetPredictionArea(transform.position.ToFPVector3(), 20);

// This ensures only nearby entities are predicted in detail
```

### 2. Entity View Pooling

Implement object pooling for entity views:

```csharp
// In EntityViewPool.cs
private Dictionary<string, Queue<GameObject>> _pools = new Dictionary<string, Queue<GameObject>>();

public GameObject Get(string prefabPath, Transform parent)
{
    if (!_pools.TryGetValue(prefabPath, out var pool))
    {
        pool = new Queue<GameObject>();
        _pools[prefabPath] = pool;
    }

    GameObject obj;
    if (pool.Count > 0)
    {
        obj = pool.Dequeue();
        obj.SetActive(true);
    }
    else
    {
        var prefab = Resources.Load<GameObject>(prefabPath);
        obj = Instantiate(prefab);
    }
    
    obj.transform.SetParent(parent);
    return obj;
}

public void Return(string prefabPath, GameObject obj)
{
    obj.SetActive(false);
    if (!_pools.TryGetValue(prefabPath, out var pool))
    {
        pool = new Queue<GameObject>();
        _pools[prefabPath] = pool;
    }
    pool.Enqueue(obj);
}
```

### 3. LOD Implementation

Implement level of detail for distant vehicles:

```csharp
public class RacerLOD : QuantumEntityViewComponent
{
    public GameObject HighDetailModel;
    public GameObject MediumDetailModel;
    public GameObject LowDetailModel;
    
    private Transform _cameraTransform;
    
    public override void OnActivate(Frame frame)
    {
        _cameraTransform = Camera.main.transform;
    }
    
    public override void OnUpdateView()
    {
        var distance = Vector3.Distance(transform.position, _cameraTransform.position);
        
        HighDetailModel.SetActive(distance < 20f);
        MediumDetailModel.SetActive(distance >= 20f && distance < 50f);
        LowDetailModel.SetActive(distance >= 50f);
    }
}
```

## Asset Loading Optimization

### 1. Asset Bundle Configuration

Organize assets into logical bundles:

```
CarBundle: All vehicle models and configs
TrackBundle: All track pieces and textures
EffectsBundle: All particle effects and sounds
```

### 2. Asset Reference Structure

Structure assets to maximize reuse:

```csharp
// Config container referencing shared assets
public class RacingAssetsConfig : AssetObject
{
    public AssetRef<Material>[] CommonMaterials;
    public AssetRef<AudioClip>[] CommonSounds;
    public AssetRef<ParticleSystem>[] CommonEffects;
}
```

### 3. Addressable Asset System

Use Unity's Addressable Asset System for dynamic loading:

```csharp
// Load track dynamically
async void LoadTrack(string trackName)
{
    var trackHandle = Addressables.LoadAssetAsync<GameObject>(trackName);
    await trackHandle.Task;
    var track = trackHandle.Result;
    Instantiate(track);
}
```

## Performance Profiling

### 1. Quantum Profiling

Enable Quantum's built-in profiling:

```csharp
// In game startup code
QuantumRunner.StartGame(..., new RuntimeConfig {
    DebugFlags = DebugFlags.Profiling
});

// Access profiling data
void DisplayProfilingData()
{
    var game = QuantumRunner.Default.Game;
    var profiler = game.Frames.Verified.Profiler;
    
    Debug.Log($"Simulation time: {profiler.GetDataSafe(ProfilerDataType.Simulate).Average}ms");
    Debug.Log($"Physics time: {profiler.GetDataSafe(ProfilerDataType.Physics).Average}ms");
}
```

### 2. Network Statistics Monitoring

Monitor network performance:

```csharp
void DisplayNetworkStats()
{
    var game = QuantumRunner.Default.Game;
    var stats = game.NetworkStatistics;
    
    Debug.Log($"RTT: {stats.RTT}ms");
    Debug.Log($"Received: {stats.BytesReceived} bytes");
    Debug.Log($"Sent: {stats.BytesSent} bytes");
}
```

### 3. Frame Debugging

Debug specific frames when issues occur:

```csharp
public override void OnRollback(QuantumGame game)
{
    Debug.LogWarning($"Rollback occurred at frame {game.Frames.Predicted.Number}");
    
    // Dump frame data for analysis
    var dumpPath = $"frame_dump_{game.Frames.Predicted.Number}.json";
    game.DumpFrame(dumpPath, game.Frames.Predicted);
}
```

## Implementation Notes

- **Profile First**: Always identify bottlenecks before optimizing
- **Batch Processing**: Group similar operations for better performance
- **Memory Management**: Minimize allocation in performance-critical paths
- **Physics Layers**: Configure collision matrix to minimize unnecessary checks
- **Network Settings**: Balance prediction frames against input delay
- **Asset Loading**: Use asynchronous loading for non-critical assets
- **LOD Strategies**: Implement level of detail for distant objects
- **Entity Pooling**: Reuse entity views instead of creating/destroying
- **Validate Determinism**: Test with recorded inputs to ensure deterministic behavior
