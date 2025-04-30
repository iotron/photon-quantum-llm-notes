# Entity Prototypes

## Introduction

Quantum features entity prototypes to facilitate data-driven design.

A Quantum Entity Prototype is a serialized version of an entity that includes:
- **Composition**: which components it is made of
- **Data**: the components' properties and their initial values

This provides a clean separation of data and behavior, allowing designers to tweak data without programmers having to constantly edit code.

## Setting up a Prototype

Entity prototypes can be set up in the Unity Editor.

### Basic Setup

To create an entity prototype:
1. Add the `QuantumEntityPrototype` component to any GameObject

![Entity Prototype Script on an empty GameObjet](/docs/img/quantum/v3/manual/entityprototype-basic.png)

The `QuantumEntityPrototype` script allows setting up parameters for commonly used components for both 2D and 3D:
- Transform (including Transform2DVertical for 2D)
- PhysicsCollider
- PhysicsBody
- NavMeshPathFinder
- NavMeshSteeringAgent
- NavMeshAvoidanceAgent

Dependencies for Physics and NavMesh related agents are respected. Refer to their respective documentation for more details.

### Custom Components

Additional components can be added to entity prototypes in two ways:
- Using the **+** button in the `Entity Components` list
- Using the regular Unity *Add Component* button and searching for the appropriate `QPrototype` component

#### Note on Collections

Dynamic collections in components are only automatically allocated **IF** there is at least one item in the prototype. Otherwise, the collection must be allocated manually. See the [Dynamics Collection entry on the DSL page](/quantum/current/manual/quantum-ecs/dsl#dynamic_collections) for more information.

### Hierarchy

In ECS, the concept of entity/GameObject hierarchy does not exist. Entity prototypes don't support hierarchies or nesting.

Although child prototypes aren't directly supported, you can:
1. Create separate prototypes in the scene and bake them
2. Link them by keeping a reference in a component
3. Update the position of the "child" manually

*Note:* Prototypes that aren't baked in scene must follow a different workflow where entities are created and linked in code.

It's possible to have hierarchies in game objects (View), but hierarchies in entities (Simulation) must be handled manually.

## Creating/Instantiating a Prototype

Once an entity prototype is defined in Unity, there are several ways to include it in the simulation.

### Baked in the Scene/Map

If the entity prototype is created as part of a Unity Scene:
- It will be baked into the corresponding Map Asset
- The baked entity prototype will be loaded when the Map is initialized with its baked values

**Note:** If a Scene's entity prototype is edited or has its values changed, the Map Data must be re-baked (which might happen automatically during some editor actions like saving the project, depending on the project setup).

### In Code

To create a new entity from a `QuantumEntityPrototype`:

1. Create a Unity Prefab of the GameObject with the `QuantumEntityPrototype` component
2. Place the Prefab in any folder included in the `QuantumEditorSettings` asset in `Asset Search Paths` (by default includes all the `Assets` folder)

![Entity Prototype Asset](/docs/img/quantum/v3/manual/entityprototype-asset.png)

This automatically generates an `EntityPrototype` asset associated with the prefab.

3. In the editor, reference these `EntityPrototype` assets via fields of type `AssetRef<EntityPrototype>`. This allows referencing the prototype through the simulation code while using familiar Unity drag-and-drop or asset selection.

Example of referencing an Entity Prototype asset in the editor:

![Entity Prototype Asset GUID & Path](/docs/img/quantum/v3/manual/assetref-entityprototype.png)

4. Use `frame.Create()` to create an entity from the prototype:

```csharp
void CreateExampleEntity(Frame frame) {
    // Using a reference to the entity prototype asset
    var exampleEntity = frame.Create(myPrototypeReference);
}
```

### Important Note

Entity prototypes present in the Scene are baked into the **Map Asset**, while prefab-ed entity prototypes are individual **assets** that are part of the Quantum Asset Database.

## Renaming a Component/Prototype

When renaming a component generated from the DSL, make sure to use Unity's asset database maintenance tooling. Deleting and recreating a component with a new name will break all existing entity prototypes that use the component.

## EntityView

The `EntityView` script is responsible for:
1. Displaying and updating the visual representation of a Quantum entity
2. Providing a way to access Unity transforms from within the Quantum simulation

To set up the connection between a GameObject and a Quantum entity:

1. Add the `EntityView` component to the GameObject
2. Link it to a Quantum entity by either:
   - Setting the `Entity Index` field with the entity ID
   - Having the `EntityView` component on a prefab that is instantiated through a Quantum entity callback

Once linked, the `EntityView` will synchronize the GameObject's position, rotation, and scale with the entity's Transform component in the Quantum simulation.

### EntityView Access

To access `EntityView` from within the Quantum simulation, use the `EntityViewTransform` API:

```csharp
// Make a Quantum entity follow a position in world space
public unsafe class FollowWorldPosition : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Get all entities with Transform3D and Follow components
        var filter = frame.Filter<Transform3D, Follow>();
        while (filter.Next(out var entity, out var transform, out var follow))
        {
            // Access the target world position through EntityViewTransform
            var worldPos = EntityViewTransform.GetWorldPosition(follow.Target);
            
            // Perform following logic with the world position
            // ...
        }
    }
}
```

### Overriding EntityView Behavior

You can customize how an `EntityView` behaves by inheriting from it and overriding its methods:

```csharp
public class CustomEntityView : EntityView
{
    // Override to customize the initialization
    public override void OnEntityInstantiated()
    {
        base.OnEntityInstantiated();
        // Your custom initialization
    }
    
    // Override to customize how transform is updated
    public override void OnEntityUpdate()
    {
        base.OnEntityUpdate();
        // Your custom update logic
    }
    
    // Override to handle entity destruction
    public override void OnEntityDestroyed()
    {
        // Your custom cleanup
        base.OnEntityDestroyed();
    }
}
```

## Runtime Entity Creation

To instantiate entities at runtime with a visual representation:

1. Create an entity prototype asset as described earlier
2. Create a prefab with the `EntityView` component
3. Link the entity prototype to the prefab through the `EntityPrototypeLinker`
4. When creating the entity in code, it will automatically instantiate the linked prefab:

```csharp
// In a Quantum system
void CreateEntityWithView(Frame frame)
{
    // Create entity from prototype
    var entity = frame.Create(prototypeAssetRef);
    
    // The EntityPrototypeLinker will handle instantiating the corresponding prefab
}
```

### Custom Entity Prototype Views

For more complex scenarios, you can create custom entity prototype views by:

1. Inheriting from `EntityPrototypeViewBase`
2. Implementing custom instantiation logic
3. Registering your view with the `EntityViewSystem`

Example:

```csharp
public class CustomPrototypeView : EntityPrototypeViewBase
{
    public override EntityView InstantiateView(EntityRef entityRef)
    {
        // Custom instantiation logic
        var instance = Instantiate(viewPrefab);
        var view = instance.GetComponent<EntityView>();
        view.EntityRef = entityRef;
        return view;
    }
}
```

## Best Practices

1. **Maintain Determinism**: Ensure that entity creation and modification in the simulation is deterministic. Use commands for player-initiated actions.

2. **Asset Organization**: Keep entity prototype prefabs in dedicated folders to maintain a clean project structure.

3. **Component Separation**: Clearly separate simulation components (Quantum) from view components (Unity).

4. **Memory Management**: Be mindful of dynamic collections in components - allocate and free them properly to avoid memory leaks.

5. **Testing**: Test prototypes in isolation before integrating them into complex gameplay scenarios.
