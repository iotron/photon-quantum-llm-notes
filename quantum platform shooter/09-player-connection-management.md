# Player Connection Management - Quantum Platform Shooter 2D

Quantum Platform Shooter 2D implements player connection management optimized for fast-paced 2D combat. The system handles player spawning, disconnection recovery, and maintains game flow in competitive platform shooter matches.

## Player Initialization

### Character Spawning System

```csharp
public unsafe class PlayerSpawnSystem : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        var playerData = f.GetPlayerData(player);
        if (playerData == null) return;
        
        // Get spawn point based on game mode
        var spawnPoint = GetSpawnPoint(f, player);
        
        // Create player character
        var characterPrototype = f.FindAsset<EntityPrototype>(playerData.PlayerAvatar);
        var character = f.Create(characterPrototype);
        
        // Set up player components
        if (f.Unsafe.TryGetPointer<PlayerLink>(character, out var playerLink))
        {
            playerLink->PlayerRef = player;
            playerLink->Team = AssignTeam(f, player);
        }
        
        // Set spawn position
        if (f.Unsafe.TryGetPointer<Transform2D>(character, out var transform))
        {
            transform->Position = spawnPoint.Position;
        }
        
        // Initialize character stats
        if (f.Unsafe.TryGetPointer<CharacterStats>(character, out var stats))
        {
            InitializeCharacterStats(stats, playerData);
        }
        
        // Add to player registry
        f.Global->PlayerEntities[player] = character;
        
        f.Events.PlayerSpawned(player, character);
    }
    
    private FPVector2 GetSpawnPoint(Frame f, PlayerRef player)
    {
        // Get appropriate spawn point based on game mode
        switch (f.Global->GameMode)
        {
            case GameMode.TeamBattle:
                return GetTeamSpawnPoint(f, player);
                
            case GameMode.Deathmatch:
                return GetRandomSpawnPoint(f);
                
            case GameMode.CaptureTheFlag:
                return GetBaseSpawnPoint(f, player);
                
            default:
                return GetDefaultSpawnPoint(f);
        }
    }
}
```

## Connection State Monitoring

### Player Presence Tracking

```csharp
public class PlayerConnectionMonitor : SystemMainThread
{
    private Dictionary<PlayerRef, ConnectionInfo> connectionStates = new();
    
    public struct ConnectionInfo
    {
        public bool IsConnected;
        public FP LastInputTime;
        public int ConsecutiveMissedInputs;
        public EntityRef CharacterEntity;
    }
    
    public override void Update(Frame f)
    {
        for (PlayerRef player = 0; player < f.PlayerCount; player++)
        {
            var inputFlags = f.GetPlayerInputFlags(player);
            bool isPresent = (inputFlags & DeterministicInputFlags.PlayerNotPresent) == 0;
            
            if (!connectionStates.TryGetValue(player, out var info))
            {
                info = new ConnectionInfo();
            }
            
            // Update connection state
            bool wasConnected = info.IsConnected;
            info.IsConnected = isPresent;
            
            if (isPresent)
            {
                // Track input timing
                if ((inputFlags & DeterministicInputFlags.HasInput) != 0)
                {
                    info.LastInputTime = f.Time;
                    info.ConsecutiveMissedInputs = 0;
                }
                else
                {
                    info.ConsecutiveMissedInputs++;
                }
            }
            
            // Handle state changes
            if (wasConnected && !isPresent)
            {
                HandlePlayerDisconnect(f, player, ref info);
            }
            else if (!wasConnected && isPresent)
            {
                HandlePlayerReconnect(f, player, ref info);
            }
            
            connectionStates[player] = info;
        }
    }
}
```

## Disconnection Handling

### Character Preservation

```csharp
public unsafe class DisconnectionHandler : SystemMainThread
{
    private const FP DISCONNECT_GRACE_PERIOD = FP._10; // 10 seconds
    
    public void HandlePlayerDisconnect(Frame f, PlayerRef player, ref ConnectionInfo info)
    {
        // Mark disconnection time
        if (f.Unsafe.TryGetPointer<PlayerLink>(info.CharacterEntity, out var playerLink))
        {
            playerLink->DisconnectTime = f.Time;
            playerLink->IsDisconnected = true;
        }
        
        // Make character invulnerable during grace period
        if (f.Unsafe.TryGetPointer<Health>(info.CharacterEntity, out var health))
        {
            health->IsInvulnerable = true;
        }
        
        // Stop character movement
        if (f.Unsafe.TryGetPointer<CharacterController2D>(info.CharacterEntity, out var controller))
        {
            controller->Velocity = FPVector2.Zero;
            controller->IsInputEnabled = false;
        }
        
        // Add visual indicator
        f.Events.PlayerDisconnected(player);
        
        // Start removal timer
        f.Add(info.CharacterEntity, new RemovalTimer 
        { 
            TimeRemaining = DISCONNECT_GRACE_PERIOD 
        });
    }
    
    public override void Update(Frame f)
    {
        // Check removal timers
        var filter = f.Filter<RemovalTimer, PlayerLink>();
        while (filter.NextUnsafe(out var entity, out var timer, out var link))
        {
            timer->TimeRemaining -= f.DeltaTime;
            
            if (timer->TimeRemaining <= 0)
            {
                // Grace period expired, remove character
                RemoveDisconnectedPlayer(f, entity, link->PlayerRef);
            }
        }
    }
}
```

## Reconnection System

### State Restoration

```csharp
public class ReconnectionHandler : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void HandlePlayerReconnect(Frame f, PlayerRef player, ref ConnectionInfo info)
    {
        // Check if player has existing character
        if (f.Exists(info.CharacterEntity))
        {
            RestorePlayerCharacter(f, player, info.CharacterEntity);
        }
        else
        {
            // Create new character if grace period expired
            SpawnNewCharacter(f, player);
        }
    }
    
    private void RestorePlayerCharacter(Frame f, PlayerRef player, EntityRef character)
    {
        // Remove disconnection components
        f.Remove<RemovalTimer>(character);
        
        // Restore control
        if (f.Unsafe.TryGetPointer<CharacterController2D>(character, out var controller))
        {
            controller->IsInputEnabled = true;
        }
        
        // Remove invulnerability after brief period
        if (f.Unsafe.TryGetPointer<Health>(character, out var health))
        {
            f.Add(character, new TimedInvulnerability 
            { 
                Duration = FP._2 // 2 seconds of protection
            });
        }
        
        // Update player link
        if (f.Unsafe.TryGetPointer<PlayerLink>(character, out var link))
        {
            link->IsDisconnected = false;
            link->DisconnectTime = FP._0;
        }
        
        f.Events.PlayerReconnected(player);
    }
}
```

## Respawn System

### Death and Respawn Handling

```csharp
public unsafe class RespawnSystem : SystemMainThreadFilter<RespawnSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Health* Health;
        public PlayerLink* Link;
        public Transform2D* Transform;
    }
    
    private const FP RESPAWN_DELAY = FP._3; // 3 seconds
    
    public override void Update(Frame f, ref Filter filter)
    {
        // Check for death
        if (filter.Health->Current <= 0 && !filter.Health->IsDead)
        {
            HandlePlayerDeath(f, ref filter);
        }
    }
    
    private void HandlePlayerDeath(Frame f, ref Filter filter)
    {
        filter.Health->IsDead = true;
        
        // Award points to killer
        if (filter.Health->LastDamageSource.IsValid)
        {
            AwardKillPoints(f, filter.Health->LastDamageSource, filter.Link->PlayerRef);
        }
        
        // Create death effect
        f.Events.PlayerDied(filter.Entity, filter.Transform->Position);
        
        // Schedule respawn
        f.Add(filter.Entity, new RespawnTimer 
        { 
            TimeRemaining = RESPAWN_DELAY,
            SpawnPoint = SelectRespawnPoint(f, filter.Link->PlayerRef)
        });
        
        // Make character invisible
        f.Add(filter.Entity, new Hidden());
        
        // Disable collision
        if (f.Has<PhysicsCollider2D>(filter.Entity))
        {
            f.Get<PhysicsCollider2D>(filter.Entity).Enabled = false;
        }
    }
}
```

## Input Management

### Player Input Handling

```csharp
public class PlayerInputHandler : QuantumEntityViewComponent
{
    private Input localInput = new Input();
    private PlayerRef playerRef;
    
    public override void OnActivate(Frame frame)
    {
        var playerLink = GetPredictedQuantumComponent<PlayerLink>();
        if (playerLink == null) return;
        
        playerRef = playerLink.PlayerRef;
        
        // Check if this is local player
        if (QuantumRunner.Default.Game.GetLocalPlayers().Contains(playerRef))
        {
            QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
        }
        else
        {
            enabled = false;
        }
    }
    
    public override void OnUpdateView()
    {
        if (!enabled) return;
        
        // Collect input
        localInput.Movement = UnityEngine.Input.GetAxis("Horizontal");
        localInput.Jump = UnityEngine.Input.GetButtonDown("Jump");
        localInput.Fire = UnityEngine.Input.GetButton("Fire1");
        localInput.SecondaryFire = UnityEngine.Input.GetButton("Fire2");
        
        // Aim direction (mouse for PC, right stick for gamepad)
        Vector2 mousePos = Camera.main.ScreenToWorldPoint(UnityEngine.Input.mousePosition);
        Vector2 playerPos = transform.position;
        localInput.AimDirection = (mousePos - playerPos).normalized.ToFPVector2();
    }
    
    private void PollInput(CallbackPollInput callback)
    {
        if (callback.PlayerRef == playerRef)
        {
            callback.SetInput(localInput, DeterministicInputFlags.Repeatable);
        }
    }
}
```

## Network Quality Monitoring

### Connection Quality Indicators

```csharp
public class NetworkQualityDisplay : MonoBehaviour
{
    [SerializeField] private Image connectionIndicator;
    [SerializeField] private Text pingText;
    [SerializeField] private Color goodConnection = Color.green;
    [SerializeField] private Color fairConnection = Color.yellow;
    [SerializeField] private Color poorConnection = Color.red;
    
    void Update()
    {
        if (QuantumRunner.Default?.Session == null) return;
        
        var stats = QuantumRunner.Default.Session.Stats;
        
        // Update ping display
        pingText.text = $"{stats.Ping}ms";
        
        // Update connection quality indicator
        if (stats.Ping < 50 && stats.PacketLoss < 0.01f)
        {
            connectionIndicator.color = goodConnection;
        }
        else if (stats.Ping < 150 && stats.PacketLoss < 0.05f)
        {
            connectionIndicator.color = fairConnection;
        }
        else
        {
            connectionIndicator.color = poorConnection;
            ShowConnectionWarning();
        }
    }
    
    private void ShowConnectionWarning()
    {
        // Display warning message
        if (Time.time % 2 < 1) // Flash warning
        {
            warningText.enabled = true;
            warningText.text = "Poor Connection";
        }
        else
        {
            warningText.enabled = false;
        }
    }
}
```

## Player Score Persistence

### Score and Stats Tracking

```csharp
public struct PlayerStats
{
    public int Kills;
    public int Deaths;
    public int Score;
    public FP DamageDealt;
    public FP DamageTaken;
    public int FlagsCaptures; // For CTF mode
}

public unsafe class PlayerStatsSystem : SystemMainThread
{
    public override void OnPlayerRemoved(Frame f, PlayerRef player)
    {
        // Save final stats
        if (f.TryResolveGlobal(out var stats))
        {
            var playerStats = stats->PlayerStats[player];
            
            // Store for post-game summary
            f.Events.PlayerFinalStats(player, playerStats);
        }
    }
    
    public void UpdatePlayerScore(Frame f, PlayerRef player, int points)
    {
        if (f.Unsafe.TryGetPointerGlobal<GlobalStats>(out var stats))
        {
            stats->PlayerStats[player].Score += points;
            
            // Check for win condition
            if (stats->PlayerStats[player].Score >= f.Global->ScoreLimit)
            {
                f.Events.PlayerWon(player);
                f.Global->GameState = GameState.GameOver;
            }
        }
    }
}
```

## Late Join Support

### Mid-Match Joining

```csharp
public class LateJoinHandler : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        // Check if match is in progress
        if (f.Global->GameState == GameState.Playing)
        {
            HandleLateJoin(f, player);
        }
    }
    
    private void HandleLateJoin(Frame f, PlayerRef player)
    {
        // Spawn with slight disadvantage
        var spawnPoint = GetSafeSpawnPoint(f);
        var character = SpawnPlayerCharacter(f, player, spawnPoint);
        
        // Give spawn protection
        f.Add(character, new SpawnProtection 
        { 
            Duration = FP._5 // 5 seconds
        });
        
        // Initialize with average score
        InitializeLateJoinScore(f, player);
        
        // Notify other players
        f.Events.PlayerJoinedMidMatch(player);
    }
    
    private void InitializeLateJoinScore(Frame f, PlayerRef player)
    {
        // Start with percentage of average score
        int totalScore = 0;
        int activePlayerCount = 0;
        
        for (int i = 0; i < f.PlayerCount; i++)
        {
            if (f.GetPlayerInputFlags(i).IsPresent())
            {
                totalScore += f.Global->PlayerStats[i].Score;
                activePlayerCount++;
            }
        }
        
        if (activePlayerCount > 0)
        {
            int averageScore = totalScore / activePlayerCount;
            f.Global->PlayerStats[player].Score = averageScore / 2; // 50% of average
        }
    }
}
```

## Best Practices

1. **Implement grace periods** for disconnections
2. **Preserve player state** during brief disconnects
3. **Use spawn protection** for respawns and reconnects
4. **Monitor connection quality** and provide feedback
5. **Handle late joins** appropriately for game balance
6. **Track comprehensive stats** for post-match summary
7. **Test with various network conditions**
8. **Implement proper cleanup** for permanent disconnections

## Common Patterns

### Team Auto-Balance

```csharp
public void CheckTeamBalance(Frame f)
{
    int team1Count = 0, team2Count = 0;
    
    var filter = f.Filter<PlayerLink>();
    while (filter.NextUnsafe(out var entity, out var link))
    {
        if (!link->IsDisconnected)
        {
            if (link->Team == 0) team1Count++;
            else team2Count++;
        }
    }
    
    // Auto-balance if difference is too large
    if (Math.Abs(team1Count - team2Count) > 1)
    {
        BalanceTeams(f, team1Count, team2Count);
    }
}
```

### Connection Recovery

```csharp
public async Task<bool> AttemptConnectionRecovery(int maxRetries = 3)
{
    for (int i = 0; i < maxRetries; i++)
    {
        try
        {
            await Task.Delay(1000 * (i + 1)); // Exponential backoff
            
            if (await TryReconnect())
            {
                ShowNotification("Connection restored!");
                return true;
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"Recovery attempt {i + 1} failed: {e}");
        }
    }
    
    return false;
}
```

This comprehensive player connection management system ensures smooth gameplay in Platform Shooter 2D even with network instabilities and player disconnections.
