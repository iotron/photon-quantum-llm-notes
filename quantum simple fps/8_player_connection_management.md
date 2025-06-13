# Player Connection Management - Quantum Simple FPS

## Overview

Quantum Simple FPS implements a **performance-critical connection system** optimized for competitive first-person shooter gameplay. The connection management prioritizes low latency, stable connections, and robust anti-cheat measures while maintaining the fast-paced nature of FPS matches.

## Connection Architecture

### 1. **FPS-Optimized Stack**
- **Custom MenuUI**: Extended connection behavior
- **High-frequency updates**: 60+ tick rate support
- **Regional matchmaking**: Latency-based server selection
- **Connection validation**: Anti-cheat integration

### 2. **Connection Pipeline**
```
Launch → Region Selection → Skill Verification → Matchmaking → Team Assignment → Game
            ↓                      ↓                   ↓
    Ping Test Results      Rank Validation      Connection Quality Check
```

## Core Implementation

### Enhanced Connection Manager
```csharp
namespace SimpleFPS
{
    public class MenuUI : QuantumMenuConnectionBehaviourSDK
    {
        private bool _isBusy;
        private bool _isConnected;
        
        public override async Task<ConnectResult> ConnectAsync(QuantumMenuConnectArgs connectionArgs)
        {
            _isBusy = true;
            
            // Pre-connection setup
            await ValidateClientIntegrity();
            ConfigureFPSNetworkSettings();
            
            ConnectResult result = await base.ConnectAsync(connectionArgs);
            
            if (result.Success)
            {
                await PostConnectionSetup();
            }
            
            _isBusy = false;
            return result;
        }
        
        private void ConfigureFPSNetworkSettings()
        {
            // FPS-specific optimizations
            PhotonNetwork.SendRate = 60;
            PhotonNetwork.SerializationRate = 30;
            
            // Reduce interpolation delay
            PhotonNetwork.NetworkingClient.LocalPlayer.TagObject = new FPSPlayerSettings
            {
                InterpolationDelay = 50, // 50ms for FPS
                ExtrapolationLimit = 100,
                JitterBufferSize = 3
            };
        }
    }
}
```

### Connection Validation
```csharp
public class FPSConnectionValidator
{
    public async Task<bool> ValidateClientIntegrity()
    {
        // Hardware ID check
        string hwid = SystemInfo.deviceUniqueIdentifier;
        bool isValidHardware = await ValidateHardwareID(hwid);
        
        // Game files integrity
        bool filesIntact = await ValidateGameFiles();
        
        // Network conditions
        bool networkSuitable = await TestNetworkConditions();
        
        return isValidHardware && filesIntact && networkSuitable;
    }
    
    private async Task<bool> TestNetworkConditions()
    {
        // Ping test to multiple regions
        var pingResults = await TestMultipleRegions();
        
        // Packet loss test
        float packetLoss = await MeasurePacketLoss();
        
        // Jitter measurement
        float jitter = await MeasureNetworkJitter();
        
        return pingResults.Min() < 100 && packetLoss < 2f && jitter < 20f;
    }
}
```

## Regional Server Selection

### Automatic Region Selection
```csharp
public class RegionSelector : MonoBehaviourPunCallbacks
{
    private Dictionary<string, RegionPingResult> regionPings = new Dictionary<string, RegionPingResult>();
    
    public async Task SelectBestRegion()
    {
        // Test all available regions
        await PingAllRegions();
        
        // Select based on criteria
        var bestRegion = regionPings
            .Where(r => r.Value.PacketLoss < 1f)
            .OrderBy(r => r.Value.AveragePing)
            .First();
        
        PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = bestRegion.Key;
        
        // Store for reconnection
        PlayerPrefs.SetString("PreferredRegion", bestRegion.Key);
    }
    
    private class RegionPingResult
    {
        public float AveragePing;
        public float MinPing;
        public float MaxPing;
        public float PacketLoss;
        public float Jitter;
    }
}
```

### Manual Server Selection
```csharp
public class ServerSelector : MonoBehaviourPunCallbacks
{
    public void ConnectToSpecificServer(string region, string serverAddress = null)
    {
        // Override automatic selection
        PhotonNetwork.PhotonServerSettings.AppSettings.FixedRegion = region;
        
        if (!string.IsNullOrEmpty(serverAddress))
        {
            // Connect to community/custom server
            PhotonNetwork.PhotonServerSettings.AppSettings.Server = serverAddress;
            PhotonNetwork.PhotonServerSettings.AppSettings.UseNameServer = false;
        }
        
        PhotonNetwork.ConnectUsingSettings();
    }
}
```

## Competitive Matchmaking

### Skill-Based Connection
```csharp
public class CompetitiveMatchmaking : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class PlayerRankData
    {
        public int Elo = 1000;
        public string RankTier = "Silver";
        public float WinRate;
        public int MatchesPlayed;
        public float KDRatio;
    }
    
    public void FindCompetitiveMatch()
    {
        var rankData = LoadPlayerRankData();
        
        // Set matchmaking properties
        var expectedProperties = new Hashtable
        {
            ["MinElo"] = rankData.Elo - 200,
            ["MaxElo"] = rankData.Elo + 200,
            ["GameMode"] = "Competitive",
            ["AntiCheat"] = true
        };
        
        // Custom lobby for ranked
        TypedLobby rankedLobby = new TypedLobby("Ranked", LobbyType.SqlLobby);
        
        PhotonNetwork.JoinRandomRoom(expectedProperties, 10, MatchmakingMode.FillRoom, 
                                    rankedLobby, BuildSqlFilter(rankData));
    }
    
    private string BuildSqlFilter(PlayerRankData rankData)
    {
        // SQL lobby filter for skill-based matchmaking
        return $"C0 BETWEEN {rankData.Elo - 200} AND {rankData.Elo + 200}";
    }
}
```

### Connection Quality Requirements
```csharp
public class QualityGatekeeper : MonoBehaviourPunCallbacks
{
    private const int MAX_COMPETITIVE_PING = 80;
    private const float MAX_PACKET_LOSS = 0.5f;
    
    public override void OnJoinedRoom()
    {
        if (IsCompetitiveRoom())
        {
            StartCoroutine(MonitorConnectionQuality());
        }
    }
    
    IEnumerator MonitorConnectionQuality()
    {
        while (PhotonNetwork.InRoom)
        {
            var quality = MeasureConnectionQuality();
            
            if (quality.Ping > MAX_COMPETITIVE_PING || quality.PacketLoss > MAX_PACKET_LOSS)
            {
                ShowQualityWarning(quality);
                
                if (quality.Ping > 150)
                {
                    // Force disconnect from competitive
                    DisconnectFromCompetitive("Connection quality too poor for competitive play");
                }
            }
            
            yield return new WaitForSeconds(5f);
        }
    }
}
```

## Player Session Management

### Secure Session Handling
```csharp
public class SecureSessionManager : MonoBehaviourPunCallbacks
{
    private string sessionToken;
    private DateTime sessionExpiry;
    
    public async Task<bool> EstablishSecureSession()
    {
        // Generate secure session
        sessionToken = await RequestSessionToken();
        
        // Validate with backend
        bool isValid = await ValidateSession(sessionToken);
        
        if (isValid)
        {
            // Set secure properties
            var authData = new AuthenticationValues();
            authData.AuthType = CustomAuthenticationType.Custom;
            authData.AddAuthParameter("token", sessionToken);
            authData.AddAuthParameter("hwid", SystemInfo.deviceUniqueIdentifier);
            
            PhotonNetwork.AuthValues = authData;
        }
        
        return isValid;
    }
    
    public override void OnCustomAuthenticationResponse(Dictionary<string, object> data)
    {
        if (data.ContainsKey("banned") && (bool)data["banned"])
        {
            HandleBannedPlayer((string)data["reason"]);
        }
    }
}
```

### Player Data Persistence
```csharp
public class FPSPlayerDataManager
{
    [System.Serializable]
    public class FPSPlayerProfile
    {
        public string PlayerId;
        public string DisplayName;
        public PlayerRankData RankData;
        public LoadoutData[] Loadouts;
        public StatisticsData Stats;
        public List<string> UnlockedItems;
        public DateTime LastPlayed;
    }
    
    public void SyncPlayerProfile()
    {
        var profile = LoadLocalProfile();
        
        var props = new Hashtable
        {
            ["Elo"] = profile.RankData.Elo,
            ["Rank"] = profile.RankData.RankTier,
            ["Level"] = profile.Stats.PlayerLevel,
            ["PlayTime"] = profile.Stats.TotalPlayTime,
            ["Verified"] = IsVerifiedPlayer(profile)
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

## Connection State Machine

### State Management
```csharp
public class FPSConnectionStateMachine
{
    public enum ConnectionState
    {
        Offline,
        ValidatingClient,
        ConnectingToMaster,
        SelectingRegion,
        JoiningLobby,
        Matchmaking,
        JoiningRoom,
        TeamSelection,
        LoadingMap,
        InGame,
        Reconnecting,
        Banned
    }
    
    private ConnectionState currentState;
    private float stateTimeout = 30f;
    
    public void TransitionToState(ConnectionState newState)
    {
        LogStateTransition(currentState, newState);
        
        currentState = newState;
        HandleStateEntry(newState);
        
        // Start timeout timer
        if (RequiresTimeout(newState))
        {
            StartStateTimeout(newState);
        }
    }
    
    private void HandleStateEntry(ConnectionState state)
    {
        switch (state)
        {
            case ConnectionState.ValidatingClient:
                StartClientValidation();
                break;
                
            case ConnectionState.SelectingRegion:
                StartRegionSelection();
                break;
                
            case ConnectionState.Matchmaking:
                StartMatchmaking();
                break;
        }
    }
}
```

## Network Optimization

### Lag Compensation
```csharp
public class FPSLagCompensation : MonoBehaviourPun
{
    private CircularBuffer<PlayerSnapshot> playerHistory = new CircularBuffer<PlayerSnapshot>(60);
    
    public void OnPhotonSerializeView(PhotonStream stream, PhotonMessageInfo info)
    {
        if (stream.IsWriting)
        {
            // Send with timestamp
            stream.SendNext(PhotonNetwork.ServerTimestamp);
            stream.SendNext(transform.position);
            stream.SendNext(transform.rotation);
            stream.SendNext(currentVelocity);
        }
        else
        {
            // Receive and compensate
            int timestamp = (int)stream.ReceiveNext();
            Vector3 position = (Vector3)stream.ReceiveNext();
            Quaternion rotation = (Quaternion)stream.ReceiveNext();
            Vector3 velocity = (Vector3)stream.ReceiveNext();
            
            // Calculate latency
            int latency = PhotonNetwork.ServerTimestamp - timestamp;
            
            // Extrapolate position
            Vector3 extrapolatedPos = position + (velocity * (latency / 1000f));
            
            // Smooth interpolation
            StartCoroutine(InterpolatePosition(extrapolatedPos, rotation));
        }
    }
}
```

### Bandwidth Optimization
```csharp
public class FPSBandwidthOptimizer : MonoBehaviour
{
    public void OptimizeForGameplay()
    {
        // Prioritize game-critical data
        PhotonNetwork.SendRate = 60;
        PhotonNetwork.SerializationRate = 30;
        
        // Reduce non-critical updates
        DisableNonEssentialSync();
        
        // Compress data
        EnableDataCompression();
        
        // Cull distant players
        SetCullingDistance(100f);
    }
    
    private void EnableDataCompression()
    {
        // Custom serialization for common FPS data
        PhotonPeer.RegisterType(typeof(CompressedPlayerState), 100, 
            SerializePlayerState, DeserializePlayerState);
    }
}
```

## Reconnection System

### Match Reconnection
```csharp
public class FPSReconnectionManager : MonoBehaviourPunCallbacks
{
    private string lastRoomName;
    private string lastMatchId;
    private Team lastTeam;
    
    public override void OnDisconnected(DisconnectCause cause)
    {
        if (cause != DisconnectCause.DisconnectByClientLogic)
        {
            // Unintentional disconnect during match
            if (WasInActiveMatch())
            {
                SaveMatchState();
                AttemptReconnection();
            }
        }
    }
    
    private void AttemptReconnection()
    {
        StartCoroutine(ReconnectionSequence());
    }
    
    IEnumerator ReconnectionSequence()
    {
        ShowReconnectingUI();
        
        // Try to reconnect multiple times
        for (int i = 0; i < 3; i++)
        {
            yield return new WaitForSeconds(2f);
            
            if (PhotonNetwork.ReconnectAndRejoin())
            {
                yield break;
            }
        }
        
        // Fallback to new connection
        PhotonNetwork.ConnectUsingSettings();
    }
    
    public override void OnJoinedRoom()
    {
        if (IsRejoiningMatch())
        {
            RestorePlayerState();
            RequestCurrentMatchState();
        }
    }
}
```

## Anti-Cheat Integration

### Client Validation
```csharp
public class AntiCheatClient : MonoBehaviourPunCallbacks
{
    private float lastHeartbeat;
    private string clientHash;
    
    void Start()
    {
        // Generate client hash
        clientHash = GenerateClientFingerprint();
        
        // Start heartbeat
        InvokeRepeating(nameof(SendHeartbeat), 0f, 5f);
    }
    
    void SendHeartbeat()
    {
        if (PhotonNetwork.IsConnected)
        {
            var heartbeatData = new Hashtable
            {
                ["Hash"] = clientHash,
                ["Time"] = PhotonNetwork.ServerTimestamp,
                ["Stats"] = GatherClientStats()
            };
            
            PhotonNetwork.RaiseEvent(HEARTBEAT_EVENT, heartbeatData, 
                RaiseEventOptions.Default, SendOptions.SendReliable);
        }
    }
    
    private string GatherClientStats()
    {
        // Collect performance metrics
        return JsonUtility.ToJson(new
        {
            FPS = GetAverageFPS(),
            Ping = PhotonNetwork.GetPing(),
            ProcessCount = System.Diagnostics.Process.GetProcesses().Length,
            MemoryUsage = GC.GetTotalMemory(false)
        });
    }
}
```

## Error Handling

### Connection Failures
```csharp
public class FPSErrorHandler : MonoBehaviourPunCallbacks
{
    public override void OnDisconnected(DisconnectCause cause)
    {
        switch (cause)
        {
            case DisconnectCause.InvalidAuthentication:
                HandleAuthenticationFailure();
                break;
                
            case DisconnectCause.MaxCcuReached:
                ShowServerFullMessage();
                OfferAlternativeRegions();
                break;
                
            case DisconnectCause.InvalidRegion:
                ResetToDefaultRegion();
                break;
                
            case DisconnectCause.ClientTimeout:
                if (WasInCompetitiveMatch())
                {
                    ApplyAbandonPenalty();
                }
                break;
        }
    }
    
    private void HandleAuthenticationFailure()
    {
        // Check if banned
        CheckBanStatus((isBanned, reason) =>
        {
            if (isBanned)
            {
                ShowBanMessage(reason);
            }
            else
            {
                // Retry with fresh token
                RefreshAuthenticationToken();
            }
        });
    }
}
```

## Performance Monitoring

### Connection Metrics
```csharp
public class FPSNetworkMetrics : MonoBehaviour
{
    private NetworkStats currentStats;
    
    void Update()
    {
        if (PhotonNetwork.IsConnected)
        {
            UpdateNetworkStats();
            
            if (ShouldShowNetworkWarning())
            {
                DisplayNetworkWarning();
            }
        }
    }
    
    void UpdateNetworkStats()
    {
        currentStats = new NetworkStats
        {
            Ping = PhotonNetwork.GetPing(),
            IncomingRate = PhotonNetwork.NetworkingClient.TrafficStatsIncoming.TotalPacketBytes,
            OutgoingRate = PhotonNetwork.NetworkingClient.TrafficStatsOutgoing.TotalPacketBytes,
            PacketLoss = CalculatePacketLoss(),
            Jitter = CalculateJitter()
        };
    }
    
    void OnGUI()
    {
        if (ShowNetStats)
        {
            GUI.Box(new Rect(Screen.width - 210, 10, 200, 100), "Network Stats");
            GUI.Label(new Rect(Screen.width - 200, 30, 180, 20), 
                $"Ping: {currentStats.Ping}ms");
            GUI.Label(new Rect(Screen.width - 200, 50, 180, 20), 
                $"Loss: {currentStats.PacketLoss:F1}%");
            GUI.Label(new Rect(Screen.width - 200, 70, 180, 20), 
                $"Jitter: {currentStats.Jitter:F1}ms");
        }
    }
}
```

## Best Practices

### 1. **Competitive Integrity**
- Validate clients before matches
- Monitor for suspicious behavior
- Implement replay system

### 2. **Performance First**
- Minimize latency at all costs
- Optimize data transmission
- Predictive networking

### 3. **Reliability**
- Robust reconnection system
- Graceful degradation
- Clear error communication

## Debugging Tools

### Network Debugger
```csharp
public class FPSNetworkDebugger : MonoBehaviour
{
    void OnGUI()
    {
        if (!Debug.isDebugBuild) return;
        
        GUILayout.BeginArea(new Rect(10, 10, 400, 600));
        GUILayout.Label("=== FPS Network Debug ===");
        
        // Connection info
        GUILayout.Label($"State: {PhotonNetwork.NetworkClientState}");
        GUILayout.Label($"Region: {PhotonNetwork.CloudRegion}");
        GUILayout.Label($"Ping: {PhotonNetwork.GetPing()}ms");
        GUILayout.Label($"Server Time: {PhotonNetwork.ServerTimestamp}");
        
        // Room info
        if (PhotonNetwork.InRoom)
        {
            GUILayout.Label($"Room: {PhotonNetwork.CurrentRoom.Name}");
            GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom.PlayerCount}");
            GUILayout.Label($"Master: {PhotonNetwork.IsMasterClient}");
        }
        
        // Actions
        if (GUILayout.Button("Simulate Lag Spike"))
        {
            StartCoroutine(SimulateLagSpike());
        }
        
        if (GUILayout.Button("Force Disconnect"))
        {
            PhotonNetwork.Disconnect();
        }
        
        if (GUILayout.Button("Toggle Packet Loss"))
        {
            TogglePacketLossSimulation();
        }
        
        GUILayout.EndArea();
    }
}
```
