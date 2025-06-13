# Game Lobby Management

This chapter covers the comprehensive implementation of game lobby systems in Photon Quantum 3, including room creation, player management, matchmaking, and lobby customization.

## Overview

Lobby management in Quantum 3 involves coordinating between Photon Realtime for networking and Quantum for deterministic simulation. The lobby system handles:

- Room creation and configuration
- Player joining and leaving
- Matchmaking logic
- Custom room properties
- Local multiplayer support
- Pre-game synchronization

## Core Components

### QuantumMenuConnectionBehaviourSDK

The primary class for managing connections and lobby operations:

**File: `/Assets/Photon/QuantumMenu/Runtime/QuantumMenuConnectionBehaviourSDK.cs`**

```csharp
public class QuantumMenuConnectionBehaviourSDK : QuantumMenuConnectionBehaviour {
    private RealtimeClient _client;
    public QuantumRunner Runner { get; private set; }
    
    // Key properties for lobby management
    public override string SessionName => Client?.CurrentRoom?.Name;
    public override string Region => Client?.CurrentRegion;
    public override int MaxPlayerCount => Client?.CurrentRoom?.MaxPlayers ?? 0;
    
    protected override async Task<ConnectResult> ConnectAsyncInternal(QuantumMenuConnectArgs connectArgs) {
        // Connection and room creation logic
        var arguments = new MatchmakingArguments {
            PhotonSettings = new AppSettings(connectArgs.AppSettings),
            MaxPlayers = connectArgs.MaxPlayerCount,
            RoomName = connectArgs.Session,
            CanOnlyJoin = !string.IsNullOrEmpty(connectArgs.Session) && !connectArgs.Creating,
            // Custom lobby properties
            CustomLobbyProperties = connectArgs.CustomLobbyProperties,
            SqlLobbyFilter = connectArgs.SqlLobbyFilter
        };
        
        // Connect to room
        _client = await MatchmakingExtensions.ConnectToRoomAsync(arguments);
    }
}
```

### Custom Lobby Properties

Support for filtering and matchmaking with custom properties:

**Example from Sports Arena Brawler:**
**File: `/Assets/SportsArenaBrawler/Scripts/Menu/SportsArenaBrawlerMenuConnectionBehaviourSDK.cs`**

```csharp
public class SportsArenaBrawlerMenuConnectionBehaviourSDK : QuantumMenuConnectionBehaviourSDK {
    [SerializeField]
    private SportsArenaBrawlerLocalPlayerController _localPlayersCountSelector;
    
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args) {
        // Set up SQL lobby for filtering by player count
        args.RandomMatchingType = MatchmakingMode.FillRoom;
        args.Lobby = LocalPlayerCountManager.SQL_LOBBY;
        args.CustomLobbyProperties = new string[] { LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY };
        
        // Filter rooms based on available slots for local players
        args.SqlLobbyFilter = $"{LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY} <= " +
            $"{Input.MAX_COUNT - _localPlayersCountSelector.GetLastSelectedLocalPlayersCount()}";
    }
}
```

## Room Creation and Configuration

### Basic Room Creation

```csharp
public async Task<ConnectResult> CreateRoom(string roomName, int maxPlayers) {
    var connectArgs = new QuantumMenuConnectArgs {
        Session = roomName,
        Creating = true,
        MaxPlayerCount = maxPlayers,
        AppSettings = PhotonServerSettings.Global.AppSettings,
        RuntimeConfig = CreateRuntimeConfig(),
        RuntimePlayers = new[] { new RuntimePlayer { PlayerNickname = "Host" } }
    };
    
    return await ConnectAsync(connectArgs);
}
```

### Advanced Room Configuration

```csharp
public class CustomLobbyManager : QuantumMenuConnectionBehaviourSDK {
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args) {
        // Configure room properties
        args.RoomOptions = new RoomOptions {
            MaxPlayers = connectArgs.MaxPlayerCount,
            PlayerTtl = 10000, // 10 seconds for reconnection
            EmptyRoomTtl = 0,  // Room closes immediately when empty
            CleanupCacheOnLeave = false, // Keep player data for reconnection
            
            // Custom properties visible in lobby
            CustomRoomProperties = new Hashtable {
                ["GameMode"] = "TeamDeathmatch",
                ["MapName"] = "Arena01",
                ["SkillLevel"] = "Intermediate"
            },
            CustomRoomPropertiesForLobby = new[] { "GameMode", "MapName", "SkillLevel" }
        };
    }
}
```

## Matchmaking Implementation

### Random Matchmaking

```csharp
public async Task<ConnectResult> JoinRandomRoom(string gameMode = null) {
    var connectArgs = new QuantumMenuConnectArgs {
        Session = null, // Null session triggers random matchmaking
        MaxPlayerCount = 4,
        RuntimeConfig = CreateRuntimeConfig()
    };
    
    // Set up SQL filter for game mode
    if (!string.IsNullOrEmpty(gameMode)) {
        connectArgs.SqlLobbyFilter = $"GameMode = '{gameMode}'";
    }
    
    return await ConnectAsync(connectArgs);
}
```

### Skill-Based Matchmaking

```csharp
public class SkillBasedMatchmaking : QuantumMenuConnectionBehaviourSDK {
    public int PlayerSkillLevel = 1000;
    public int SkillRange = 200;
    
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args) {
        // Create SQL filter for skill-based matching
        int minSkill = PlayerSkillLevel - SkillRange;
        int maxSkill = PlayerSkillLevel + SkillRange;
        
        args.SqlLobbyFilter = $"SkillLevel >= {minSkill} AND SkillLevel <= {maxSkill}";
        args.CustomLobbyProperties = new[] { "SkillLevel" };
        
        // Set room properties
        if (args.RoomOptions == null) {
            args.RoomOptions = new RoomOptions();
        }
        args.RoomOptions.CustomRoomProperties = new Hashtable {
            ["SkillLevel"] = PlayerSkillLevel
        };
    }
}
```

## Player List Management

### Real-time Player Tracking

```csharp
public class LobbyPlayerList : MonoBehaviour {
    private QuantumMenuConnectionBehaviourSDK _connection;
    
    void Update() {
        if (_connection?.Runner?.Game != null) {
            var frame = _connection.Runner.Game.Frames.Verified;
            
            // Update player list UI
            for (int i = 0; i < frame.MaxPlayerCount; i++) {
                var isConnected = (frame.GetPlayerInputFlags(i) & 
                    DeterministicInputFlags.PlayerNotPresent) == 0;
                    
                if (isConnected) {
                    var playerData = frame.GetPlayerData(i);
                    UpdatePlayerSlot(i, playerData.PlayerNickname, true);
                } else {
                    UpdatePlayerSlot(i, "Empty", false);
                }
            }
        }
    }
}
```

### Custom Player Properties

```csharp
public class PlayerCustomization {
    public static void SetPlayerProperties(RealtimeClient client, Hashtable properties) {
        // Set custom properties for the local player
        client.LocalPlayer.SetCustomProperties(properties);
    }
    
    public static void UpdateLobbyDisplay() {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client?.CurrentRoom != null) {
            foreach (var player in client.CurrentRoom.Players.Values) {
                if (player.CustomProperties.TryGetValue("CharacterType", out var characterType)) {
                    Debug.Log($"Player {player.NickName} selected: {characterType}");
                }
            }
        }
    }
}
```

## Pre-Game Lobby System

### Lobby Timer Implementation

**From Motor Dome Sample:**
**File: `/Assets/QuantumUser/Simulation/Game/Systems/LobbySystem.cs`**

```csharp
unsafe class LobbySystem : SystemMainThread, IGameState_Lobby {
    public override void OnEnabled(Frame f) {
        if (f.SessionConfig.PlayerCount > 1) {
            // Set lobby countdown timer
            f.Global->clock = FrameTimer.FromSeconds(f, 
                f.SimulationConfig.lobbyingDuration);
        } else {
            // Skip lobby for single player
            GameStateSystem.SetState(f, GameState.Pregame);
        }
    }
    
    public override void Update(Frame f) {
        var expiredThisFrame = f.Global->clock.IsRunning(f) == false && 
            f.Global->clock.TargetFrame == f.Number;
            
        if (expiredThisFrame) {
            f.Global->clock = FrameTimer.None;
            GameStateSystem.SetState(f, GameState.Pregame);
        }
    }
}
```

### Ready System

```csharp
// Define in DSL
component PlayerReady {
    bool IsReady;
}

// Lobby ready system
public class LobbyReadySystem : SystemMainThread {
    public override void Update(Frame f) {
        if (f.Global->CurrentState != GameState.Lobby) return;
        
        int readyCount = 0;
        int totalPlayers = 0;
        
        // Check all players
        var playerFilter = f.Filter<PlayerLink, PlayerReady>();
        while (playerFilter.NextUnsafe(out var entity, out var link, out var ready)) {
            totalPlayers++;
            if (ready->IsReady) readyCount++;
        }
        
        // Start game when all ready
        if (readyCount == totalPlayers && totalPlayers > 0) {
            GameStateSystem.SetState(f, GameState.Starting);
        }
    }
}
```

## Local Multiplayer Lobby

### Supporting Multiple Local Players

```csharp
public class LocalMultiplayerLobby : MonoBehaviour {
    public int LocalPlayerCount = 1;
    
    public void CreateRoomWithLocalPlayers() {
        var runtimePlayers = new RuntimePlayer[LocalPlayerCount];
        
        for (int i = 0; i < LocalPlayerCount; i++) {
            runtimePlayers[i] = new RuntimePlayer {
                PlayerNickname = $"Player {i + 1}",
                PlayerAvatar = GetAvatarForPlayer(i)
            };
        }
        
        var connectArgs = new QuantumMenuConnectArgs {
            Session = "LocalMultiplayerRoom",
            MaxPlayerCount = 4,
            RuntimePlayers = runtimePlayers
        };
        
        StartCoroutine(ConnectToRoom(connectArgs));
    }
}
```

## Lobby Events and Callbacks

### Monitoring Lobby State

```csharp
public class LobbyEventHandler : MonoBehaviour {
    void Start() {
        // Subscribe to Photon callbacks
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null) {
            client.CallbackMessage.Listen<OnPlayerEnteredRoomMsg>(OnPlayerJoined);
            client.CallbackMessage.Listen<OnPlayerLeftRoomMsg>(OnPlayerLeft);
            client.CallbackMessage.Listen<OnRoomPropertiesUpdateMsg>(OnRoomPropertiesChanged);
        }
    }
    
    void OnPlayerJoined(OnPlayerEnteredRoomMsg msg) {
        Debug.Log($"Player joined: {msg.newPlayer.NickName}");
        UpdateLobbyUI();
    }
    
    void OnPlayerLeft(OnPlayerLeftRoomMsg msg) {
        Debug.Log($"Player left: {msg.otherPlayer.NickName}");
        UpdateLobbyUI();
    }
    
    void OnRoomPropertiesChanged(OnRoomPropertiesUpdateMsg msg) {
        Debug.Log("Room properties updated");
        RefreshRoomSettings();
    }
}
```

## Best Practices

1. **Always validate room settings** before creating or joining
2. **Use SQL filters** for efficient matchmaking
3. **Implement timeout handling** for lobby waiting
4. **Cache player properties** to reduce network calls
5. **Handle edge cases** like host migration
6. **Provide feedback** for all lobby actions
7. **Test with various player counts** and network conditions
8. **Implement proper cleanup** when leaving lobby

## Common Patterns

### Auto-Start When Full

```csharp
public class AutoStartLobby : SystemMainThread {
    public override void Update(Frame f) {
        if (f.Global->CurrentState != GameState.Lobby) return;
        
        int connectedPlayers = 0;
        for (int i = 0; i < f.SessionConfig.PlayerCount; i++) {
            if ((f.GetPlayerInputFlags(i) & DeterministicInputFlags.PlayerNotPresent) == 0) {
                connectedPlayers++;
            }
        }
        
        if (connectedPlayers == f.SessionConfig.PlayerCount) {
            // Room is full, start immediately
            GameStateSystem.SetState(f, GameState.Starting);
        }
    }
}
```

### Host Migration Support

```csharp
public class HostMigrationLobby : QuantumMenuConnectionBehaviourSDK {
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args) {
        // Enable host migration
        args.RoomOptions = new RoomOptions {
            PlayerTtl = 10000,  // Keep player slot for 10 seconds
            EmptyRoomTtl = 5000, // Keep room alive for 5 seconds when empty
            CleanupCacheOnLeave = false
        };
    }
    
    protected override void OnConnected(RealtimeClient client) {
        // Monitor for master client changes
        client.CallbackMessage.Listen<OnMasterClientSwitchedMsg>(msg => {
            Debug.Log($"New host: {msg.newMasterClient.NickName}");
            UpdateHostUI(msg.newMasterClient);
        });
    }
}
```

This comprehensive lobby management system provides the foundation for creating robust multiplayer experiences with proper player coordination and room management.
