# Gameplay System in Quantum Simple FPS

This document explains the implementation of the Gameplay System in the Quantum Simple FPS sample project, covering game state management, player statistics, respawning, and match flow.

## Gameplay Components

The gameplay system is built on a singleton component and supporting types defined in the Quantum DSL:

```qtn
singleton component Gameplay
{
    EGameplayState State;
    FP             GameDuration;
    FP             DoubleDamageDuration;
    FP             PlayerRespawnTime;
    FP             RemainingTime;

    [AllocateOnComponentAdded, FreeOnComponentRemoved, ExcludeFromPrototype]
    list<int> RecentSpawnPoints;

    [AllocateOnComponentAdded, FreeOnComponentRemoved]
    dictionary<PlayerRef, PlayerData> PlayerData;
}

enum EGameplayState
{
    Skirmish,
    Running,
    Finished,
}

struct PlayerData
{
    PlayerRef PlayerRef;
    FP        RespawnTimer;
    int       Kills;
    int       Deaths;
    int       LastKillFrame;
    int       StatisticPosition;
    bool      IsAlive;
    bool      IsConnected;
}

signal PlayerKilled(PlayerRef killerPlayerRef, PlayerRef victimPlayerRef, Byte weaponType, Boolean isCriticalKill);

synced event PlayerKilled
{
    PlayerRef KillerPlayerRef;
    PlayerRef VictimPlayerRef;
    Byte WeaponType;
    Boolean IsCriticalKill;
}

synced event GameplayStateChanged
{
	EGameplayState State;
}
```

Additionally, the `GameplayData` asset stores gameplay configuration:

```csharp
public class GameplayData : AssetObject
{
    public SpawnPointData[] SpawnPoints;
}

[Serializable]
public struct SpawnPointData
{
    public FPVector3    Position;
    public FPQuaternion Rotation;
}
```

## Gameplay Extensions

The Gameplay component has extensions to provide utility methods and properties:

```csharp
namespace Quantum
{
    public unsafe partial struct Gameplay
    {
        public bool IsDoubleDamageActive => State == EGameplayState.Running && RemainingTime < DoubleDamageDuration;

        // Additional methods implemented here
    }
}
```

Key properties:
- `IsDoubleDamageActive`: Indicates the final phase of the match with increased damage

## Gameplay System Implementation

The `GameplaySystem` manages the overall game flow:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class GameplaySystem : SystemMainThread, 
                                         ISignalOnPlayerAdded, 
                                         ISignalOnPlayerRemoved, 
                                         ISignalPlayerKilled
    {
        public override void Update(Frame frame)
        {
            var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();

            // Start gameplay when there are enough players connected
            if (gameplay->State == EGameplayState.Skirmish && frame.ComponentCount<Player>() > 1)
            {
                gameplay->StartGameplay(frame);
            }

            if (gameplay->State == EGameplayState.Running)
            {
                gameplay->RemainingTime -= frame.DeltaTime;

                if (gameplay->RemainingTime <= 0)
                {
                    gameplay->StopGameplay(frame);
                }
            }

            if (gameplay->State != EGameplayState.Finished)
            {
                gameplay->TryRespawnPlayers(frame);
            }
        }

        void ISignalOnPlayerAdded.OnPlayerAdded(Frame frame, PlayerRef playerRef, bool firstTime)
        {
            var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
            gameplay->ConnectPlayer(frame, playerRef);
        }

        void ISignalOnPlayerRemoved.OnPlayerRemoved(Frame frame, PlayerRef playerRef)
        {
            var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
            gameplay->DisconnectPlayer(frame, playerRef);
        }

        void ISignalPlayerKilled.PlayerKilled(Frame frame, PlayerRef killerPlayerRef, PlayerRef victimPlayerRef, byte weaponType, QBoolean isCriticalKill)
        {
            var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
            var players = frame.ResolveDictionary(gameplay->PlayerData);

            // Update statistics of the killer player
            if (players.TryGetValue(killerPlayerRef, out PlayerData killerData))
            {
                killerData.Kills++;
                killerData.LastKillFrame = frame.Number;
                players[killerPlayerRef] = killerData;
            }

            // Update statistics of the victim player
            if (players.TryGetValue(victimPlayerRef, out PlayerData playerData))
            {
                playerData.Deaths++;
                playerData.IsAlive = false;
                playerData.RespawnTimer = gameplay->PlayerRespawnTime;
                players[victimPlayerRef] = playerData;
            }

            frame.Events.PlayerKilled(killerPlayerRef, victimPlayerRef, weaponType, isCriticalKill);

            gameplay->RecalculateStatisticPositions(frame);
        }
    }
}
```

Key responsibilities of the GameplaySystem:
1. Managing game state transitions (Skirmish → Running → Finished)
2. Tracking match duration and triggering final phase
3. Handling player connections and disconnections
4. Processing player kills and updating statistics
5. Coordinating player respawning

## Gameplay Component Methods

The Gameplay component has several methods for game flow management:

```csharp
public void ConnectPlayer(Frame frame, PlayerRef playerRef)
{
    var players = frame.ResolveDictionary(PlayerData);

    if (players.TryGetValue(playerRef, out var playerData) == false)
    {
        playerData = new PlayerData();
        playerData.PlayerRef = playerRef;
        playerData.StatisticPosition = int.MaxValue;
        playerData.IsAlive = false;
        playerData.IsConnected = false;
    }

    if (playerData.IsConnected)
        return;

    Log.Warn($"{playerRef} connected.");

    playerData.IsConnected = true;
    players[playerRef] = playerData;

    RespawnPlayer(frame, playerRef);
    RecalculateStatisticPositions(frame);
}

public void DisconnectPlayer(Frame frame, PlayerRef playerRef)
{
    var players = frame.ResolveDictionary(PlayerData);

    if (players.TryGetValue(playerRef, out var playerData))
    {
        if (playerData.IsConnected)
        {
            Log.Warn($"{playerRef} disconnected.");
        }

        playerData.IsConnected = false;
        playerData.IsAlive = false;
        players[playerRef] = playerData;
    }

    var playerEntity = frame.GetPlayerEntity(playerRef);
    if (playerEntity.IsValid)
    {
        frame.Destroy(playerEntity);
    }

    RecalculateStatisticPositions(frame);
}

public void StartGameplay(Frame frame)
{
    SetState(frame, EGameplayState.Running);
    RemainingTime = GameDuration;

    // Reset player data after skirmish and respawn players
    var players = frame.ResolveDictionary(PlayerData);
    foreach (var playerPair in players)
    {
        var playerData = playerPair.Value;

        playerData.RespawnTimer = 0;
        playerData.Kills = 0;
        playerData.Deaths = 0;
        playerData.StatisticPosition = int.MaxValue;

        players[playerData.PlayerRef] = playerData;

        RespawnPlayer(frame, playerData.PlayerRef);
    }
}

public void StopGameplay(Frame frame)
{
    RecalculateStatisticPositions(frame);
    SetState(frame, EGameplayState.Finished);
}

public void TryRespawnPlayers(Frame frame)
{
    var players = frame.ResolveDictionary(PlayerData);
    foreach (var playerPair in players)
    {
        var playerData = playerPair.Value;
        if (playerData.RespawnTimer <= 0)
            continue;

        playerData.RespawnTimer -= frame.DeltaTime;
        players[playerData.PlayerRef] = playerData;

        if (playerData.RespawnTimer <= 0)
        {
            RespawnPlayer(frame, playerPair.Key);
        }
    }
}

public void RecalculateStatisticPositions(Frame frame)
{
    if (State == EGameplayState.Finished)
        return;

    var tempPlayerData = new List<PlayerData>();

    var players = frame.ResolveDictionary(PlayerData);
    foreach (var pair in players)
    {
        tempPlayerData.Add(pair.Value);
    }

    tempPlayerData.Sort((a, b) =>
    {
        if (a.Kills != b.Kills)
            return b.Kills.CompareTo(a.Kills);

        return a.LastKillFrame.CompareTo(b.LastKillFrame);
    });

    for (int i = 0; i < tempPlayerData.Count; i++)
    {
        var playerData = tempPlayerData[i];
        playerData.StatisticPosition = playerData.Kills > 0 ? i + 1 : int.MaxValue;

        players[playerData.PlayerRef] = playerData;
    }
}

private void SetState(Frame frame, EGameplayState state)
{
    State = state;
    frame.Events.GameplayStateChanged(state);
}

private void RespawnPlayer(Frame frame, PlayerRef playerRef)
{
    var players = frame.ResolveDictionary(PlayerData);

    // Despawn old player object if it exists
    var playerEntity = frame.GetPlayerEntity(playerRef);
    if (playerEntity.IsValid)
    {
        frame.Destroy(playerEntity);
    }

    // Don't spawn the player for disconnected clients
    if (players.TryGetValue(playerRef, out PlayerData playerData) == false || 
        playerData.IsConnected == false)
        return;

    // Update player data
    playerData.IsAlive = true;
    players[playerRef] = playerData;

    var runtimePlayer = frame.GetPlayerData(playerRef);
    playerEntity = frame.Create(runtimePlayer.PlayerAvatar);

    frame.AddOrGet<Player>(playerEntity, out var player);
    player->PlayerRef = playerRef;

    var playerTransform = frame.Unsafe.GetPointer<Transform3D>(playerEntity);

    SpawnPointData spawnPoint = GetSpawnPoint(frame);
    playerTransform->Position = spawnPoint.Position;
    playerTransform->Rotation = spawnPoint.Rotation;

    var playerKCC = frame.Unsafe.GetPointer<KCC>(playerEntity);
    playerKCC->SetLookRotation(spawnPoint.Rotation.AsEuler.XY);
}

private SpawnPointData GetSpawnPoint(Frame frame)
{
    var gameplayData = frame.FindAsset<GameplayData>(frame.Map.UserAsset);

    SpawnPointData spawnPointData = default;
    int spawnPointIndex = 0;

    var recentSpawnPoints = frame.ResolveList(RecentSpawnPoints);
    int randomOffset = frame.RNG->Next(0, gameplayData.SpawnPoints.Length);

    // Iterate over all spawn points in the scene
    for (int i = 0; i < gameplayData.SpawnPoints.Length; i++)
    {
        spawnPointIndex = (randomOffset + i) % gameplayData.SpawnPoints.Length;
        spawnPointData = gameplayData.SpawnPoints[spawnPointIndex];

        if (recentSpawnPoints.Contains(spawnPointIndex) == false)
            break;
    }

    // Add spawn point to list of recently used spawn points
    recentSpawnPoints.Add(spawnPointIndex);

    // Ignore only last 3 spawn points
    if (recentSpawnPoints.Count > 3)
    {
        recentSpawnPoints.RemoveAt(0);
    }

    return spawnPointData;
}
```

Key methods of the Gameplay component:
1. `ConnectPlayer()`: Handles player connection and first spawn
2. `DisconnectPlayer()`: Handles player disconnection and cleanup
3. `StartGameplay()`: Transitions from Skirmish to Running state
4. `StopGameplay()`: Transitions to Finished state at the end of the match
5. `TryRespawnPlayers()`: Processes respawn timers and respawns players
6. `RecalculateStatisticPositions()`: Updates player rankings based on kills
7. `RespawnPlayer()`: Handles the actual player respawn process
8. `GetSpawnPoint()`: Selects a spawn point, avoiding recently used ones

## Game States

The game flows through three distinct states:

1. **Skirmish**
   - Initial state when players connect
   - Players can join, fight, and test weapons
   - No score tracking or game timer
   - Transitions to Running when enough players join

2. **Running**
   - Main gameplay phase with timer counting down
   - Score tracking is active
   - Special events may occur (double damage phase)
   - Transitions to Finished when timer expires

3. **Finished**
   - End-of-match state
   - Final scores and winner displayed
   - No more respawning
   - Transitions to Skirmish for next match

## Spawn Point Management

The spawn system implements intelligent spawn point selection:

1. Spawn points are defined in the `GameplayData` asset
2. A list of recently used spawn points is maintained
3. When selecting a spawn point:
   - Start from a random index to avoid predictable spawns
   - Skip recently used spawn points to prevent spawn camping
   - Keep only the last 3 used points in "recent" list

```csharp
private SpawnPointData GetSpawnPoint(Frame frame)
{
    var gameplayData = frame.FindAsset<GameplayData>(frame.Map.UserAsset);

    SpawnPointData spawnPointData = default;
    int spawnPointIndex = 0;

    var recentSpawnPoints = frame.ResolveList(RecentSpawnPoints);
    int randomOffset = frame.RNG->Next(0, gameplayData.SpawnPoints.Length);

    // Iterate over all spawn points in the scene
    for (int i = 0; i < gameplayData.SpawnPoints.Length; i++)
    {
        spawnPointIndex = (randomOffset + i) % gameplayData.SpawnPoints.Length;
        spawnPointData = gameplayData.SpawnPoints[spawnPointIndex];

        if (recentSpawnPoints.Contains(spawnPointIndex) == false)
            break;
    }

    // Add spawn point to list of recently used spawn points
    recentSpawnPoints.Add(spawnPointIndex);

    // Ignore only last 3 spawn points
    if (recentSpawnPoints.Count > 3)
    {
        recentSpawnPoints.RemoveAt(0);
    }

    return spawnPointData;
}
```

## Player Statistics

Player statistics are tracked and used for rankings:

1. **Kills**: Incremented when a player kills another player
2. **Deaths**: Incremented when a player is killed
3. **LastKillFrame**: Timestamp of the player's most recent kill
4. **StatisticPosition**: Player's position in the rankings (1 = first place)

Rankings are updated whenever a kill occurs:

```csharp
public void RecalculateStatisticPositions(Frame frame)
{
    if (State == EGameplayState.Finished)
        return;

    var tempPlayerData = new List<PlayerData>();

    var players = frame.ResolveDictionary(PlayerData);
    foreach (var pair in players)
    {
        tempPlayerData.Add(pair.Value);
    }

    tempPlayerData.Sort((a, b) =>
    {
        if (a.Kills != b.Kills)
            return b.Kills.CompareTo(a.Kills);

        return a.LastKillFrame.CompareTo(b.LastKillFrame);
    });

    for (int i = 0; i < tempPlayerData.Count; i++)
    {
        var playerData = tempPlayerData[i];
        playerData.StatisticPosition = playerData.Kills > 0 ? i + 1 : int.MaxValue;

        players[playerData.PlayerRef] = playerData;
    }
}
```

This ranking system:
1. Sorts players primarily by kills (highest first)
2. Uses LastKillFrame as a tiebreaker (earlier kills win)
3. Requires at least one kill to be ranked

## Special Game Mechanics

The gameplay system implements special mechanics to enhance the experience:

1. **Double Damage Phase**
   - Activates during final countdown (DoubleDamageDuration)
   - All weapon damage is doubled
   - Encourages aggressive play at the end

```csharp
public bool IsDoubleDamageActive => State == EGameplayState.Running && RemainingTime < DoubleDamageDuration;
```

This is checked in the WeaponsSystem when applying damage:

```csharp
// At the end of gameplay the damage is doubled
if (frame.GetSingleton<Gameplay>().IsDoubleDamageActive)
{
    damage *= 2;
}
```

2. **Spawn Protection**
   - Temporary immortality after spawning
   - Prevents spawn-killing
   - Canceled when player starts shooting

```csharp
// In WeaponsSystem.TryFire method
if (input->Fire.IsDown)
{
    TryFire(frame, ref filter, currentWeapon, input->Fire.WasPressed);

    // Cancel after-spawn immortality when player starts shooting
    filter.Health->StopImmortality();
}
```

## Game State Communication

Game state changes are communicated to the view through events:

```csharp
private void SetState(Frame frame, EGameplayState state)
{
    State = state;
    frame.Events.GameplayStateChanged(state);
}
```

The Unity view layer subscribes to these events:

```csharp
namespace QuantumDemo
{
    public class GameplayUI : QuantumMonoBehaviour
    {
        // UI references
        public GameObject SkirmishUI;
        public GameObject RunningUI;
        public GameObject FinishedUI;
        public Text TimerText;
        public GameObject DoubleDamageWarning;
        
        // Player score display
        public Transform ScoreboardContent;
        public GameObject ScoreEntryPrefab;
        
        private void OnEnable()
        {
            // Subscribe to gameplay events
            QuantumEvent.Subscribe<EventGameplayStateChanged>(this, OnGameplayStateChanged);
        }
        
        private void OnDisable()
        {
            QuantumEvent.Unsubscribe<EventGameplayStateChanged>(this, OnGameplayStateChanged);
        }
        
        private void OnGameplayStateChanged(EventGameplayStateChanged e)
        {
            // Update UI based on new state
            SkirmishUI.SetActive(e.State == EGameplayState.Skirmish);
            RunningUI.SetActive(e.State == EGameplayState.Running);
            FinishedUI.SetActive(e.State == EGameplayState.Finished);
            
            if (e.State == EGameplayState.Finished)
            {
                // Display final scores
                UpdateScoreboard();
            }
        }
        
        private void Update()
        {
            if (!QuantumRunner.Default.Game.TryGetFrameLocal(out var frame))
                return;
                
            if (!frame.TryGet<Gameplay>(out var gameplay))
                return;
                
            if (gameplay.State == EGameplayState.Running)
            {
                // Update timer
                int minutes = (int)(gameplay.RemainingTime / 60);
                int seconds = (int)(gameplay.RemainingTime % 60);
                TimerText.text = $"{minutes:00}:{seconds:00}";
                
                // Show double damage warning
                DoubleDamageWarning.SetActive(gameplay.IsDoubleDamageActive);
            }
            
            // Update scoreboard periodically
            if (Time.frameCount % 30 == 0)
            {
                UpdateScoreboard();
            }
        }
        
        private void UpdateScoreboard()
        {
            if (!QuantumRunner.Default.Game.TryGetFrameLocal(out var frame))
                return;
                
            if (!frame.TryGet<Gameplay>(out var gameplay))
                return;
                
            // Clear existing entries
            foreach (Transform child in ScoreboardContent)
            {
                Destroy(child.gameObject);
            }
            
            // Get player data
            var players = frame.ResolveDictionary(gameplay.PlayerData);
            
            // Create sorted list
            var sortedPlayers = new List<PlayerData>();
            foreach (var pair in players)
            {
                sortedPlayers.Add(pair.Value);
            }
            
            // Sort by position
            sortedPlayers.Sort((a, b) => a.StatisticPosition.CompareTo(b.StatisticPosition));
            
            // Create entries
            foreach (var playerData in sortedPlayers)
            {
                if (playerData.StatisticPosition == int.MaxValue)
                    continue;
                    
                var entry = Instantiate(ScoreEntryPrefab, ScoreboardContent);
                var scoreEntry = entry.GetComponent<ScoreEntry>();
                
                // Get player name from SessionManager
                string playerName = SessionManager.Instance.GetPlayerName(playerData.PlayerRef);
                
                scoreEntry.SetData(
                    playerData.StatisticPosition,
                    playerName,
                    playerData.Kills,
                    playerData.Deaths,
                    frame.PlayerIsLocal(playerData.PlayerRef)
                );
            }
        }
    }
}
```

## Best Practices for FPS Gameplay Implementation

1. **State machine architecture**: Clear separation between game states
2. **Singleton game controller**: Centralized gameplay management
3. **Player data dictionary**: Efficient player data lookup by PlayerRef
4. **Advanced spawn logic**: Smart spawn point selection to avoid camping
5. **Score-based ranking**: Real-time player rankings with tiebreakers
6. **Game phases**: Changing mechanics during match (double damage)
7. **Event-based UI updates**: Communicate state changes to view layer
8. **Spawn protection**: Temporary immortality after respawning
9. **Clean player cleanup**: Proper handling of disconnected players
10. **Dynamic game start**: Auto-start when enough players join

These practices ensure a fair and engaging multiplayer experience with clear rules and state transitions. The gameplay system manages the overall game flow while providing appropriate feedback to players about the current state and remaining time.
