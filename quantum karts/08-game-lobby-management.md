# Game Lobby Management - Quantum Karts

Quantum Karts implements a racing game lobby system that handles player matchmaking, kart selection, and race initialization. The lobby manages both human players and AI bots to ensure full races.

## Lobby Architecture Overview

### Standard Menu Integration

Quantum Karts uses the standard Quantum Menu system with custom extensions for kart selection:

**File: `/Assets/Scripts/Menu/KartSelector.cs`**

```csharp
public class KartSelector : MonoBehaviour
{
    [SerializeField] private KartSelectionData[] availableKarts;
    [SerializeField] private RuntimePlayer playerTemplate;
    
    private int selectedKartIndex = 0;
    
    public void SelectKart(int index)
    {
        selectedKartIndex = Mathf.Clamp(index, 0, availableKarts.Length - 1);
        UpdateKartPreview();
        
        // Update runtime player data
        UpdatePlayerKartSelection();
    }
    
    private void UpdatePlayerKartSelection()
    {
        // Store selected kart in runtime player
        playerTemplate.PlayerAvatar = availableKarts[selectedKartIndex].KartPrefab;
        
        // Store kart properties for matchmaking
        StoreKartProperties();
    }
}
```

## Room Configuration

### Race-Specific Room Settings

```csharp
public class KartRaceRoomManager : QuantumMenuConnectionBehaviourSDK
{
    public const int MAX_RACERS = 8;
    public const int MIN_RACERS_TO_START = 2;
    
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
    {
        // Configure room for racing
        args.RoomOptions = new RoomOptions
        {
            MaxPlayers = MAX_RACERS,
            IsOpen = true,
            IsVisible = true,
            
            // Custom properties for race configuration
            CustomRoomProperties = new Hashtable
            {
                ["RaceMode"] = GetSelectedRaceMode(),
                ["TrackId"] = GetSelectedTrack(),
                ["Laps"] = GetLapCount(),
                ["PowerUpsEnabled"] = IsPowerUpsEnabled()
            },
            
            // Properties visible in lobby for filtering
            CustomRoomPropertiesForLobby = new[] { "RaceMode", "TrackId" }
        };
        
        // Don't allow late joining after race starts
        args.RoomOptions.CloseOnStart = true;
    }
}
```

## Pre-Race Lobby System

### Lobby State Management

```csharp
public enum LobbyState
{
    WaitingForPlayers,
    KartSelection,
    TrackVoting,
    Countdown,
    RaceStarting
}

public class RaceLobbyManager : MonoBehaviour
{
    private LobbyState currentState = LobbyState.WaitingForPlayers;
    private float stateTimer = 0f;
    
    void Update()
    {
        if (QuantumRunner.Default?.NetworkClient == null) return;
        
        switch (currentState)
        {
            case LobbyState.WaitingForPlayers:
                UpdateWaitingForPlayers();
                break;
                
            case LobbyState.KartSelection:
                UpdateKartSelection();
                break;
                
            case LobbyState.TrackVoting:
                UpdateTrackVoting();
                break;
                
            case LobbyState.Countdown:
                UpdateCountdown();
                break;
        }
    }
    
    private void UpdateWaitingForPlayers()
    {
        var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
        if (room.PlayerCount >= MIN_RACERS_TO_START)
        {
            TransitionToState(LobbyState.KartSelection);
        }
    }
}
```

### Kart Selection Phase

```csharp
public class KartSelectionManager : MonoBehaviour, IInRoomCallbacks
{
    private Dictionary<Player, int> playerKartSelections = new();
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.TryGetValue("SelectedKart", out var kartIndex))
        {
            playerKartSelections[targetPlayer] = (int)kartIndex;
            UpdateKartSelectionUI(targetPlayer, (int)kartIndex);
            
            // Check if all players have selected
            if (AllPlayersReady())
            {
                StartCountdown();
            }
        }
    }
    
    private bool AllPlayersReady()
    {
        var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
        foreach (var player in room.Players.Values)
        {
            if (!player.CustomProperties.ContainsKey("SelectedKart"))
                return false;
        }
        return true;
    }
}
```

## AI Bot Management

### Filling Empty Slots

```csharp
public class AIBotManager : QuantumCallbacks
{
    [SerializeField] private AIDriverData[] aiDriverProfiles;
    
    public override void OnGameStart(QuantumGame game, bool isResync)
    {
        if (!game.Session.IsMasterClient) return;
        
        // Fill empty slots with AI
        int humanPlayers = CountHumanPlayers(game);
        int botsNeeded = Mathf.Max(0, MIN_RACERS_TO_START - humanPlayers);
        
        for (int i = 0; i < botsNeeded; i++)
        {
            AddAIBot(game, humanPlayers + i);
        }
    }
    
    private void AddAIBot(QuantumGame game, int slot)
    {
        var aiProfile = aiDriverProfiles[Random.Range(0, aiDriverProfiles.Length)];
        
        var botPlayer = new RuntimePlayer
        {
            PlayerNickname = aiProfile.Name,
            PlayerAvatar = aiProfile.KartPrefab,
            IsBot = true,
            CustomData = SerializeAIData(aiProfile)
        };
        
        game.AddPlayer(slot, botPlayer);
    }
}
```

## Track Selection System

### Voting Mechanism

```csharp
public class TrackVotingSystem : MonoBehaviour
{
    private Dictionary<string, List<Player>> trackVotes = new();
    
    public void VoteForTrack(string trackId)
    {
        var client = QuantumRunner.Default.NetworkClient;
        client.LocalPlayer.SetCustomProperties(new Hashtable
        {
            ["VotedTrack"] = trackId
        });
    }
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.TryGetValue("VotedTrack", out var trackId))
        {
            UpdateVoteCount(targetPlayer, (string)trackId);
            
            if (AllPlayersVoted())
            {
                DetermineWinningTrack();
            }
        }
    }
    
    private void DetermineWinningTrack()
    {
        string winningTrack = trackVotes
            .OrderByDescending(kvp => kvp.Value.Count)
            .First().Key;
            
        // Update room properties with selected track
        var room = QuantumRunner.Default.NetworkClient.CurrentRoom;
        room.SetCustomProperties(new Hashtable
        {
            ["SelectedTrack"] = winningTrack
        });
    }
}
```

## Race Start Synchronization

### Countdown System

```csharp
public class RaceCountdownManager : SystemMainThread, IGameState_Lobby
{
    private const float COUNTDOWN_DURATION = 5f;
    
    public override void OnEnabled(Frame f)
    {
        // Initialize countdown timer
        f.Global->LobbyCountdown = FP.FromFloat_UNSAFE(COUNTDOWN_DURATION);
        
        // Lock room to prevent new players
        if (f.IsVerified && f.Game.Session.IsMasterClient)
        {
            LockRoom();
        }
    }
    
    public override void Update(Frame f)
    {
        f.Global->LobbyCountdown -= f.DeltaTime;
        
        if (f.Global->LobbyCountdown <= 0)
        {
            // Transition to race
            GameStateSystem.SetState(f, GameState.Racing);
            f.Events.RaceStarted();
        }
        else
        {
            // Sync countdown across clients
            int secondsRemaining = f.Global->LobbyCountdown.AsInt;
            if (secondsRemaining != f.Global->LastCountdownSecond)
            {
                f.Global->LastCountdownSecond = secondsRemaining;
                f.Events.CountdownTick(secondsRemaining);
            }
        }
    }
    
    private void LockRoom()
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client?.CurrentRoom != null)
        {
            client.CurrentRoom.IsOpen = false;
        }
    }
}
```

## Starting Grid Assignment

### Position Allocation

```csharp
public class StartingGridManager : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        if (f.Global->CurrentState != GameState.Lobby) return;
        
        // Assign grid position based on join order
        int gridPosition = CountConnectedPlayers(f);
        
        // Create kart entity at grid position
        var prototype = f.GetPlayerData(player).PlayerAvatar;
        var gridTransform = GetGridPosition(gridPosition);
        
        var kartEntity = f.Create(prototype);
        f.Add(kartEntity, new PlayerLink { PlayerRef = player });
        f.Add(kartEntity, new GridPosition { Position = gridPosition });
        
        // Set initial transform
        if (f.Unsafe.TryGetPointer<Transform3D>(kartEntity, out var transform))
        {
            transform->Position = gridTransform.Position;
            transform->Rotation = gridTransform.Rotation;
        }
    }
    
    private Transform3D GetGridPosition(int position)
    {
        // Calculate grid position based on track layout
        var trackConfig = GetTrackConfiguration();
        return trackConfig.GridPositions[position];
    }
}
```

## Lobby UI Integration

### Player List Display

```csharp
public class LobbyPlayerListUI : MonoBehaviour
{
    [SerializeField] private PlayerSlotUI[] playerSlots;
    
    void Update()
    {
        var room = QuantumRunner.Default?.NetworkClient?.CurrentRoom;
        if (room == null) return;
        
        // Update player slots
        for (int i = 0; i < playerSlots.Length; i++)
        {
            if (i < room.PlayerCount)
            {
                var player = room.Players.Values.ElementAt(i);
                UpdatePlayerSlot(i, player);
            }
            else
            {
                playerSlots[i].SetEmpty();
            }
        }
    }
    
    private void UpdatePlayerSlot(int index, Player player)
    {
        var slot = playerSlots[index];
        slot.SetPlayerName(player.NickName);
        
        // Show selected kart
        if (player.CustomProperties.TryGetValue("SelectedKart", out var kartIndex))
        {
            slot.SetKartIcon(GetKartIcon((int)kartIndex));
            slot.SetReady(true);
        }
        else
        {
            slot.SetReady(false);
        }
        
        // Show vote
        if (player.CustomProperties.TryGetValue("VotedTrack", out var trackId))
        {
            slot.SetVotedTrack((string)trackId);
        }
    }
}
```

## Best Practices

1. **Implement minimum player requirements** to ensure good race experience
2. **Add AI bots** to fill empty slots for better gameplay
3. **Lock rooms during countdown** to prevent late joins
4. **Sync countdown across all clients** for fair starts
5. **Allow kart and track selection** in lobby phase
6. **Show all players' selections** in real-time
7. **Handle player disconnections** during lobby gracefully
8. **Test with various player counts** including full rooms

## Common Patterns

### Quick Match Implementation

```csharp
public async Task QuickMatch()
{
    var connectArgs = new QuantumMenuConnectArgs
    {
        Session = null, // Random room
        MaxPlayerCount = MAX_RACERS,
        RuntimeConfig = CreateDefaultRaceConfig(),
        
        // Quick match filters
        SqlLobbyFilter = "RaceMode = 'Standard' AND Laps = 3"
    };
    
    var result = await Connection.ConnectAsync(connectArgs);
    
    if (result.Success)
    {
        // Auto-select random kart
        AutoSelectKart();
    }
}
```

### Private Room Creation

```csharp
public async Task CreatePrivateRace(string roomCode)
{
    var connectArgs = new QuantumMenuConnectArgs
    {
        Session = roomCode,
        Creating = true,
        MaxPlayerCount = MAX_RACERS,
        
        // Private room settings
        RoomOptions = new RoomOptions
        {
            IsVisible = false, // Not in public listings
            MaxPlayers = MAX_RACERS,
            CustomRoomProperties = new Hashtable
            {
                ["IsPrivate"] = true,
                ["Password"] = GenerateRoomPassword()
            }
        }
    };
    
    await Connection.ConnectAsync(connectArgs);
}
```

This comprehensive lobby system ensures smooth race setup and fair competition in Quantum Karts.
