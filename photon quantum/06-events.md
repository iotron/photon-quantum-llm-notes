# Quantum Events

## Introduction

Quantum's architecture separates the simulation (Quantum) and view (Unity), providing modularity for game state and visuals. There are two ways for the view to get information from the game state:

1. **Polling the game state**: Continuously checking the game state for information
2. **Events/Callbacks**: Receiving notifications when specific things happen

General usage pattern:
- **Polling**: Preferred for ongoing visuals (continuous updates)
- **Events**: Better for punctual occurrences where the simulation triggers a reaction in the view

This document focuses on **Frame Events** & **Callbacks**.

## Frame Events

Events are a fire-and-forget mechanism to transfer information from the simulation to the view. Important characteristics:

- Events should **never** be used to modify or update the game state (use `Signals` for that)
- Events do not synchronize between clients - they are fired by each client's own simulation
- The same Frame can be simulated multiple times (prediction, rollback), so events might trigger multiple times
- Quantum identifies duplicate events using a hash code function based on event data, ID, and tick
- Regular (non-`synced`) events will be canceled or confirmed once the predicted frame is verified
- Events are dispatched after all Frames have been simulated, right after the `OnUpdateView` callback
- Events are called in the same order they were invoked (with exceptions for non-`synced` duplicates)

### Basic Example

1. Define an Event using Quantum DSL:

```qtn
event MyEvent {
  int Foo;
}
```

2. Trigger the Event from the simulation:

```csharp
f.Events.MyEvent(2023);
```

3. Subscribe and consume the Event in Unity:

```csharp
QuantumEvent.Subscribe(listener: this, handler: (EventMyEvent e) => Debug.Log($"MyEvent {e.Foo}"));
```

### DSL Structure

Events and their data are defined using the Quantum DSL inside a qtn-file. After compiling, they become available via the `Frame.Events` API in the simulation.

```qtn
event MyEvent {
  FPVector3 Position;
  FPVector3 Direction;
  FP Length
}
```

Class inheritance allows sharing base Event classes and members:

```qtn
event MyBaseEvent {}
event SpecializedEventFoo : MyBaseEvent {}
event SpecializedEventBar : MyBaseEvent {}
```

Notes on inheritance:
- The `synced` keyword cannot be inherited
- Use abstract classes to prevent base-Events from being triggered directly:

```qtn
abstract event MyBaseEvent {}
event MyConcreteEvent : MyBaseEvent {}
```

You can reuse DSL-generated structs inside Events:

```qtn
struct FooEventData {
  FP Bar;
  FP Par;
  FP Rap;
}

event FooEvent {
  FooEventData EventData;
}
```

### Special Keywords

#### synced

To avoid rollback-induced false positive Events, mark them with the `synced` keyword:

```qtn
synced event MyEvent {}
```

This guarantees events will only be dispatched to Unity when the input for the Frame has been confirmed by the server. This introduces a delay between when the event is issued in the simulation and when it appears in the view.

Key points:
- `synced` Events never create false positives or false negatives
- Non-`synced` Events are never called twice on Unity

#### nothashed

Events use hash codes to prevent duplicates from being dispatched multiple times. Sometimes, minimal rollback-induced changes can cause the same conceptual event to be interpreted as two different events.

The `nothashed` keyword controls what data is used in the uniqueness test by ignoring parts of the Event data:

```qtn
abstract event MyEvent {
  nothashed FPVector2 Position;
  Int32 Foo;
}
```

#### local, remote

For events with a `player_ref` member, special keywords are available:

```qtn
event LocalPlayerOnly {
  local player_ref player;
}
```

```qtn
event RemotePlayerOnly {
  remote player_ref player;
}
```

These keywords cause the `player_ref` to be checked before dispatching the event on a client:
- `local`: Only dispatched if the player is a local player
- `remote`: Only dispatched if the player is a remote player

The simulation itself is agnostic to the concept of `remote` and `local`. The keywords only affect whether a particular event is raised in the view of an individual client.

You can combine `local` and `remote` with multiple `player_ref` parameters:

```qtn
event MyEvent {
  local player_ref LocalPlayer;
  remote player_ref RemotePlayer;
  player_ref AnyPlayer;
}
```

This event will only trigger on the client who controls the `LocalPlayer` and when the `RemotePlayer` is assigned to a different player.

If a client controls several players (e.g., split-screen), all their `player_ref` will be considered local.

#### client, server

This is only relevant when running server-side simulation on a custom Quantum plugin.

Events can be qualified using `client` and `server` keywords to scope where they will be executed. By default, all Events will be dispatched on both client and server.

```qtn
server synced event MyServerEvent {}
```

```qtn
client event MyClientEvent {}
```

### Using Events

#### Triggering Events

Event types and signatures are code-generated into the `Frame.FrameEvents` struct, accessible via `Frame.Events`:

```csharp
public override void Update(Frame frame) {
  frame.Events.MyEvent(2023);
}
```

#### Choosing Event Data

Event data should be self-contained and carry all information the subscriber will need to handle it in the view. When an Event is dispatched to the view:

- The Frame when the Event was raised might no longer be available
- Information needed to handle the Event could be lost if it wasn't included in the Event
- QCollections or QLists are passed as pointers to memory on the Frame heap, which might be unavailable
- EntityRefs might point to different data than when the Event was originally invoked

Ways to include collection data in Events:

1. Use fixed arrays for known, reasonable-sized collections:
```qtn
struct FooEventData {
  array<FP>[4] ArrayOfValues;
}
event FooEvent {
  FooEventData EventData;
}
```

2. Extend the Event implementation using partial classes (see "Extend Event Implementation" section)

#### Event Subscriptions In Unity

Quantum provides a flexible Event subscription API via `QuantumEvent`:

```csharp
QuantumEvent.Subscribe(listener: this, handler: (EventPlayerHit e) => Debug.Log($"Player hit in Frame {e.Tick}"));
```

You can also use a delegate function:

```csharp
QuantumEvent.Subscribe<EventPlayerHit>(listener: this, handler: OnEventPlayerHit);

private void OnEventPlayerHit(EventPlayerHit e){
  Debug.Log($"Player hit in Frame {e.Tick}");
}
```

`QuantumEvent.Subscribe` offers several optional parameters to qualify the subscription:

```csharp
// Only invoked once, then removed
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, once: true); 

// Not invoked if the listener is not active and enabled
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, onlyIfActiveAndEnabled: true); 

// Only called for runner with specified id
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, runnerId: "SomeRunnerId"); 

// Only called for a specific runner
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, runner: runnerReference); 

// Custom filter, invoked only if player 4 is local
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, filter: (QuantumGame game) => game.PlayerIsLocal(4)); 

// Only for replays
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, gameMode: DeterministicGameMode.Replay); 

// For all types except replays
QuantumEvent.Subscribe(this, (EventPlayerHit e) => {}, gameMode: DeterministicGameMode.Replay, exclude: true);
```

#### Unsubscribing From Events

Unity manages the lifetime of `MonoBehaviours`, so there's no need to unregister as listeners are cleaned up automatically.

For manual control:

```csharp
var subscription = QuantumEvent.Subscribe(...);

// Cancels this specific subscription
QuantumEvent.Unsubscribe(subscription); 

// Cancels all subscriptions for this listener
QuantumEvent.UnsubscribeListener(this); 

// Cancels all listeners to EventPlayerHit for this listener
QuantumEvent.UnsubscribeListener<EventPlayerHit>(this);
```

#### Event Subscriptions Outside MonoBehaviours

If an Event is subscribed outside of a `MonoBehaviour`, the subscription must be handled manually:

```csharp
var disposable = QuantumEvent.SubscribeManual((EventPlayerHit e) => {}); // subscribes to the event
// ...
disposable.Dispose(); // disposes the event subscription
```

#### Canceled And Confirmed Events

Non-`synced` Events are either canceled or confirmed once the verified Frame has been simulated. Quantum offers callbacks to react to these:

```csharp
QuantumCallback.Subscribe(this, (Quantum.CallbackEventCanceled c) => Debug.Log($"Cancelled event {c.EventKey}"));
QuantumCallback.Subscribe(this, (Quantum.CallbackEventConfirmed c) => Debug.Log($"Confirmed event {c.EventKey}"));
```

Event instances are identified by the `EventKey` struct. The previously received Event can be tracked using this key:

```csharp
public void OnEvent(MyEvent e) {
  EventKey eventKey = (EventKey)e;
  // Store in dictionary, etc.
}
```

### Extending Event Implementation

Although Events support using a `QList`, when resolving the list the corresponding Frame might not be available. Additional data types can be added using `partial` class declarations:

1. Define the event in Quantum DSL:
```qtn
event ListEvent {
  EntityRef Entity;
}
```

2. Extend the `partial FrameEvents` struct to raise the customized Event:

```csharp
namespace Quantum
{
  using System;
  using System.Collections.Generic;

  partial class EventListEvent {
    // Add the C# list field to the event object using partial
    public List<Int32> ListOfFoo;
  }

  partial class Frame {
    partial struct FrameEvents {
      public EventListEvent ListEvent(EntityRef entity, List<Int32> listOfFoo) {
        var ev = ListEvent(entity);
        if (ev == null) {
          // Synced or local events can be null for example during predicted frame
          return null;
        }

        // Reuse the list object of the pooled event
        if (ev.ListOfFoo == null) {
          ev.ListOfFoo = new List<Int32>(listOfFoo.Count);
        }
        ev.ListOfFoo.Clear();

        // Copy the content into the event to be independent from the input list
        ev.ListOfFoo.AddRange(listOfFoo);

        return ev;
      }
    }
  }
}
```

3. Call the event from the simulation code:

```csharp
// The list object can be cached and reused, its content is copied inside the ListEvent() call
f.Events.ListEvent(f, 0, new List<FP> {2, 3, 4});
```

## Callbacks

Callbacks are special events triggered internally by the Quantum Core. Available callbacks include:

| Callback | Description |
| --- | --- |
| CallbackPollInput | Called when the simulation queries local input |
| CallbackInputConfirmed | Called when local input was confirmed |
| CallbackGameStarted | Called when the game has been started |
| CallbackGameResynced | Called when the game has been re-synchronized from a snapshot |
| CallbackGameDestroyed | Called when the game was destroyed |
| CallbackUpdateView | Guaranteed to be called every rendered frame |
| CallbackSimulateFinished | Called when frame simulation has completed |
| CallbackEventCanceled | Called when an event raised in a predicted frame was cancelled |
| CallbackEventConfirmed | Called when an event was confirmed by a verified frame |
| CallbackChecksumError | Called on a checksum error |
| CallbackChecksumErrorFrameDump | Called when a frame is dumped due to a checksum error |
| CallbackChecksumComputed | Called when a checksum has been computed |
| CallbackPluginDisconnect | Called when the plugin disconnects the client with an error |

### Unity-side Callbacks

By configuring `Auto Load Scene From Map` in the `SimulationConfig` asset, you can control if the game scene will be loaded automatically and whether preview scene unloading happens before or after the game scene is loaded.

Scene loading/unloading callbacks:
- `CallbackUnitySceneLoadBegin`
- `CallbackUnitySceneLoadDone`
- `CallbackUnitySceneUnloadBegin`
- `CallbackUnitySceneUnloadDone`

### Subscribing to Callbacks

Callbacks are subscribed to and unsubscribed from in the same way as Events:

```csharp
QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
```

## Best Practices

1. **Choose the Right Mechanism**:
   - Use polling for continuous visual updates
   - Use events for one-time notifications
   - Use signals for inter-system communication within simulation

2. **Self-Contained Events**:
   - Events should carry all data needed to handle them
   - Do not rely on accessing the Frame when handling events

3. **Consider Synchronization**:
   - Use `synced` keyword for events that should never create false positives
   - Be aware of prediction/rollback when designing event systems

4. **Handle Collections Properly**:
   - Use fixed arrays for small collections
   - Extend events with partial classes for more complex data structures
   - Be careful with QCollections in events as the frame might be unavailable

5. **Optimize Subscriptions**:
   - Use subscription filters to limit when events are processed
   - Clean up manually managed subscriptions to prevent memory leaks

6. **Use Event Confirmation**:
   - Monitor event cancellation/confirmation for non-synced events
   - Consider visual feedback that can gracefully handle cancellation
