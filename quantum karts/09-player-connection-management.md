# Player Connection Management - Quantum Karts

Quantum Karts implements a player connection system designed for racing games, handling both human players and AI bots. The system ensures races continue smoothly even when players disconnect, with AI taking over abandoned karts.

## Player Registration System

### PlayerManager Architecture

**File: `/Assets/Scripts/Managers/PlayerManager.cs`**

```csharp
public class PlayerManager : MonoSingleton<PlayerManager>
{
    public Dictionary<PlayerRef, KartViewController> PlayerKarts { get; private set; } = new();
    public Dictionary<PlayerRef, KartViewController> BotKarts { get; private set; } = new();
    
    public void RegisterPlayer(QuantumGame game, KartViewController kartView)
    {
        if (kartView.isAI)
        {
            BotKarts[kartView._AIIndex] = kartView;
        }
        else
        {
            PlayerKarts[kartView.PlayerRef] = kartView;
        }
        
        // Register local player for camera and input
        if (game.GetLocalPlayers().Count > 0 && 
            kartView.PlayerRef == game.GetLocalPlayers()[0])
        {
            LocalPlayerManager.Instance.RegisterLocalPlayer(kartView);
        }
    }
    
    public void UnregisterPlayer(QuantumGame game, KartViewController kartView)
    {
        PlayerKarts.Remove(kartView.PlayerRef);
    }
}
```

### Local Player Management

**File: `/Assets/Scripts/Managers/LocalPlayerManager.cs`**

```csharp
public class LocalPlayerManager : MonoSingleton<LocalPlayerManager>
{
    [SerializeField] private FP _predictionCullingRange;
    [SerializeField] private FP _predictionCullingFowardOffset;
    
    public QuantumEntityView LocalPlayerView { get; private set; }
    public KartViewController LocalPlayerKartView { get; private set; }
    public EntityRef LocalPlayerEntity { get; private set; }
    public PlayerRef LocalPlayerRef { get; private set; }
    
    public void RegisterLocalPlayer(KartViewController localPlayerKartView)
    {
        LocalPlayerView = localPlayerKartView.EntityView;
        LocalPlayerKartView = localPlayerKartView;
        LocalPlayerEntity = localPlayerKartView.EntityView.EntityRef;
        LocalPlayerRef = localPlayerKartView.PlayerRef;
        
        // Add prediction culling for performance
        var predictionCullingController = localPlayerKartView.gameObject
            .AddComponent<PredictionCullingController>();
        predictionCullingController.Range = _predictionCullingRange;
        predictionCullingController.FowardOffset = _predictionCullingFowardOffset;
    }
}
```

## Connection Flow

### Player Initialization

```csharp
public class KartPlayerInitializer : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        var playerData = f.GetPlayerData(player);
        if (playerData == null) return;
        
        // Determine if this is a bot or human player
        bool isBot = playerData.IsBot;
        
        // Create kart entity
        var kartEntity = f.Create(playerData.PlayerAvatar);
        
        // Set up player components
        if (f.Unsafe.TryGetPointer<PlayerLink>(kartEntity, out var playerLink))
        {
            playerLink->PlayerRef = player;
            playerLink->IsBot = isBot;
        }
        
        // Initialize kart stats
        if (f.Unsafe.TryGetPointer<KartStats>(kartEntity, out var stats))
        {
            InitializeKartStats(stats, playerData);
        }
        
        // Position at starting grid
        PositionAtGrid(f, kartEntity, player);
        
        // Fire connection event
        f.Events.PlayerConnected(player, kartEntity, isBot);
    }
    
    private void InitializeKartStats(KartStats* stats, RuntimePlayer playerData)
    {
        // Load kart configuration from player data
        var kartConfig = LoadKartConfiguration(playerData.PlayerAvatar);
        
        stats->MaxSpeed = kartConfig.MaxSpeed;
        stats->Acceleration = kartConfig.Acceleration;
        stats->Handling = kartConfig.Handling;
        stats->Weight = kartConfig.Weight;
    }
}
```

## Disconnection Handling

### AI Takeover System

```csharp
public class PlayerDisconnectHandler : SystemMainThread
{
    public override void Update(Frame f)
    {
        var filter = f.Filter<PlayerLink, KartController>();
        
        while (filter.NextUnsafe(out var entity, out var playerLink, out var kartController))
        {
            var inputFlags = f.GetPlayerInputFlags(playerLink->PlayerRef);
            bool isDisconnected = (inputFlags & DeterministicInputFlags.PlayerNotPresent) != 0;
            
            if (isDisconnected && !playerLink->IsBot && !playerLink->HasDisconnected)
            {
                HandlePlayerDisconnection(f, entity, playerLink, kartController);
            }
        }
    }
    
    private void HandlePlayerDisconnection(Frame f, EntityRef entity, 
        PlayerLink* playerLink, KartController* kartController)
    {
        playerLink->HasDisconnected = true;
        playerLink->DisconnectTime = f.Time;
        
        // Convert to AI control
        ConvertToAI(f, entity, playerLink, kartController);
        
        // Notify other systems
        f.Events.PlayerDisconnected(playerLink->PlayerRef);
    }
    
    private void ConvertToAI(Frame f, EntityRef entity, 
        PlayerLink* playerLink, KartController* kartController)
    {
        // Mark as bot
        playerLink->IsBot = true;
        
        // Add AI controller component
        f.Add(entity, new AIDriver
        {
            Difficulty = AIDriver.DifficultyLevel.Medium,
            PersonalityType = DetermineAIPersonality()
        });
        
        // Keep racing position and stats
        // AI will continue from current position
    }
}
```

### Reconnection Support

```csharp
public class KartReconnectionHandler : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        // Check if this is a reconnection
        var playerData = f.GetPlayerData(player);
        if (string.IsNullOrEmpty(playerData?.ReconnectionToken)) return;
        
        // Find disconnected kart
        var filter = f.Filter<PlayerLink, Transform3D>();
        while (filter.NextUnsafe(out var entity, out var playerLink, out var transform))
        {
            if (playerLink->DisconnectedPlayerId == playerData.ReconnectionToken)
            {
                HandleReconnection(f, entity, player, playerLink);
                break;
            }
        }
    }
    
    private void HandleReconnection(Frame f, EntityRef kartEntity, 
        PlayerRef newPlayerRef, PlayerLink* playerLink)
    {
        // Restore player control
        playerLink->PlayerRef = newPlayerRef;
        playerLink->IsBot = false;
        playerLink->HasDisconnected = false;
        
        // Remove AI component
        f.Remove<AIDriver>(kartEntity);
        
        // Calculate time penalty
        var disconnectDuration = f.Time - playerLink->DisconnectTime;
        ApplyReconnectionPenalty(f, kartEntity, disconnectDuration);
        
        f.Events.PlayerReconnected(newPlayerRef, kartEntity);
    }
}
```

## Race State Preservation

### Mid-Race Connection Handling

```csharp
public unsafe class RaceStateManager : SystemMainThread
{
    public struct PlayerRaceState
    {
        public int CurrentLap;
        public int CheckpointIndex;
        public FP RaceTime;
        public int Position;
        public bool HasFinished;
    }
    
    private Dictionary<string, PlayerRaceState> _disconnectedStates = new();
    
    public void OnPlayerDisconnecting(Frame f, PlayerRef player)
    {
        var filter = f.Filter<PlayerLink, RaceProgress>();
        while (filter.NextUnsafe(out var entity, out var link, out var progress))
        {
            if (link->PlayerRef == player)
            {
                // Store race state
                var state = new PlayerRaceState
                {
                    CurrentLap = progress->CurrentLap,
                    CheckpointIndex = progress->LastCheckpoint,
                    RaceTime = progress->TotalRaceTime,
                    Position = progress->Position,
                    HasFinished = progress->HasFinished
                };
                
                var playerId = f.GetPlayerData(player)?.ClientId;
                if (!string.IsNullOrEmpty(playerId))
                {
                    _disconnectedStates[playerId] = state;
                }
                break;
            }
        }
    }
    
    public bool TryRestoreRaceState(Frame f, string playerId, EntityRef kartEntity)
    {
        if (_disconnectedStates.TryGetValue(playerId, out var state))
        {
            if (f.Unsafe.TryGetPointer<RaceProgress>(kartEntity, out var progress))
            {
                // Restore race progress
                progress->CurrentLap = state.CurrentLap;
                progress->LastCheckpoint = state.CheckpointIndex;
                progress->TotalRaceTime = state.RaceTime;
                progress->Position = state.Position;
                progress->HasFinished = state.HasFinished;
                
                _disconnectedStates.Remove(playerId);
                return true;
            }
        }
        return false;
    }
}
```

## Network Quality Monitoring

### Per-Player Connection Stats

```csharp
public class KartNetworkMonitor : QuantumEntityViewComponent
{
    private PlayerRef _playerRef;
    private NetworkQualityIndicator _indicator;
    
    public override void OnActivate(Frame frame)
    {
        var playerLink = GetPredictedQuantumComponent<PlayerLink>();
        if (playerLink != null)
        {
            _playerRef = playerLink.PlayerRef;
            _indicator = GetComponentInChildren<NetworkQualityIndicator>();
        }
    }
    
    public override void OnUpdateView()
    {
        if (!QuantumRunner.Default.Game.GetLocalPlayers().Contains(_playerRef))
            return;
            
        var stats = QuantumRunner.Default.Session.Stats;
        
        // Update network indicator
        _indicator.SetPing(stats.Ping);
        _indicator.SetPacketLoss(stats.PacketLoss);
        
        // Show warning for poor connection
        if (stats.Ping > 150 || stats.PacketLoss > 0.03f)
        {
            _indicator.ShowWarning();
        }
    }
}
```

## Split-Screen Support

### Multiple Local Players

```csharp
public class SplitScreenManager : MonoBehaviour
{
    [SerializeField] private Camera[] playerCameras;
    [SerializeField] private Canvas[] playerCanvases;
    
    public void SetupSplitScreen(List<PlayerRef> localPlayers)
    {
        int playerCount = localPlayers.Count;
        
        for (int i = 0; i < playerCameras.Length; i++)
        {
            if (i < playerCount)
            {
                ConfigurePlayerView(i, localPlayers[i], playerCount);
                playerCameras[i].gameObject.SetActive(true);
                playerCanvases[i].gameObject.SetActive(true);
            }
            else
            {
                playerCameras[i].gameObject.SetActive(false);
                playerCanvases[i].gameObject.SetActive(false);
            }
        }
    }
    
    private void ConfigurePlayerView(int index, PlayerRef player, int totalPlayers)
    {
        // Set camera viewport
        switch (totalPlayers)
        {
            case 1:
                playerCameras[index].rect = new Rect(0, 0, 1, 1);
                break;
            case 2:
                // Horizontal split
                playerCameras[index].rect = index == 0 
                    ? new Rect(0, 0.5f, 1, 0.5f) 
                    : new Rect(0, 0, 1, 0.5f);
                break;
            case 3:
            case 4:
                // Quad split
                float x = index % 2 == 0 ? 0 : 0.5f;
                float y = index < 2 ? 0.5f : 0;
                playerCameras[index].rect = new Rect(x, y, 0.5f, 0.5f);
                break;
        }
        
        // Assign UI canvas to camera
        playerCanvases[index].worldCamera = playerCameras[index];
    }
}
```

## Connection Events

### Race-Specific Events

```csharp
public class RaceConnectionEvents : QuantumCallbacks
{
    public override void OnPlayerAdded(PlayerRef player, QuantumGame game)
    {
        Debug.Log($"Player {player} joined the race");
        
        // Update UI
        UpdatePlayerList();
        
        // Check if race should wait
        if (IsInLobby())
        {
            ResetLobbyTimer();
        }
    }
    
    public override void OnPlayerRemoved(PlayerRef player, QuantumGame game)
    {
        Debug.Log($"Player {player} left the race");
        
        // Update positions if race is active
        if (IsRaceActive())
        {
            RecalculatePositions();
        }
    }
    
    public override void OnPlayerDataSet(PlayerRef player, QuantumGame game)
    {
        var playerData = game.GetPlayerData(player);
        Debug.Log($"Player {player} data updated: {playerData.PlayerNickname}");
        
        // Update player nameplate
        UpdatePlayerNameplate(player, playerData.PlayerNickname);
    }
}
```

## Best Practices

1. **Convert disconnected players to AI** to maintain race flow
2. **Store race progress** for potential reconnections
3. **Handle split-screen gracefully** for local multiplayer
4. **Monitor connection quality** per player
5. **Implement reconnection penalties** to prevent abuse
6. **Test with various disconnection scenarios** during races
7. **Update UI immediately** when players connect/disconnect
8. **Consider bandwidth** for split-screen scenarios

## Common Patterns

### Late Join Spectator Mode

```csharp
public void HandleLateJoin(PlayerRef player)
{
    var frame = QuantumRunner.Default.Game.Frames.Verified;
    
    if (frame.Global->RaceState == RaceState.InProgress)
    {
        // Create spectator entity
        var spectator = frame.Create(SpectatorPrototype);
        frame.Add(spectator, new PlayerLink { PlayerRef = player });
        frame.Add(spectator, new SpectatorMode { TargetKart = GetLeadingKart() });
        
        // Notify UI
        frame.Events.SpectatorJoined(player);
    }
}
```

This comprehensive player connection system ensures smooth racing experiences in Quantum Karts, handling various connection scenarios while maintaining competitive integrity.
