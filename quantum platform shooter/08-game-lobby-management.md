# Game Lobby Management - Quantum Platform Shooter 2D

> **Implementation Note**: For projects using standard Quantum Menu (Platform Shooter, Twin Stick Shooter), code examples are illustrative patterns that could be implemented. Only projects with custom implementations have verified file paths marked with ✓.

Quantum Platform Shooter 2D implements a streamlined lobby system focused on quick matchmaking for 2D platform combat. The game uses the standard Quantum Menu framework with custom UI elements tailored for the platformer genre.

## Menu System Architecture

### Custom Menu Configuration

The game can use custom menu prefab variants to maintain the platform shooter aesthetic. The following is an example implementation:

```csharp
public class QuantumMenuToggleGameObjectPlugin : QuantumMenuScreenPlugin
{
    public GameObject[] HideObjects;
    public GameObject[] ShowObjects;
    
    public override void Show(QuantumMenuUIScreen screen)
    {
        foreach (var go in HideObjects)
        {
            go.SetActive(false);
        }
        
        foreach (var go in ShowObjects)
        {
            go.SetActive(true);
        }
    }
}
```

## Room Configuration

### Platform Shooter Specific Settings

```csharp
public class PlatformShooterLobbyManager : QuantumMenuConnectionBehaviourSDK
{
    public const int MAX_PLAYERS = 4;
    public const int MIN_PLAYERS = 2;
    
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
    {
        // Configure for platform shooter gameplay
        args.RoomOptions = new RoomOptions
        {
            MaxPlayers = MAX_PLAYERS,
            IsOpen = true,
            IsVisible = true,
            
            // Custom properties for game modes
            CustomRoomProperties = new Hashtable
            {
                ["GameMode"] = GetSelectedGameMode(), // Deathmatch, TeamBattle, CaptureTheFlag
                ["MapIndex"] = GetSelectedMapIndex(),
                ["TimeLimit"] = GetTimeLimit(),
                ["ScoreLimit"] = GetScoreLimit(),
                ["PowerUpsEnabled"] = ArePowerUpsEnabled()
            },
            
            CustomRoomPropertiesForLobby = new[] { "GameMode", "MapIndex" }
        };
    }
}
```

## Game Mode Selection

### Pre-Game Configuration

```csharp
public enum PlatformShooterGameMode
{
    Deathmatch,
    TeamBattle,
    CaptureTheFlag,
    KingOfTheHill
}

public class GameModeSelector : MonoBehaviour
{
    [SerializeField] private GameModeConfig[] gameModes;
    private PlatformShooterGameMode selectedMode = PlatformShooterGameMode.Deathmatch;
    
    public void SelectGameMode(int modeIndex)
    {
        selectedMode = (PlatformShooterGameMode)modeIndex;
        UpdateRoomProperties();
        UpdateUI();
    }
    
    private void UpdateRoomProperties()
    {
        if (QuantumRunner.Default?.NetworkClient?.LocalPlayer.IsMasterClient == true)
        {
            var props = new Hashtable
            {
                ["GameMode"] = selectedMode.ToString(),
                ["ModeConfig"] = SerializeGameModeConfig(gameModes[(int)selectedMode])
            };
            
            QuantumRunner.Default.NetworkClient.CurrentRoom.SetCustomProperties(props);
        }
    }
}
```

## Character Selection

### Pre-Match Character Setup

```csharp
public class CharacterSelectionManager : MonoBehaviour
{
    [SerializeField] private CharacterData[] availableCharacters;
    private int selectedCharacterIndex = 0;
    
    public void SelectCharacter(int index)
    {
        selectedCharacterIndex = Mathf.Clamp(index, 0, availableCharacters.Length - 1);
        
        // Update runtime player
        UpdateRuntimePlayer();
        
        // Notify other players
        BroadcastCharacterSelection();
    }
    
    private void UpdateRuntimePlayer()
    {
        var runtimePlayer = new RuntimePlayer
        {
            PlayerNickname = GetPlayerName(),
            PlayerAvatar = availableCharacters[selectedCharacterIndex].CharacterPrefab,
            CustomData = SerializeCharacterLoadout()
        };
        
        // Store for game start
        PlayerPrefs.SetString("SelectedCharacter", JsonUtility.ToJson(runtimePlayer));
    }
    
    private void BroadcastCharacterSelection()
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            client.LocalPlayer.SetCustomProperties(new Hashtable
            {
                ["CharacterIndex"] = selectedCharacterIndex,
                ["CharacterName"] = availableCharacters[selectedCharacterIndex].Name
            });
        }
    }
}
```

## Quick Match System

### Rapid Matchmaking

```csharp
public class QuickMatchManager : MonoBehaviour
{
    private QuantumMenuConnectionBehaviourSDK connection;
    
    public async void QuickMatch()
    {
        var connectArgs = new QuantumMenuConnectArgs
        {
            Session = null, // Random room
            MaxPlayerCount = MAX_PLAYERS,
            RuntimeConfig = CreateDefaultConfig(),
            
            // Quick match preferences
            SqlLobbyFilter = BuildQuickMatchFilter()
        };
        
        var result = await connection.ConnectAsync(connectArgs);
        
        if (result.Success)
        {
            // Auto-select character if not selected
            if (!HasSelectedCharacter())
            {
                AutoSelectCharacter();
            }
        }
    }
    
    private string BuildQuickMatchFilter()
    {
        var filters = new List<string>();
        
        // Filter by preferred game modes
        var preferredModes = GetPreferredGameModes();
        if (preferredModes.Any())
        {
            var modeFilter = string.Join(" OR ", 
                preferredModes.Select(m => $"GameMode = '{m}'"));
            filters.Add($"({modeFilter})");
        }
        
        // Filter by skill level (if implemented)
        if (IsSkillBasedMatchmakingEnabled())
        {
            var skillRange = GetSkillRange();
            filters.Add($"SkillLevel >= {skillRange.Min} AND SkillLevel <= {skillRange.Max}");
        }
        
        return string.Join(" AND ", filters);
    }
}
```

## Map Voting System

### Democratic Map Selection

```csharp
public class MapVotingManager : MonoBehaviour, IInRoomCallbacks
{
    [SerializeField] private MapInfo[] availableMaps;
    private Dictionary<int, List<Player>> mapVotes = new();
    
    public void VoteForMap(int mapIndex)
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            client.LocalPlayer.SetCustomProperties(new Hashtable
            {
                ["VotedMap"] = mapIndex
            });
        }
    }
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.TryGetValue("VotedMap", out var mapIndex))
        {
            UpdateVoteCount(targetPlayer, (int)mapIndex);
            
            if (AllPlayersVoted() || VotingTimeExpired())
            {
                DetermineWinningMap();
            }
        }
    }
    
    private void DetermineWinningMap()
    {
        int winningMapIndex = mapVotes
            .OrderByDescending(kvp => kvp.Value.Count)
            .ThenBy(kvp => kvp.Key) // Tie breaker
            .First().Key;
            
        if (QuantumRunner.Default?.NetworkClient?.LocalPlayer.IsMasterClient == true)
        {
            // Update room with selected map
            var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
            room.SetCustomProperties(new Hashtable
            {
                ["SelectedMap"] = winningMapIndex,
                ["MapName"] = availableMaps[winningMapIndex].Name
            });
            
            // Update runtime config
            UpdateRuntimeConfigMap(winningMapIndex);
        }
    }
}
```

## Ready System

### Player Ready State

```csharp
public class LobbyReadySystem : MonoBehaviour
{
    private Dictionary<Player, bool> playerReadyStates = new();
    
    public void ToggleReady()
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            bool currentState = IsLocalPlayerReady();
            client.LocalPlayer.SetCustomProperties(new Hashtable
            {
                ["IsReady"] = !currentState
            });
        }
    }
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.TryGetValue("IsReady", out var isReady))
        {
            playerReadyStates[targetPlayer] = (bool)isReady;
            UpdateReadyUI(targetPlayer, (bool)isReady);
            
            if (CheckAllPlayersReady() && IsMinimumPlayersMet())
            {
                if (QuantumRunner.Default?.NetworkClient?.LocalPlayer.IsMasterClient == true)
                {
                    StartCountdown();
                }
            }
        }
    }
    
    private void StartCountdown()
    {
        var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
        room.SetCustomProperties(new Hashtable
        {
            ["CountdownStartTime"] = PhotonNetwork.ServerTimestamp,
            ["GameStarting"] = true
        });
        
        // Lock room
        room.IsOpen = false;
    }
}
```

## Lobby UI Integration

### Platform Shooter UI Elements

```csharp
public class PlatformShooterLobbyUI : MonoBehaviour
{
    [SerializeField] private PlayerSlotUI[] playerSlots;
    [SerializeField] private CharacterPreview characterPreview;
    [SerializeField] private MapPreview mapPreview;
    [SerializeField] private GameModeInfo gameModeInfo;
    
    void Update()
    {
        if (QuantumRunner.Default?.NetworkClient?.CurrentRoom == null) return;
        
        UpdatePlayerList();
        UpdateGameSettings();
        UpdateCountdown();
    }
    
    void UpdatePlayerList()
    {
        var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
        
        for (int i = 0; i < playerSlots.Length; i++)
        {
            if (i < room.PlayerCount)
            {
                var player = room.Players.Values.ElementAt(i);
                var slot = playerSlots[i];
                
                slot.SetActive(true);
                slot.SetPlayerName(player.NickName);
                
                // Show character selection
                if (player.CustomProperties.TryGetValue("CharacterIndex", out var charIndex))
                {
                    slot.SetCharacterIcon(GetCharacterIcon((int)charIndex));
                }
                
                // Show ready state
                if (player.CustomProperties.TryGetValue("IsReady", out var isReady))
                {
                    slot.SetReadyState((bool)isReady);
                }
                
                // Show team (for team modes)
                if (IsTeamMode() && player.CustomProperties.TryGetValue("Team", out var team))
                {
                    slot.SetTeamColor((int)team);
                }
            }
            else
            {
                playerSlots[i].SetActive(false);
            }
        }
    }
}
```

## Match Start Synchronization

### Synchronized Game Start

```csharp
public class MatchStartManager : SystemMainThread
{
    private const float COUNTDOWN_DURATION = 5f;
    
    public override void OnEnabled(Frame f)
    {
        if (f.Global->GameState == GameState.WaitingToStart)
        {
            // Initialize countdown
            f.Global->CountdownTimer = FP.FromFloat_UNSAFE(COUNTDOWN_DURATION);
            
            // Spawn players at start positions
            SpawnAllPlayers(f);
        }
    }
    
    public override void Update(Frame f)
    {
        if (f.Global->GameState != GameState.WaitingToStart) return;
        
        f.Global->CountdownTimer -= f.DeltaTime;
        
        if (f.Global->CountdownTimer <= 0)
        {
            // Start match
            f.Global->GameState = GameState.Playing;
            f.Events.MatchStarted();
            
            // Enable player controls
            EnableAllPlayerControls(f);
        }
        else
        {
            // Broadcast countdown
            int seconds = f.Global->CountdownTimer.AsInt;
            if (seconds != f.Global->LastCountdownSecond)
            {
                f.Global->LastCountdownSecond = seconds;
                f.Events.CountdownUpdate(seconds);
            }
        }
    }
}
```

## Private Room Support

### Party Code System

```csharp
public class PrivateRoomManager : MonoBehaviour
{
    public void CreatePrivateRoom()
    {
        string roomCode = GenerateRoomCode();
        
        var connectArgs = new QuantumMenuConnectArgs
        {
            Session = roomCode,
            Creating = true,
            MaxPlayerCount = MAX_PLAYERS,
            
            // Private room settings
            RoomOptions = new RoomOptions
            {
                IsVisible = false,
                MaxPlayers = MAX_PLAYERS,
                CustomRoomProperties = new Hashtable
                {
                    ["IsPrivate"] = true,
                    ["HostSettings"] = GetHostSettings()
                }
            }
        };
        
        StartCoroutine(CreateRoomCoroutine(connectArgs));
    }
    
    public void JoinPrivateRoom(string roomCode)
    {
        var connectArgs = new QuantumMenuConnectArgs
        {
            Session = roomCode,
            Creating = false,
            MaxPlayerCount = MAX_PLAYERS
        };
        
        StartCoroutine(JoinRoomCoroutine(connectArgs));
    }
    
    private string GenerateRoomCode()
    {
        // Generate 6-character code
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        return new string(Enumerable.Repeat(chars, 6)
            .Select(s => s[UnityEngine.Random.Range(0, s.Length)]).ToArray());
    }
}
```

## Best Practices

1. **Keep lobby simple** for quick match starts
2. **Support multiple game modes** with appropriate filtering
3. **Implement character preview** in lobby
4. **Show map voting results** in real-time
5. **Use ready system** for coordinated starts
6. **Lock rooms during countdown** to prevent late joins
7. **Support private matches** with easy-to-share codes
8. **Test with various player counts** and configurations

## Common Patterns

### Auto-Balance Teams

```csharp
public void AutoBalanceTeams()
{
    var room = QuantumRunner.Default?.NetworkClient?.CurrentRoom;
    if (room == null || !room.LocalPlayer.IsMasterClient) return;
    
    var players = room.Players.Values.ToList();
    var teamAssignments = new Dictionary<Player, int>();
    
    // Sort by skill or join order
    players.Sort((a, b) => GetPlayerSkill(b).CompareTo(GetPlayerSkill(a)));
    
    // Assign alternating teams
    for (int i = 0; i < players.Count; i++)
    {
        teamAssignments[players[i]] = i % 2;
    }
    
    // Update room properties
    var props = new Hashtable();
    foreach (var kvp in teamAssignments)
    {
        props[$"Team_{kvp.Key.ActorNumber}"] = kvp.Value;
    }
    
    room.SetCustomProperties(props);
}
```

This lobby system provides a smooth experience for platform shooter gameplay with quick matchmaking and flexible game configuration options.
