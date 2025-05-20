# Networking and Synchronization in Quantum

Quantum implements a deterministic networking model with prediction, rollback, and state synchronization. This document explains how networking works in Quantum and how to implement multiplayer features.

## Core Networking Concepts

### Deterministic Simulation

The core of Quantum's networking is its deterministic simulation:

- Same inputs produce the same outputs on all machines
- Fixed timestep ensures consistent behavior
- All random operations use synchronized seeds
- Physics and other systems behave identically on all clients

### Client-Server Architecture

Quantum uses a client-server architecture:

- One client acts as the host/server
- The server is authoritative for input collection and verification
- Clients predict game state and roll back if necessary
- Photon Realtime is used for the actual network transport

### Input Collection and Distribution

Player inputs are collected locally, then sent to the server:

1. Local inputs are accumulated (e.g., in `PlayerInput.cs`)
2. Inputs are sampled during the `CallbackPollInput` callback
3. Inputs are sent to the server
4. The server distributes inputs to all clients
5. All clients simulate the game state using the same inputs

## Implementation Details

### Input Collection

Input is collected on each client and sent to the server using the `Input` struct:

```csharp
// Input defined in Quantum DSL (Input.qtn)
input {
    FPVector2 MoveDirection;
    FPVector2 LookRotation;
    bool Jump;
    bool Fire;
    bool Sprint;
}

// Input collection in Unity (PlayerInput.cs)
public override void OnUpdateView()
{
    // Accumulate input
    var lookRotationDelta = new Vector2(-Input.GetAxisRaw("Mouse Y"), Input.GetAxisRaw("Mouse X"));
    _input.LookRotation = ClampLookRotation(_input.LookRotation + lookRotationDelta.ToFPVector2());
    
    var moveDirection = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
    _input.MoveDirection = moveDirection.normalized.ToFPVector2();
    
    _input.Fire = Input.GetButton("Fire1");
    _input.Jump = Input.GetButton("Jump");
    _input.Sprint = Input.GetButton("Sprint");
}

// Send input to Quantum
private void PollInput(CallbackPollInput callback)
{
    callback.SetInput(_input, DeterministicInputFlags.Repeatable);
}
```

### QuantumRunner

The `QuantumRunner` class manages the connection between Unity and the Quantum simulation:

```csharp
// Start a Quantum game
var runner = QuantumRunner.StartGame(new SessionRunner.Arguments 
{
    GameMode = DeterministicGameMode.MultiplayerServer,
    RunnerId = "Server",
    RuntimeConfig = RuntimeConfig,
    PlayerCount = 4
});

// Local debug mode
var runner = QuantumRunner.StartGame(new SessionRunner.Arguments 
{
    GameMode = DeterministicGameMode.Local,
    RunnerId = "LocalDebug",
    RuntimeConfig = RuntimeConfig,
    PlayerCount = 4
});
```

### Player Management

Players are managed using the `PlayerRef` type and `RuntimePlayer` class:

```csharp
// Add a player to the game
var playerData = new RuntimePlayer();
playerData.PlayerNickname = "Player1";
playerData.PlayerAvatar = avatarPrototypeRef;
game.AddPlayer(playerIndex, playerData);

// Access player data in a system
var player = frame.GetPlayerData(playerRef);
var playerNickname = player.PlayerNickname;
```

## Prediction and Rollback

Quantum implements prediction and rollback to handle network latency:

1. Clients predict game state based on local inputs
2. When authoritative inputs arrive from the server, clients validate predictions
3. If predictions were incorrect, clients roll back and resimulate

### Prediction Culling

Prediction culling is an optimization where only relevant parts of the game (those in the "prediction area") are simulated during prediction:

```csharp
// Set the prediction area around the local player
frame.SetPredictionArea(playerPosition, radius);

// Check if an entity is in the prediction area
if (frame.InPredictionArea(entityPosition)) {
    // This entity will be simulated in prediction
}
```

## Network Events and Callbacks

Quantum provides numerous callbacks for network events:

```csharp
// Subscribe to callbacks
QuantumCallback.Subscribe(this, (CallbackGameStarted callback) => {
    Debug.Log("Game started!");
});

QuantumCallback.Subscribe(this, (CallbackPlayerAdded callback) => {
    Debug.Log($"Player {callback.PlayerRef} added");
});

QuantumCallback.Subscribe(this, (CallbackPollInput callback) => {
    PollInput(callback);
});
```

## RuntimeConfig and Player Data

The `RuntimeConfig` class allows you to configure the game's initial state:

```csharp
// Create a RuntimeConfig
var config = new RuntimeConfig();
config.Seed = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
config.Map = mapAssetRef;
config.SimulationConfig = simulationConfigRef;
```

The `RuntimePlayer` class stores player-specific data:

```csharp
// Create player data
var playerData = new RuntimePlayer();
playerData.PlayerNickname = "Player1";
playerData.PlayerAvatar = avatarRef;
```

## Game Events

Quantum uses events to communicate from the simulation to the view:

```csharp
// Define an event in Quantum DSL
event Jumped {
    EntityRef Entity;
}

// Trigger an event in a system
frame.Events.Jumped(entity);

// Subscribe to an event in Unity
QuantumEvent.Subscribe<EventJumped>(this, OnJumped);

private void OnJumped(EventJumped jumpEvent) {
    // Play jump sound or animation
    PlayJumpAnimation(jumpEvent.Entity);
}
```

## NetworkCallbacks

`QuantumCallbacks` bridge the Quantum simulation with Unity:

```csharp
// Implementation in QuantumRunnerBehaviour.cs
public void Update() {
    Runner?.Update();
}

// Implementation in UnityRuntime.cs
Runner.Session.Update();
```

## Connecting to Photon Servers

Quantum integrates with Photon Realtime for network transport:

```csharp
// Connect to Photon
PhotonAppSettings.Instance.AppSettings.FixedRegion = region;
PhotonNetwork.ConnectUsingSettings();

// Create or join a room
PhotonNetwork.CreateRoom(roomName);
// or
PhotonNetwork.JoinRoom(roomName);

// When connected to Photon, start Quantum
void OnJoinedRoom() {
    var config = new RuntimeConfig();
    config.Map = map;
    config.Seed = Random.Range(int.MinValue, int.MaxValue);
    
    QuantumRunner.StartGame(new SessionRunner.Arguments {
        GameMode = DeterministicGameMode.MultiplayerServer,
        RuntimeConfig = config,
        PlayerCount = 4
    });
}
```

## Local Debug Mode

Quantum provides a local debug mode for testing without network connections:

```csharp
// Start a local debug game
private void StartLocalDebugGame() {
    var config = new RuntimeConfig();
    config.Map = map;
    config.Seed = Random.Range(int.MinValue, int.MaxValue);
    
    QuantumRunner.StartGame(new SessionRunner.Arguments {
        GameMode = DeterministicGameMode.Local,
        RuntimeConfig = config,
        PlayerCount = 1
    });
}
```

This networking architecture provides a robust foundation for building multiplayer games with Quantum, with powerful features like prediction, rollback, and deterministic simulation that help create smooth, responsive experiences even in high-latency environments.
