# Physics in Quantum

Quantum includes a deterministic physics engine that works consistently across all clients. This document explains how to use Quantum's physics systems for both 2D and 3D games.

## Core Physics Concepts

Quantum's physics engine is:

- Fully deterministic (same inputs produce same outputs on all machines)
- Available in both 2D and 3D variants
- Completely separate from Unity's physics
- Built for performance and network synchronization

## Physics Components

### 2D Physics Components

Quantum provides several 2D physics components:

#### PhysicsCollider2D

Base component for all 2D colliders:

```csharp
// Add a 2D box collider
var collider = frame.AddComponent<PhysicsCollider2D>(entity);
collider->Shape = Shape2D.CreateBox(FP._0_5, FP._0_5);

// Add a 2D circle collider
var collider = frame.AddComponent<PhysicsCollider2D>(entity);
collider->Shape = Shape2D.CreateCircle(FP._0_5);

// Add a 2D polygon collider
var collider = frame.AddComponent<PhysicsCollider2D>(entity);
collider->Shape = Shape2D.CreatePolygon(vertices);
```

#### PhysicsBody2D

Represents a dynamic rigid body in 2D:

```csharp
// Add a 2D physics body
var body = frame.AddComponent<PhysicsBody2D>(entity);
body->Mass = 1;
body->Drag = FP._0_1;
body->AngularDrag = FP._0_05;
body->GravityScale = FP._1;
body->Layer = 0;
body->IsTrigger = false;
body->IsKinematic = false;
```

### 3D Physics Components

Quantum also provides 3D physics components:

#### PhysicsCollider3D

Base component for all 3D colliders:

```csharp
// Add a 3D box collider
var collider = frame.AddComponent<PhysicsCollider3D>(entity);
collider->Shape = Shape3D.CreateBox(FP._0_5, FP._1, FP._0_5);

// Add a 3D sphere collider
var collider = frame.AddComponent<PhysicsCollider3D>(entity);
collider->Shape = Shape3D.CreateSphere(FP._0_5);

// Add a 3D capsule collider
var collider = frame.AddComponent<PhysicsCollider3D>(entity);
collider->Shape = Shape3D.CreateCapsule(FP._0_5, FP._1);
```

#### PhysicsBody3D

Represents a dynamic rigid body in 3D:

```csharp
// Add a 3D physics body
var body = frame.AddComponent<PhysicsBody3D>(entity);
body->Mass = 1;
body->Drag = FP._0_1;
body->AngularDrag = FP._0_05;
body->GravityScale = FP._1;
body->Layer = 0;
body->IsTrigger = false;
body->IsKinematic = false;
```

### Kinematic Character Controller (KCC)

Quantum provides specialized Kinematic Character Controllers for both 2D and 3D:

```csharp
// Add a 3D KCC
var kcc = frame.AddComponent<KCC>(entity);
kcc->Config = frame.FindAsset<KCCConfig>("DefaultKCCConfig");
```

## Physics API

### Physics Access

Physics is accessed through the Frame object:

```csharp
// Access 2D physics
frame.Physics2D.Raycast(origin, direction, length, layerMask);

// Access 3D physics
frame.Physics3D.Raycast(origin, direction, length, layerMask);
```

### Common Physics Operations

#### Raycasts

```csharp
// 2D raycast
RaycastHit2D hit;
if (frame.Physics2D.Raycast(origin, direction, length, layerMask, out hit)) {
    // Hit something
    var hitEntity = hit.Entity;
    var hitPoint = hit.Point;
    var hitNormal = hit.Normal;
}

// 3D raycast
RaycastHit3D hit;
if (frame.Physics3D.Raycast(origin, direction, length, layerMask, out hit)) {
    // Hit something
    var hitEntity = hit.Entity;
    var hitPoint = hit.Point;
    var hitNormal = hit.Normal;
}
```

#### Overlaps

```csharp
// 2D circle overlap
var results = frame.Physics2D.OverlapCircle(center, radius, layerMask);
foreach (var hit in results) {
    // Process each overlapping entity
}

// 3D sphere overlap
var results = frame.Physics3D.OverlapSphere(center, radius, layerMask);
foreach (var hit in results) {
    // Process each overlapping entity
}
```

#### Forces

```csharp
// Apply force to 2D body
var body = frame.Get<PhysicsBody2D>(entity);
frame.Physics2D.AddForce(body, force, forceMode);

// Apply force to 3D body
var body = frame.Get<PhysicsBody3D>(entity);
frame.Physics3D.AddForce(body, force, forceMode);
```

## Collision Detection

### Collision Signals

Quantum uses signals for collision callbacks:

```csharp
// Implement collision callbacks
public class CollisionHandlerSystem : SystemBase, 
    ISignalOnCollisionEnter3D, 
    ISignalOnCollisionExit3D, 
    ISignalOnTriggerEnter3D, 
    ISignalOnTriggerExit3D
{
    public void OnCollisionEnter3D(Frame f, CollisionInfo3D info) {
        // Handle collision enter
        var entityA = info.EntityA;
        var entityB = info.EntityB;
        var point = info.Points[0].Position;
    }

    public void OnCollisionExit3D(Frame f, ExitInfo3D info) {
        // Handle collision exit
        var entityA = info.EntityA;
        var entityB = info.EntityB;
    }

    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info) {
        // Handle trigger enter
        var entityA = info.Entity;
        var entityB = info.Other;
    }

    public void OnTriggerExit3D(Frame f, ExitInfo3D info) {
        // Handle trigger exit
        var entityA = info.EntityA;
        var entityB = info.EntityB;
    }
}
```

### Collision Layers and Masks

Physics layers control which objects can collide:

```csharp
// Set up physics layer
var body = frame.Get<PhysicsBody3D>(entity);
body->Layer = PhysicsLayers.Player;

// Set up collision mask (which layers this object collides with)
var collider = frame.Get<PhysicsCollider3D>(entity);
collider->LayerMask = PhysicsLayers.Default | PhysicsLayers.Environment;
```

## Physics Configuration

Physics behavior is configured in the SimulationConfig:

```csharp
// In SimulationConfig asset
config.Physics.Gravity2D = new FPVector2(0, -10);
config.Physics.Gravity3D = new FPVector3(0, -10, 0);
config.Physics.SimulationIterations = 3;
config.Physics.SleepThreshold = FP._0_01;
```

## Character Controller Implementation

The Kinematic Character Controller (KCC) provides ready-to-use character movement:

```csharp
// Update character movement in a system
public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public PlayerLink* PlayerLink;
        public Transform3D* Transform;
        public KCC* KCC;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        var input = frame.GetPlayerInput(filter.PlayerLink->PlayerRef);
        
        // Convert input direction to world space
        var lookRotation = FPQuaternion.Euler(0, input->LookRotation.Y, 0);
        var moveDirection = lookRotation * new FPVector3(input->MoveDirection.X, 0, input->MoveDirection.Y);
        
        // Set character rotation
        filter.KCC->SetLookRotation(input->LookRotation.X, input->LookRotation.Y);
        
        // Apply movement
        filter.KCC->SetInputDirection(moveDirection);
        
        // Handle jumping
        if (input->Jump.WasPressed && filter.KCC->IsGrounded)
        {
            filter.KCC->Jump(FPVector3.Up * 10);
            frame.Events.Jumped(filter.Entity);
        }
    }
}
```

## Static Colliders

For environments, static colliders can be created from Unity colliders:

```csharp
// Unity component for static box collider
public class QuantumStaticBoxCollider3D : MonoBehaviour
{
    public FPVector3 Size = FPVector3.One;
    public FPVector3 Center = FPVector3.Zero;
    public PhysicsColliderSettings Settings = new PhysicsColliderSettings();
}
```

These static colliders are automatically converted to Quantum physics colliders when the map is loaded.

## Debugging Physics

Quantum provides visualization tools for physics debugging:

```csharp
// Enable physics debugging in QuantumGameGizmosSettings
settings.DebugDraw.Physics3D.DrawColliders = true;
settings.DebugDraw.Physics3D.DrawContacts = true;
settings.DebugDraw.Physics3D.DrawRaycasts = true;
```

## Best Practices

1. **Avoid mixing Unity and Quantum physics**: Keep all gameplay physics in Quantum for determinism
2. **Use appropriate collision layers**: Organize your physics objects into logical layers
3. **Tune your physics parameters**: Adjust iteration counts, gravity, etc. for your game's needs
4. **Use the KCC for characters**: The built-in KCC handles most character movement cases
5. **Keep physics shapes simple**: Simpler shapes are more performant and stable
6. **Avoid zero-thickness colliders**: They can cause stability issues
7. **Use physics callbacks judiciously**: Only register for the callbacks you need

Quantum's deterministic physics system provides a solid foundation for multiplayer games, ensuring consistent behavior across all clients and eliminating physics-related desynchronization issues.
