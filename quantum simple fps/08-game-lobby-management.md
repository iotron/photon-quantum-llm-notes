# Game Lobby Management - Quantum Simple FPS

Quantum Simple FPS implements a streamlined lobby system optimized for fast-paced first-person shooter gameplay. The game focuses on quick matchmaking and minimal downtime between matches.

## Lobby Architecture

### FPS-Specific Menu System

**File: `/Assets/Scripts/UI/MenuUI.cs`**

```csharp
namespace SimpleFPS
{
    public class MenuUI : QuantumMenuConnectionBehaviourSDK
    {
        [SerializeField]
        private GameObject[] _menuObjects;
        
        private bool _isBusy;
        private bool _isConnected;
        
        public override async Task<ConnectResult> ConnectAsync(QuantumMenuConnectArgs connectionArgs)
        {
            _isBusy = true;
            
            ConnectResult result = await base.ConnectAsync(connectionArgs);
            
            _isBusy = false;
            
            return result;
        }
        
        private void Update()
        {
            if (_isBusy == true)
                return;
            if (_isConnected == IsConnected)
                return;
                
            _isConnected = IsConnected;
            
            if (_isConnected == false)
            {
                // Show cursor for menu navigation
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
            }
            
            foreach (GameObject go in _menuObjects)
            {
                go.SetActive(_isConnected == false);
            }
        }
    }
}
```

## Room Configuration

### FPS Game Settings

```csharp
public class FPSLobbyManager : QuantumMenuConnectionBehaviourSDK
{
    public const int MAX_PLAYERS = 16;
    public const int MIN_PLAYERS_TO_START = 2;
    
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
    {
        // Configure FPS-specific room settings
        args.RoomOptions = new RoomOptions
        {
            MaxPlayers = MAX_PLAYERS,
            IsOpen = true,
            IsVisible = true,
            
            // FPS game modes and settings
            CustomRoomProperties = new Hashtable
            {
                ["GameMode"] = GetSelectedGameMode(), // Deathmatch, TeamDeathmatch, CaptureTheFlag, Domination
                ["MapName"] = GetSelectedMap(),
                ["TimeLimit"] = GetTimeLimit(),
                ["ScoreLimit"] = GetScoreLimit(),
                ["FriendlyFire"] = IsFriendlyFireEnabled(),
                ["RespawnTime"] = GetRespawnTime(),
                ["WeaponSet"] = GetWeaponSet() // Standard, Snipers, Pistols
            },
            
            CustomRoomPropertiesForLobby = new[] { "GameMode", "MapName", "WeaponSet" }
        };
        
        // Don't allow late joining in competitive modes
        if (IsCompetitiveMode())
        {
            args.RoomOptions.CloseOnStart = true;
        }
    }
}
```

## Game Mode Selection

### FPS Game Modes

```csharp
public enum FPSGameMode
{
    Deathmatch,
    TeamDeathmatch,
    CaptureTheFlag,
    Domination,
    SearchAndDestroy,
    GunGame,
    FreeForAll
}

public class GameModeManager : MonoBehaviour
{
    [SerializeField] private GameModeConfig[] gameModes;
    private FPSGameMode selectedMode = FPSGameMode.TeamDeathmatch;
    
    public void SelectGameMode(int modeIndex)
    {
        selectedMode = (FPSGameMode)modeIndex;
        UpdateGameModeSettings();
        
        // Update room properties if host
        if (IsRoomHost())
        {
            UpdateRoomGameMode();
        }
    }
    
    private void UpdateGameModeSettings()
    {
        var config = gameModes[(int)selectedMode];
        
        // Configure mode-specific settings
        SetMaxPlayers(config.MaxPlayers);
        SetRespawnEnabled(config.AllowRespawn);
        SetTeamMode(config.IsTeamBased);
        SetObjectiveMode(config.HasObjectives);
        
        // Update UI
        UpdateGameModeUI(config);
    }
}
```

## Loadout Selection

### Pre-Match Loadout System

```csharp
public class LoadoutManager : MonoBehaviour
{
    [System.Serializable]
    public class Loadout
    {
        public WeaponType PrimaryWeapon;
        public WeaponType SecondaryWeapon;
        public GrenadeType Grenade;
        public PerkType[] Perks;
    }
    
    private Loadout currentLoadout;
    
    public void SelectPrimaryWeapon(int weaponIndex)
    {
        currentLoadout.PrimaryWeapon = (WeaponType)weaponIndex;
        UpdateLoadoutDisplay();
        SaveLoadoutToPlayer();
    }
    
    private void SaveLoadoutToPlayer()
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            var loadoutData = SerializeLoadout(currentLoadout);
            
            client.LocalPlayer.SetCustomProperties(new Hashtable
            {
                ["Loadout"] = loadoutData,
                ["LoadoutHash"] = loadoutData.GetHashCode()
            });
        }
    }
}
```

## Map Voting

### Democratic Map Selection

```csharp
public class MapVotingSystem : MonoBehaviour, IInRoomCallbacks
{
    [SerializeField] private MapData[] availableMaps;
    private Dictionary<string, int> mapVotes = new();
    private float voteEndTime;
    
    public void StartMapVoting()
    {
        voteEndTime = Time.time + 30f; // 30 second voting period
        
        // Initialize vote counts
        foreach (var map in availableMaps)
        {
            mapVotes[map.Name] = 0;
        }
        
        ShowMapVotingUI();
    }
    
    public void VoteForMap(string mapName)
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            client.LocalPlayer.SetCustomProperties(new Hashtable
            {
                ["VotedMap"] = mapName,
                ["VoteTime"] = PhotonNetwork.ServerTimestamp
            });
        }
    }
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.TryGetValue("VotedMap", out var mapName))
        {
            UpdateVoteCount((string)mapName);
            
            if (Time.time >= voteEndTime || AllPlayersVoted())
            {
                DetermineWinningMap();
            }
        }
    }
    
    private void DetermineWinningMap()
    {
        var winningMap = mapVotes.OrderByDescending(kvp => kvp.Value)
                                 .ThenBy(kvp => Random.value) // Random tiebreaker
                                 .First().Key;
                                 
        if (IsRoomHost())
        {
            SetSelectedMap(winningMap);
        }
    }
}
```

## Team Balancing

### Automatic Team Assignment

```csharp
public class TeamBalancer : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        if (!IsTeamGameMode(f)) return;
        
        // Count players in each team
        int team1Count = 0;
        int team2Count = 0;
        
        var filter = f.Filter<PlayerLink, Team>();
        while (filter.NextUnsafe(out var entity, out var link, out var team))
        {
            if (team->TeamIndex == 0) team1Count++;
            else if (team->TeamIndex == 1) team2Count++;
        }
        
        // Assign to smaller team
        int assignedTeam = team1Count <= team2Count ? 0 : 1;
        
        // Check for friends/party members
        if (HasPartyMembers(f, player))
        {
            assignedTeam = GetPartyTeam(f, player);
        }
        
        // Create player with team assignment
        CreatePlayerWithTeam(f, player, assignedTeam);
    }
}
```

## Warm-up Phase

### Pre-Match Warm-up

```csharp
public class WarmupSystem : SystemMainThread
{
    private const FP WARMUP_DURATION = FP._30; // 30 seconds
    
    public override void OnEnabled(Frame f)
    {
        if (f.Global->GameState == GameState.Warmup)
        {
            f.Global->WarmupTimer = WARMUP_DURATION;
            
            // Enable unlimited respawns
            f.Global->UnlimitedRespawns = true;
            
            // Disable scoring
            f.Global->ScoringEnabled = false;
        }
    }
    
    public override void Update(Frame f)
    {
        if (f.Global->GameState != GameState.Warmup) return;
        
        f.Global->WarmupTimer -= f.DeltaTime;
        
        // Check if enough players to start
        int connectedPlayers = CountConnectedPlayers(f);
        bool canStart = connectedPlayers >= MIN_PLAYERS_TO_START;
        
        if (f.Global->WarmupTimer <= 0 && canStart)
        {
            // Transition to match
            StartMatch(f);
        }
        else if (!canStart)
        {
            // Reset timer if not enough players
            f.Global->WarmupTimer = WARMUP_DURATION;
            f.Events.WaitingForPlayers(MIN_PLAYERS_TO_START - connectedPlayers);
        }
    }
    
    private void StartMatch(Frame f)
    {
        f.Global->GameState = GameState.Playing;
        f.Global->UnlimitedRespawns = false;
        f.Global->ScoringEnabled = true;
        
        // Reset all player scores
        ResetAllScores(f);
        
        // Respawn all players
        RespawnAllPlayers(f);
        
        f.Events.MatchStarted();
    }
}
```

## Quick Play System

### Fast Matchmaking

```csharp
public class QuickPlayManager : MonoBehaviour
{
    private QuantumMenuConnectionBehaviourSDK connection;
    
    public async void QuickPlay()
    {
        // Find best available match
        var connectArgs = new QuantumMenuConnectArgs
        {
            Session = null, // Random room
            MaxPlayerCount = MAX_PLAYERS,
            RuntimeConfig = CreateQuickPlayConfig(),
            
            // Prefer nearly full rooms for better experience
            SqlLobbyFilter = BuildQuickPlayFilter()
        };
        
        ShowSearchingUI();
        
        var result = await connection.ConnectAsync(connectArgs);
        
        if (result.Success)
        {
            // Auto-select default loadout
            ApplyDefaultLoadout();
            
            // Ready up automatically
            SetPlayerReady();
        }
        else
        {
            ShowQuickPlayError(result);
        }
    }
    
    private string BuildQuickPlayFilter()
    {
        var filters = new List<string>();
        
        // Prefer standard game modes
        filters.Add("(GameMode = 'TeamDeathmatch' OR GameMode = 'Domination')");
        
        // Prefer rooms with players
        filters.Add("PlayerCount >= 4");
        
        // Region-based matchmaking
        var preferredRegion = GetPreferredRegion();
        if (!string.IsNullOrEmpty(preferredRegion))
        {
            filters.Add($"Region = '{preferredRegion}'");
        }
        
        return string.Join(" AND ", filters);
    }
}
```

## Competitive Mode

### Ranked Match Lobby

```csharp
public class CompetitiveLobby : QuantumMenuConnectionBehaviourSDK
{
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
    {
        // Strict competitive settings
        args.RoomOptions = new RoomOptions
        {
            MaxPlayers = 10, // 5v5
            IsOpen = true,
            IsVisible = false, // Not in casual browser
            CloseOnStart = true, // No late joining
            PlayerTtl = 60000, // 60 second reconnect window
            
            CustomRoomProperties = new Hashtable
            {
                ["Mode"] = "Competitive",
                ["SkillTier"] = GetPlayerSkillTier(),
                ["RequireFullTeams"] = true,
                ["PenaltyForLeaving"] = true
            }
        };
        
        // Skill-based matchmaking
        args.SqlLobbyFilter = $"SkillTier >= {GetMinSkillTier()} AND " +
                             $"SkillTier <= {GetMaxSkillTier()}";
    }
    
    protected override void OnStarted(QuantumRunner runner)
    {
        // Lock loadouts once match starts
        LockAllLoadouts();
        
        // Start with knife round
        if (IsKnifeRoundEnabled())
        {
            StartKnifeRound();
        }
    }
}
```

## Lobby UI

### FPS-Specific UI Elements

```csharp
public class FPSLobbyUI : MonoBehaviour
{
    [SerializeField] private Transform playerListContainer;
    [SerializeField] private LoadoutDisplay loadoutDisplay;
    [SerializeField] private MapVoteDisplay mapVoteDisplay;
    [SerializeField] private GameModeInfo gameModeInfo;
    [SerializeField] private Text matchCountdown;
    
    void Update()
    {
        var room = QuantumRunner.Default?.NetworkClient?.CurrentRoom;
        if (room == null) return;
        
        UpdatePlayerList(room);
        UpdateMatchCountdown();
        UpdateTeamBalance();
    }
    
    void UpdatePlayerList(Room room)
    {
        foreach (var player in room.Players.Values)
        {
            var playerUI = GetOrCreatePlayerUI(player);
            
            // Update player info
            playerUI.SetName(player.NickName);
            playerUI.SetLevel(GetPlayerLevel(player));
            
            // Show loadout
            if (player.CustomProperties.TryGetValue("Loadout", out var loadout))
            {
                playerUI.SetLoadoutIcon(GetLoadoutIcon(loadout));
            }
            
            // Show ready status
            if (player.CustomProperties.TryGetValue("Ready", out var ready))
            {
                playerUI.SetReady((bool)ready);
            }
            
            // Show team
            if (IsTeamMode() && player.CustomProperties.TryGetValue("Team", out var team))
            {
                playerUI.SetTeam((int)team);
            }
        }
    }
}
```

## Best Practices

1. **Implement warm-up phase** for late joiners
2. **Balance teams automatically** for fair matches
3. **Allow loadout customization** in lobby
4. **Support map voting** for player engagement
5. **Lock competitive matches** once started
6. **Show ping/region** for connection quality
7. **Quick play for casual players**
8. **Separate ranked queue** for competitive play

## Common Patterns

### Server Browser

```csharp
public class ServerBrowser : MonoBehaviour
{
    public async Task<List<RoomInfo>> GetAvailableServers(ServerFilter filter)
    {
        var rooms = await FetchRoomList();
        
        return rooms.Where(r => 
            MatchesGameMode(r, filter.GameMode) &&
            MatchesMap(r, filter.Map) &&
            HasSpace(r, filter.NotFull) &&
            InPingRange(r, filter.MaxPing))
            .OrderBy(r => r.PlayerCount)
            .ToList();
    }
}
```

### Party System

```csharp
public class PartyManager : MonoBehaviour
{
    private List<string> partyMembers = new();
    
    public async Task CreatePartyRoom()
    {
        var connectArgs = new QuantumMenuConnectArgs
        {
            Session = GeneratePartyCode(),
            Creating = true,
            MaxPlayerCount = partyMembers.Count,
            
            // Private party room
            RoomOptions = new RoomOptions
            {
                IsVisible = false,
                MaxPlayers = MAX_PLAYERS,
                CustomRoomProperties = new Hashtable
                {
                    ["IsParty"] = true,
                    ["PartyLeader"] = GetLocalUserId()
                }
            }
        };
        
        await connection.ConnectAsync(connectArgs);
    }
}
```

This comprehensive lobby system provides smooth matchmaking and game setup for competitive FPS gameplay.
