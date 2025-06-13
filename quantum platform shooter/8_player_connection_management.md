# Player Connection Management - Quantum Platform Shooter

## Overview

Quantum Platform Shooter uses the **standard Quantum Menu connection system** with minimal overhead, optimized for fast-paced 2D platform combat. The connection management focuses on quick matchmaking, stable gameplay connections, and seamless reconnection support.

## Connection Architecture

### 1. **Streamlined Stack**
- **Quantum Menu Connection**: Handles all networking
- **Photon Realtime**: Core networking layer
- **Simple State Management**: Minimal connection states
- **Quick Recovery**: Fast reconnection logic

### 2. **Connection Flow**
```
Main Menu → Connect to Photon → Join Lobby → Quick Match → Game
                                    ↓
                              Create Room → Wait for Players → Start
```

## Core Components

### Standard Connection Handler
```csharp
public class PlatformShooterConnection : QuantumMenuConnectionBehaviourSDK
{
    protected override void Awake()
    {
        base.Awake();
        
        // Configure for platform shooter
        ConfigureConnectionSettings();
    }
    
    void ConfigureConnectionSettings()
    {
        // Optimize for fast-paced gameplay
        PhotonNetwork.SendRate = 60;
        PhotonNetwork.SerializationRate = 30;
        
        // Quick disconnect detection
        PhotonNetwork.KeepAliveInBackground = 2f;
    }
}
```

### Connection States
```csharp
public enum ConnectionState
{
    Offline,
    Connecting,
    Connected,
    InLobby,
    JoiningRoom,
    InRoom,
    LoadingGame,
    InGame
}
```

## Quick Connect System

### 1. **Auto-Connect on Start**
```csharp
public class AutoConnectManager : MonoBehaviourPunCallbacks
{
    void Start()
    {
        // Check saved preferences
        if (ShouldAutoConnect())
        {
            ConnectToPhoton();
        }
    }
    
    void ConnectToPhoton()
    {
        // Set player name from saved data
        PhotonNetwork.NickName = PlayerPrefs.GetString("PlayerName", GenerateGuestName());
        
        // Connect with configured settings
        PhotonNetwork.ConnectUsingSettings();
    }
    
    string GenerateGuestName()
    {
        return $"Player{Random.Range(1000, 9999)}";
    }
}
```

### 2. **Region Selection**
```csharp
public class RegionManager : MonoBehaviourPunCallbacks
{
    void Start()
    {
        // Use saved region or auto-select
        string savedRegion = PlayerPrefs.GetString("PreferredRegion", "");
        
        if (!string.IsNullOrEmpty(savedRegion))
        {
            PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = savedRegion;
        }
        else
        {
            // Let Photon choose best region
            PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = "";
        }
    }
    
    public override void OnConnectedToMaster()
    {
        // Save selected region for next time
        PlayerPrefs.SetString("PreferredRegion", PhotonNetwork.CloudRegion);
    }
}
```

## Player Session Management

### Session Data
```csharp
[System.Serializable]
public class PlayerSessionData
{
    public string PlayerId;
    public string DisplayName;
    public int SelectedCharacter;
    public PlayerStats Statistics;
    public DateTime LastPlayed;
    
    public void SaveLocal()
    {
        string json = JsonUtility.ToJson(this);
        PlayerPrefs.SetString("SessionData", json);
    }
    
    public static PlayerSessionData LoadLocal()
    {
        string json = PlayerPrefs.GetString("SessionData", "");
        return string.IsNullOrEmpty(json) 
            ? new PlayerSessionData() 
            : JsonUtility.FromJson<PlayerSessionData>(json);
    }
}
```

### Player Properties Sync
```csharp
public class PlayerPropertiesManager : MonoBehaviourPunCallbacks
{
    void Start()
    {
        SetInitialProperties();
    }
    
    void SetInitialProperties()
    {
        var properties = new Hashtable
        {
            ["Character"] = PlayerPrefs.GetInt("SelectedCharacter", 0),
            ["Level"] = CalculatePlayerLevel(),
            ["Wins"] = PlayerPrefs.GetInt("TotalWins", 0),
            ["Ready"] = false
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(properties);
    }
    
    public override void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        // Update UI when properties change
        if (targetPlayer == PhotonNetwork.LocalPlayer)
        {
            UpdateLocalPlayerUI(changedProps);
        }
        else
        {
            UpdateRemotePlayerUI(targetPlayer, changedProps);
        }
    }
}
```

## Matchmaking

### Quick Match Implementation
```csharp
public class QuickMatchManager : MonoBehaviourPunCallbacks
{
    private int matchmakingAttempts = 0;
    private const int MAX_ATTEMPTS = 3;
    
    public void StartQuickMatch()
    {
        matchmakingAttempts = 0;
        AttemptJoinRoom();
    }
    
    void AttemptJoinRoom()
    {
        var expectedProperties = new Hashtable
        {
            ["GameMode"] = PlayerPrefs.GetString("PreferredMode", "Deathmatch"),
            ["InProgress"] = false
        };
        
        PhotonNetwork.JoinRandomRoom(expectedProperties, 4);
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        matchmakingAttempts++;
        
        if (matchmakingAttempts < MAX_ATTEMPTS)
        {
            // Try with less strict requirements
            var relaxedProperties = new Hashtable { ["InProgress"] = false };
            PhotonNetwork.JoinRandomRoom(relaxedProperties, 4);
        }
        else
        {
            // Create new room
            CreateQuickMatchRoom();
        }
    }
}
```

### Room Creation
```csharp
void CreateQuickMatchRoom()
{
    string roomName = GenerateRoomName();
    
    var roomOptions = new RoomOptions
    {
        MaxPlayers = 4,
        PlayerTtl = 10000, // 10 seconds to reconnect
        EmptyRoomTtl = 5000, // 5 seconds before closing empty room
        CleanupCacheOnLeave = false, // Allow reconnection
        PublishUserId = true,
        CustomRoomProperties = GetDefaultRoomProperties(),
        CustomRoomPropertiesForLobby = new[] { "GameMode", "Map", "InProgress" }
    };
    
    PhotonNetwork.CreateRoom(roomName, roomOptions);
}
```

## Connection Quality Monitoring

### Ping Monitor
```csharp
public class ConnectionQualityMonitor : MonoBehaviourPun
{
    public event Action<ConnectionQuality> OnQualityChanged;
    
    private ConnectionQuality currentQuality;
    private float checkInterval = 1f;
    
    void Start()
    {
        InvokeRepeating(nameof(CheckConnectionQuality), 0f, checkInterval);
    }
    
    void CheckConnectionQuality()
    {
        if (!PhotonNetwork.IsConnected) return;
        
        int ping = PhotonNetwork.GetPing();
        var newQuality = EvaluateQuality(ping);
        
        if (newQuality != currentQuality)
        {
            currentQuality = newQuality;
            OnQualityChanged?.Invoke(currentQuality);
            AdjustGameSettings(currentQuality);
        }
    }
    
    ConnectionQuality EvaluateQuality(int ping)
    {
        return ping switch
        {
            < 50 => ConnectionQuality.Excellent,
            < 100 => ConnectionQuality.Good,
            < 150 => ConnectionQuality.Fair,
            < 200 => ConnectionQuality.Poor,
            _ => ConnectionQuality.Unplayable
        };
    }
}
```

### Adaptive Quality Settings
```csharp
void AdjustGameSettings(ConnectionQuality quality)
{
    switch (quality)
    {
        case ConnectionQuality.Poor:
        case ConnectionQuality.Unplayable:
            // Reduce update rates
            PhotonNetwork.SendRate = 30;
            PhotonNetwork.SerializationRate = 15;
            // Disable non-essential effects
            DisableParticleSync();
            break;
            
        case ConnectionQuality.Fair:
            PhotonNetwork.SendRate = 45;
            PhotonNetwork.SerializationRate = 20;
            break;
            
        default:
            // Restore full quality
            PhotonNetwork.SendRate = 60;
            PhotonNetwork.SerializationRate = 30;
            EnableAllFeatures();
            break;
    }
}
```

## Reconnection System

### Disconnect Handling
```csharp
public class ReconnectionManager : MonoBehaviourPunCallbacks
{
    private string lastRoomName;
    private bool wasInGame;
    private float reconnectTimeout = 10f;
    
    public override void OnDisconnected(DisconnectCause cause)
    {
        if (cause == DisconnectCause.DisconnectByClientLogic)
        {
            // Intentional disconnect
            ReturnToMainMenu();
            return;
        }
        
        // Unintentional disconnect
        if (wasInGame)
        {
            ShowReconnectDialog();
            StartReconnectTimer();
        }
        else
        {
            // Just return to menu if not in game
            ReturnToMainMenu();
        }
    }
    
    void AttemptReconnect()
    {
        if (!string.IsNullOrEmpty(lastRoomName))
        {
            PhotonNetwork.RejoinRoom(lastRoomName);
        }
        else
        {
            PhotonNetwork.Reconnect();
        }
    }
}
```

### Rejoin Flow
```csharp
public override void OnJoinedRoom()
{
    if (PhotonNetwork.CurrentRoom.CustomProperties.ContainsKey("InProgress"))
    {
        // Rejoin game in progress
        RejoinMatch();
    }
    else
    {
        // Normal lobby join
        ShowLobbyUI();
    }
}

void RejoinMatch()
{
    // Request current game state
    if (PhotonNetwork.IsMasterClient)
    {
        SendGameStateToPlayer(PhotonNetwork.LocalPlayer);
    }
    else
    {
        photonView.RPC("RequestGameState", RpcTarget.MasterClient);
    }
}
```

## Network Events

### Custom Events
```csharp
public class NetworkEventManager : MonoBehaviourPunCallbacks, IOnEventCallback
{
    // Event codes
    private const byte PLAYER_READY_EVENT = 1;
    private const byte GAME_START_EVENT = 2;
    private const byte MATCH_END_EVENT = 3;
    private const byte PLAYER_RESPAWN_EVENT = 4;
    
    public void SendPlayerReady(bool isReady)
    {
        object[] data = new object[] { PhotonNetwork.LocalPlayer.ActorNumber, isReady };
        
        RaiseEventOptions options = new RaiseEventOptions
        {
            Receivers = ReceiverGroup.All,
            CachingOption = EventCaching.DoNotCache
        };
        
        PhotonNetwork.RaiseEvent(PLAYER_READY_EVENT, data, options, SendOptions.SendReliable);
    }
    
    public void OnEvent(EventData photonEvent)
    {
        switch (photonEvent.Code)
        {
            case PLAYER_READY_EVENT:
                HandlePlayerReady(photonEvent.CustomData);
                break;
                
            case GAME_START_EVENT:
                HandleGameStart(photonEvent.CustomData);
                break;
                
            case MATCH_END_EVENT:
                HandleMatchEnd(photonEvent.CustomData);
                break;
        }
    }
}
```

## Performance Optimization

### Bandwidth Management
```csharp
public class BandwidthOptimizer : MonoBehaviour
{
    void OnEnable()
    {
        // Subscribe to scene changes
        SceneManager.sceneLoaded += OnSceneLoaded;
    }
    
    void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        if (scene.name.Contains("Menu"))
        {
            // Lower rates in menu
            PhotonNetwork.SendRate = 20;
            PhotonNetwork.SerializationRate = 10;
        }
        else if (scene.name.Contains("Game"))
        {
            // Higher rates in game
            PhotonNetwork.SendRate = 60;
            PhotonNetwork.SerializationRate = 30;
        }
    }
}
```

### Interest Management
```csharp
public class PlatformShooterInterestManagement : MonoBehaviourPunCallbacks
{
    // Only sync players within screen bounds + margin
    private float syncDistance = 20f;
    
    void Update()
    {
        if (!PhotonNetwork.IsConnected) return;
        
        // Update culling distance based on gameplay
        foreach (var player in FindObjectsOfType<PlayerController>())
        {
            float distance = Vector2.Distance(transform.position, player.transform.position);
            player.photonView.enabled = distance <= syncDistance;
        }
    }
}
```

## Error Recovery

### Connection Error Handling
```csharp
public class ErrorHandler : MonoBehaviourPunCallbacks
{
    public override void OnErrorInfo(ErrorInfo errorInfo)
    {
        Debug.LogError($"Photon Error: {errorInfo.Info}");
        
        switch (errorInfo.Info)
        {
            case ErrorCode.GameDoesNotExist:
                ShowError("Game no longer exists");
                ReturnToMatchmaking();
                break;
                
            case ErrorCode.GameFull:
                ShowError("Game is full");
                StartQuickMatch();
                break;
                
            case ErrorCode.UserBlocked:
                ShowError("Connection blocked");
                ReturnToMainMenu();
                break;
        }
    }
}
```

### Graceful Degradation
```csharp
public class DegradationManager
{
    public void HandlePoorConnection()
    {
        // Disable non-critical features
        DisableVoiceChat();
        ReduceParticleEffects();
        SimplifyNetworkUpdates();
        
        // Notify player
        ShowWarning("Poor connection detected - some features disabled");
    }
    
    public void RestoreFullFeatures()
    {
        EnableAllFeatures();
        HideWarning();
    }
}
```

## Best Practices

### 1. **Connection Lifecycle**
- Auto-connect on startup
- Save connection preferences
- Handle app pause/resume

### 2. **Player Experience**
- Show connection status clearly
- Provide reconnect options
- Minimize connection interruptions

### 3. **Network Efficiency**
- Use appropriate send rates
- Implement interest management
- Cache frequently used data

## Mobile Considerations

### Background Handling
```csharp
void OnApplicationPause(bool pauseStatus)
{
    if (pauseStatus)
    {
        // App going to background
        if (PhotonNetwork.IsConnected)
        {
            SaveConnectionState();
        }
    }
    else
    {
        // App returning to foreground
        if (ShouldReconnect())
        {
            AttemptReconnect();
        }
    }
}
```

### Battery Optimization
```csharp
public class BatteryOptimizer
{
    public void EnableLowPowerMode()
    {
        // Reduce network frequency
        PhotonNetwork.SendRate = 30;
        
        // Disable background keep-alive
        PhotonNetwork.KeepAliveInBackground = 0f;
        
        // Reduce particle sync
        LimitNetworkObjects();
    }
}
```

## Debugging Tools

### Connection Inspector
```csharp
public class ConnectionDebugUI : MonoBehaviour
{
    void OnGUI()
    {
        if (!Debug.isDebugBuild) return;
        
        GUILayout.BeginArea(new Rect(10, 10, 200, 300));
        
        GUILayout.Label($"State: {PhotonNetwork.NetworkClientState}");
        GUILayout.Label($"Ping: {PhotonNetwork.GetPing()}ms");
        GUILayout.Label($"Region: {PhotonNetwork.CloudRegion}");
        GUILayout.Label($"Room: {PhotonNetwork.CurrentRoom?.Name ?? "None"}");
        GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom?.PlayerCount ?? 0}");
        
        if (GUILayout.Button("Simulate Disconnect"))
        {
            PhotonNetwork.Disconnect();
        }
        
        if (GUILayout.Button("Force Reconnect"))
        {
            PhotonNetwork.Reconnect();
        }
        
        GUILayout.EndArea();
    }
}
```
