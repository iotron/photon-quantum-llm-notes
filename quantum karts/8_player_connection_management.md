# Player Connection Management - Quantum Karts

## Overview

Quantum Karts utilizes **Photon Realtime** for network connectivity and the **Quantum Menu** framework for connection management. The system handles online multiplayer connections, player authentication, and seamless transitions between lobby and gameplay.

## Connection Architecture

### 1. **Network Stack**
- **Photon Cloud**: Global server infrastructure
- **Photon Realtime**: Room-based networking
- **Quantum Protocol**: Deterministic simulation sync
- **UDP Transport**: Low-latency communication

### 2. **Connection Layers**
```
Unity Client
    ↓
Quantum Menu Connection Manager
    ↓
Photon Realtime Client
    ↓
Photon Cloud (Master Server → Game Server)
    ↓
Quantum Simulation
```

## Core Components

### QuantumMenuConnection
```csharp
public class QuantumMenuConnection : QuantumMenuConnectionBehaviourSDK
{
    protected override void OnConnectedToMaster()
    {
        base.OnConnectedToMaster();
        
        // Auto-join lobby for matchmaking
        if (PhotonNetwork.InLobby == false)
        {
            PhotonNetwork.JoinLobby();
        }
    }
    
    public override void OnJoinedRoom()
    {
        base.OnJoinedRoom();
        
        // Initialize player data
        SetupLocalPlayer();
        
        // Notify UI
        OnRoomJoined?.Invoke(PhotonNetwork.CurrentRoom);
    }
}
```

### Connection Configuration
```csharp
public class KartConnectionConfig
{
    public AppSettings AppSettings = new AppSettings
    {
        AppIdRealtime = "your-app-id",
        FixedRegion = "us",
        Protocol = ConnectionProtocol.Udp,
        EnableLobbyStatistics = true
    };
    
    public ConnectionSettings Settings = new ConnectionSettings
    {
        MaxPlayers = 8,
        NetworkLogging = DebugLevel.WARNING,
        SendRate = 60,
        SerializationRate = 15
    };
}
```

## Connection Flow

### 1. **Initial Connection**
```csharp
public class ConnectionManager : MonoBehaviourPunCallbacks
{
    public void ConnectToPhoton()
    {
        // Set player name
        PhotonNetwork.NickName = PlayerPrefs.GetString("PlayerName", "Racer");
        
        // Configure settings
        PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = GetBestRegion();
        
        // Connect
        PhotonNetwork.ConnectUsingSettings();
    }
    
    public override void OnConnectedToMaster()
    {
        Debug.Log($"Connected to {PhotonNetwork.CloudRegion} region");
        PhotonNetwork.JoinLobby();
    }
}
```

### 2. **Matchmaking**
```csharp
public class Matchmaking : MonoBehaviourPunCallbacks
{
    // Quick Match
    public void QuickMatch()
    {
        var expectedProperties = new Hashtable
        {
            ["GameMode"] = "Race",
            ["Started"] = false
        };
        
        PhotonNetwork.JoinRandomRoom(expectedProperties, 8);
    }
    
    // Create Room
    public void CreateRoom(string roomName)
    {
        var roomOptions = new RoomOptions
        {
            MaxPlayers = 8,
            IsVisible = true,
            IsOpen = true,
            PublishUserId = true,
            CustomRoomProperties = GetDefaultRoomProperties(),
            CustomRoomPropertiesForLobby = new[] { "GameMode", "Track" }
        };
        
        PhotonNetwork.CreateRoom(roomName, roomOptions);
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        // No suitable room found, create one
        CreateRoom(null);
    }
}
```

### 3. **Player Authentication**
```csharp
public class PlayerAuthentication : MonoBehaviourPunCallbacks
{
    public void AuthenticatePlayer()
    {
        var authValues = new AuthenticationValues();
        
        // Custom authentication
        if (HasCustomAuth())
        {
            authValues.AuthType = CustomAuthenticationType.Custom;
            authValues.AddAuthParameter("token", GetAuthToken());
            authValues.AddAuthParameter("userId", GetUserId());
        }
        
        PhotonNetwork.AuthValues = authValues;
    }
    
    public override void OnCustomAuthenticationResponse(Dictionary<string, object> data)
    {
        // Handle auth response
        if (data.ContainsKey("userId"))
        {
            string userId = (string)data["userId"];
            SaveUserId(userId);
        }
    }
}
```

## Connection States

### State Management
```csharp
public enum ConnectionState
{
    Disconnected,
    Connecting,
    Connected,
    JoiningLobby,
    InLobby,
    JoiningRoom,
    InRoom,
    StartingGame,
    InGame,
    Disconnecting
}

public class ConnectionStateManager
{
    public ConnectionState CurrentState { get; private set; }
    public event Action<ConnectionState> OnStateChanged;
    
    public void TransitionTo(ConnectionState newState)
    {
        if (IsValidTransition(CurrentState, newState))
        {
            CurrentState = newState;
            OnStateChanged?.Invoke(newState);
        }
    }
}
```

### Connection Quality Monitoring
```csharp
public class ConnectionQualityMonitor : MonoBehaviourPun
{
    private float pingUpdateInterval = 1f;
    private ConnectionQuality quality;
    
    void Start()
    {
        InvokeRepeating(nameof(UpdateConnectionQuality), 0f, pingUpdateInterval);
    }
    
    void UpdateConnectionQuality()
    {
        int ping = PhotonNetwork.GetPing();
        
        quality = ping switch
        {
            < 50 => ConnectionQuality.Excellent,
            < 100 => ConnectionQuality.Good,
            < 150 => ConnectionQuality.Fair,
            _ => ConnectionQuality.Poor
        };
        
        UpdateQualityUI(quality, ping);
    }
}
```

## Player Session Management

### Session Data
```csharp
[System.Serializable]
public class PlayerSession
{
    public string PlayerId;
    public string DisplayName;
    public int KartSelection;
    public int ColorSelection;
    public PlayerStatistics Stats;
    public DateTime ConnectionTime;
    
    public void SaveToCloud()
    {
        var data = new Hashtable
        {
            ["stats"] = JsonUtility.ToJson(Stats),
            ["kart"] = KartSelection,
            ["color"] = ColorSelection
        };
        PhotonNetwork.LocalPlayer.SetCustomProperties(data);
    }
}
```

### Reconnection System
```csharp
public class ReconnectionManager : MonoBehaviourPunCallbacks
{
    private string lastRoomName;
    private bool wasInGame;
    
    public void EnableReconnection()
    {
        // Save room info before disconnect
        if (PhotonNetwork.InRoom)
        {
            lastRoomName = PhotonNetwork.CurrentRoom.Name;
            wasInGame = QuantumRunner.Default != null;
            SaveGameState();
        }
    }
    
    public void AttemptReconnection()
    {
        if (!string.IsNullOrEmpty(lastRoomName))
        {
            PhotonNetwork.RejoinRoom(lastRoomName);
        }
    }
    
    public override void OnJoinedRoom()
    {
        if (wasInGame)
        {
            // Rejoin Quantum game in progress
            RestoreGameState();
            RejoinQuantumGame();
        }
    }
}
```

## Network Optimization

### Data Synchronization
```csharp
public class PlayerDataSync : MonoBehaviourPunCallbacks
{
    private float syncInterval = 0.5f;
    private Hashtable cachedProperties = new Hashtable();
    
    public void SetPlayerProperty(string key, object value)
    {
        cachedProperties[key] = value;
        
        // Batch updates
        if (!IsInvoking(nameof(FlushProperties)))
        {
            Invoke(nameof(FlushProperties), syncInterval);
        }
    }
    
    private void FlushProperties()
    {
        if (cachedProperties.Count > 0)
        {
            PhotonNetwork.LocalPlayer.SetCustomProperties(cachedProperties);
            cachedProperties.Clear();
        }
    }
}
```

### Bandwidth Management
```csharp
public class BandwidthOptimizer
{
    public void OptimizeForLobby()
    {
        PhotonNetwork.SendRate = 30;
        PhotonNetwork.SerializationRate = 10;
    }
    
    public void OptimizeForGameplay()
    {
        PhotonNetwork.SendRate = 60;
        PhotonNetwork.SerializationRate = 30;
    }
    
    public void AdaptToConnectionQuality(ConnectionQuality quality)
    {
        switch (quality)
        {
            case ConnectionQuality.Poor:
                PhotonNetwork.SendRate = 30;
                break;
            case ConnectionQuality.Fair:
                PhotonNetwork.SendRate = 45;
                break;
            default:
                PhotonNetwork.SendRate = 60;
                break;
        }
    }
}
```

## Error Handling

### Disconnect Handling
```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    switch (cause)
    {
        case DisconnectCause.DisconnectByClientLogic:
            // Intentional disconnect
            HandleCleanDisconnect();
            break;
            
        case DisconnectCause.ServerTimeout:
        case DisconnectCause.ClientTimeout:
            // Connection lost
            ShowReconnectDialog();
            break;
            
        case DisconnectCause.MaxCcuReached:
            ShowError("Server capacity reached");
            break;
            
        case DisconnectCause.InvalidAuthentication:
            HandleAuthenticationFailure();
            break;
            
        default:
            ShowError($"Connection lost: {cause}");
            break;
    }
}
```

### Recovery Strategies
```csharp
public class ConnectionRecovery
{
    private int maxRetries = 3;
    private float retryDelay = 2f;
    
    public async void RecoverConnection(DisconnectCause cause)
    {
        for (int i = 0; i < maxRetries; i++)
        {
            UpdateUI($"Reconnecting... Attempt {i + 1}/{maxRetries}");
            
            await Task.Delay((int)(retryDelay * 1000));
            
            if (PhotonNetwork.Reconnect())
            {
                return;
            }
        }
        
        OnRecoveryFailed();
    }
}
```

## Advanced Features

### 1. **Region Selection**
```csharp
public class RegionSelector
{
    public async void SelectBestRegion()
    {
        PhotonNetwork.NetworkingClient.EnableLobbyStatistics = true;
        var pingResults = await PhotonNetwork.NetworkingClient.GetRegions();
        
        var bestRegion = pingResults
            .Where(r => r.Ping < 150)
            .OrderBy(r => r.Ping)
            .FirstOrDefault();
            
        if (bestRegion != null)
        {
            PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = bestRegion.Code;
        }
    }
}
```

### 2. **Connection Persistence**
```csharp
public class PersistentConnection
{
    public void SaveConnectionData()
    {
        PlayerPrefs.SetString("LastRegion", PhotonNetwork.CloudRegion);
        PlayerPrefs.SetString("LastRoom", PhotonNetwork.CurrentRoom?.Name ?? "");
        PlayerPrefs.SetString("PlayerId", PhotonNetwork.LocalPlayer.UserId);
    }
    
    public void RestoreConnectionData()
    {
        string lastRegion = PlayerPrefs.GetString("LastRegion");
        if (!string.IsNullOrEmpty(lastRegion))
        {
            PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = lastRegion;
        }
    }
}
```

### 3. **Cross-Platform Support**
```csharp
public class CrossPlatformConnection
{
    public void ConfigureForPlatform()
    {
        #if UNITY_MOBILE
        // Mobile optimizations
        PhotonNetwork.SendRate = 30;
        PhotonNetwork.EnableCloseConnection = true;
        #elif UNITY_CONSOLE
        // Console settings
        PhotonNetwork.SendRate = 60;
        PhotonNetwork.KeepAliveInBackground = 5f;
        #else
        // PC settings
        PhotonNetwork.SendRate = 60;
        #endif
    }
}
```

## Best Practices

1. **Connection Lifecycle**
   - Clean disconnect on app pause/exit
   - Implement proper timeout handling
   - Save state before disconnecting

2. **Network Efficiency**
   - Use interest management
   - Implement data compression
   - Batch network updates

3. **User Experience**
   - Show connection status clearly
   - Provide reconnection options
   - Handle region selection smoothly

## Debugging Tools

### Connection Inspector
```csharp
public class ConnectionDebugger : MonoBehaviour
{
    void OnGUI()
    {
        if (!Debug.isDebugBuild) return;
        
        GUILayout.BeginArea(new Rect(10, 10, 300, 500));
        GUILayout.Label($"State: {PhotonNetwork.NetworkClientState}");
        GUILayout.Label($"Region: {PhotonNetwork.CloudRegion}");
        GUILayout.Label($"Ping: {PhotonNetwork.GetPing()}ms");
        GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom?.PlayerCount ?? 0}");
        GUILayout.Label($"Send Rate: {PhotonNetwork.SendRate}");
        GUILayout.Label($"In/Out: {PhotonNetwork.NetworkingClient.TrafficStatsIncoming.TotalPacketBytes}/" +
                       $"{PhotonNetwork.NetworkingClient.TrafficStatsOutgoing.TotalPacketBytes}");
        GUILayout.EndArea();
    }
}
```
