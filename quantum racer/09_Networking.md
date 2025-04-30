# Quantum Networking Implementation

Quantum Racer 2.5D leverages Photon Quantum's networking capabilities to provide deterministic multiplayer racing. This document explains the key networking concepts and implementation details.

## PhotonServerSettings

The PhotonServerSettings asset contains the configuration for connecting to Photon servers:

```csharp
// Located in Assets/QuantumUser/Resources/PhotonServerSettings.asset
public class PhotonServerSettings : ScriptableObject
{
    public string AppID;        // Photon application ID from dashboard
    public string AppVersion;   // Application version for matchmaking
    public string Region;       // Default region (e.g., "eu", "us", "asia")
    public bool EnableLobby;    // Whether to join a lobby on connect
    public ServerType ServerType = ServerType.Quantum;  // Using Quantum servers
    public RuntimeConfig DefaultRuntimeConfig;          // Default quantum config
}
```

## Core Quantum Networking

Quantum provides a deterministic networking framework with:

1. Input collection and synchronization
2. Deterministic physics simulation
3. Frame rollback and prediction
4. Client-side reconciliation

## Session Config

The SessionConfig asset defines the network session parameters:

```csharp
// Located in Assets/QuantumUser/Resources/SessionConfig.asset
public class SessionConfig : ScriptableObject
{
    public RuntimeConfig RuntimeConfig;
    public DeterministicSessionConfig SessionConfig;
    
    // Network settings
    public int TickRate = 60;                // Physics updates per second
    public int UpdateFPS = 60;               // Visual update rate
    public int InputDelayFrames = 2;         // Delay for input processing
    public int PredictionFrames = 2;         // Number of frames to predict ahead
    public int RollbackFrames = 12;          // Maximum rollback frames on correction
    public int SnapshotSendRate = 30;        // State snapshots per second
    public int InputSendRate = 60;           // Input send rate per second
    
    // Game settings
    public int MaxSlotsOnServer = 99;        // Maximum players in a session 
    public bool ClientSideVerification = false;
}
```

## Multiplayer Integration

### Player Connection

The Quantum runner manages player connections and game session:

```csharp
public class MultiplayerManager : MonoBehaviour
{
    private QuantumRunner _runner;
    
    public async void JoinGame()
    {
        // Load server settings
        var serverSettings = Resources.Load<PhotonServerSettings>("PhotonServerSettings");
        var sessionConfig = Resources.Load<SessionConfig>("SessionConfig");
        
        // Connect to Photon Cloud
        await Photon.Realtime.PhotonNetwork.ConnectUsingSettingsAsync(serverSettings);
        
        // Join or create room
        var roomOptions = new Photon.Realtime.RoomOptions {
            MaxPlayers = sessionConfig.MaxSlotsOnServer,
            IsVisible = true
        };
        
        await Photon.Realtime.PhotonNetwork.JoinOrCreateRoomAsync(
            "RacerRoom", roomOptions, Photon.Realtime.TypedLobby.Default);
        
        // Start Quantum session
        var callbackHandler = new QuantumCallbacks();
        _runner = QuantumRunner.StartGame(
            "RacerRoom", 
            PhotonNetwork.LocalPlayer.ActorNumber, 
            PhotonNetwork.CurrentRoom.Players.Count,
            sessionConfig,
            callbackHandler);
    }
}
```

### Input Handling

The Quantum input system collects and synchronizes player inputs:

```csharp
public class InputHandler : MonoBehaviour, ISignalInputConfirmed, ISignalInputSubmitted
{
    public void Update()
    {
        if (QuantumRunner.Default == null) return;
        
        // Get current input
        var input = new Quantum.Input();
        
        // Keyboard controls
        input.RacerAccel.Set(UnityEngine.Input.GetKey(KeyCode.W));
        input.RacerBrake.Set(UnityEngine.Input.GetKey(KeyCode.S));
        input.RacerLeft.Set(UnityEngine.Input.GetKey(KeyCode.A));
        input.RacerRight.Set(UnityEngine.Input.GetKey(KeyCode.D));
        input.RacerLeanLeft.Set(UnityEngine.Input.GetKey(KeyCode.J));
        input.RacerLeanRight.Set(UnityEngine.Input.GetKey(KeyCode.L));
        input.RacerPitchUp.Set(UnityEngine.Input.GetKey(KeyCode.I));
        input.RacerPitchDown.Set(UnityEngine.Input.GetKey(KeyCode.K));
        
        // Submit to Quantum
        QuantumRunner.Default.Game.SendInput(input);
    }
    
    public void OnInputConfirmed(Frame frame, InputInfo inputInfo)
    {
        // Called when the server confirms our input
        Debug.Log($"Input confirmed for frame {inputInfo.Frame}");
    }
    
    public void OnInputSubmitted(Frame frame, PlayerRef player, Input input)
    {
        // Called when any player submits input
        if (player == frame.Runner.LocalPlayerRef)
        {
            Debug.Log($"Local input submitted for frame {frame.Number}");
        }
    }
}
```

## Network Synchronization

### Player Data Synchronization

```csharp
public class NetworkPlayerData
{
    // Synchronized player data
    public string PlayerNickname;
    public int PlayerCar;
    public AssetRef<EntityPrototype> PlayerAvatar;
    
    // Local setup
    public static void SetupLocalPlayer(string nickname, int carIndex)
    {
        if (QuantumRunner.Default == null) return;
        
        var data = QuantumRunner.Default.Game.GetPlayerData(QuantumRunner.Default.Game.LocalPlayerIndex);
        data.PlayerNickname = nickname;
        data.PlayerCar = carIndex;
        
        // Set avatar based on car selection
        var map = QuantumRunner.Default.Game.Frames.Predicted.Map;
        var spawnConfig = QuantumRunner.Default.Game.Frames.Predicted.FindAsset<SpawnConfig>(map.UserAsset);
        data.PlayerAvatar = spawnConfig.AvailableCars[carIndex];
    }
}
```

### Deterministic Random

Quantum uses a deterministic random number generator to ensure all clients calculate the same results:

```csharp
// In RaceManagerSystem.Spawn
var racelineToPick = f.Global->RngSession.Next(0, spawnConfig.AvailableRacelines.Length);
bot->Raceline = spawnConfig.AvailableRacelines[racelineToPick];
```

## Frame Prediction and Rollback

Quantum uses frame prediction for smooth gameplay and rollback for corrections:

```csharp
public class QuantumCallbacks : QuantumCallbackHandler
{
    public override void OnUpdateView(QuantumGame game)
    {
        // Called after the prediction is complete
        // View components use this to update visuals
    }
    
    public override void OnSimulateFinished(QuantumGame game, Frame frame)
    {
        // Called after each frame simulation
        if (frame.IsVerified)
        {
            // Frame has been verified by the server
        }
    }
    
    public override void OnRollback(QuantumGame game)
    {
        // Called when a client needs to rollback due to a correction
        Debug.Log($"Rollback occurred at frame {game.Frames.Predicted.Number}");
    }
}
```

## Handling Networked Events

Events are used to synchronize important game events across the network:

```csharp
// Signal interfaces
public unsafe class RacerSystem : SystemMainThreadFilter<RacerSystem.Filter>,
    ISignalOnPlayerAdded,
    ISignalOnTriggerEnter2D,
    ISignalOnTriggerExit2D,
    ISignalOnCollisionEnter2D,
    ISignalRespawn,
    ISignalReset
{
    // Implementation...
}

// Event emission in code
f.Events.Jump(entity);
f.Events.Death(entity);
f.Events.VehicleBump(info.Entity, info.Other, info.ContactPoints.Average);

// Event handling via interfaces
public class RacerSFX : QuantumEntityViewComponent, 
    ISignalOnJump, 
    ISignalOnJumpLand, 
    ISignalOnDeath, 
    ISignalOnRespawn, 
    ISignalOnBump, 
    ISignalOnVehicleBump
{
    public void OnJump(Frame frame, Jump e) 
    {
        if (e.Entity == EntityRef && EffectsSource != null && JumpSound != null) 
        {
            EffectsSource.PlayOneShot(JumpSound);
        }
    }
    
    // Other handlers...
}
```

## Photon Room and Matchmaking

The game uses Photon's room system for matchmaking:

```csharp
public class MatchmakingUI : MonoBehaviour
{
    public async void CreateRoom()
    {
        var roomOptions = new Photon.Realtime.RoomOptions
        {
            MaxPlayers = 16,
            IsVisible = true,
            CustomRoomProperties = new ExitGames.Client.Photon.Hashtable
            {
                { "map", "Circuit1" },
                { "laps", 3 }
            },
            CustomRoomPropertiesForLobby = new string[] { "map", "laps" }
        };
        
        await PhotonNetwork.CreateRoomAsync(null, roomOptions);
    }
    
    public async void JoinRandomRoom()
    {
        try 
        {
            await PhotonNetwork.JoinRandomRoomAsync();
        }
        catch (Photon.Realtime.ClientOutgoingOperationFailedException)
        {
            // No rooms available, create one
            await CreateRoom();
        }
    }
}
```

## Implementation Notes

- Uses Photon Quantum's deterministic networking
- Supports up to 99 players in a race
- Input delay and prediction settings are configurable
- Requires AppID from Photon Dashboard
- Uses deterministic random for consistent results
- Events propagate synchronized game events
- Matchmaking uses Photon's room system
- Frame rollback handles network corrections
