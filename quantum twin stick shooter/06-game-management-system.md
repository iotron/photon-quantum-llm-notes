# Game Management System

This document explains the game management system in the Quantum Twin Stick Shooter, focusing on how game flow, match management, and team mechanics are handled.

## Overview

The game management system in Twin Stick Shooter provides:

1. **Game State Management**: Controls the flow between game states
2. **Match Timing**: Handles countdown, match duration, and overtime
3. **Team Management**: Tracks team scores and determines victory conditions
4. **Game Mode Implementation**: Manages the Coin Grab game mechanics
5. **HFSM-Based Flow**: Uses Hierarchical Finite State Machine for game states

## Core Components

### Global Game State

```csharp
// From Game.qtn
global
{
    FP MatchTimer;
    FP MatchDuration;

    Boolean ControllersEnabled;
    GameState State;

    HFSMData GameManagerHFSM;
}

enum GameState{
    None,
    CharacterSelection,
    Playing,
    Over
}
```

### Team Component

```csharp
// From Team.qtn
component TeamInfo
{
    int Index;
}

struct TeamData
{
    byte Score;
    byte ScoreTimer;
}
```

### Game Manager HFSM

The Game Manager uses a Hierarchical Finite State Machine to control game flow:

```csharp
// GameManagerSystem.cs
[Preserve]
public unsafe class GameManagerSystem : SystemMainThread, 
    ISignalOnCharacterSelectionStart, ISignalOnGameStart, ISignalOnGameOver
{
    public override void OnInit(Frame frame)
    {
        // Initialize game manager HFSM
        HFSMRoot hfsmRoot = frame.FindAsset<HFSMRoot>(frame.RuntimeConfig.GameManagerHFSM.Id);

        HFSMData* hfsmData = &frame.Global->GameManagerHFSM;
        hfsmData->Root = hfsmRoot;
        HFSMManager.Init(frame, hfsmData, default, hfsmRoot);
    }

    public override void Update(Frame frame)
    {
        // Update game manager HFSM
        HFSMManager.Update(frame, frame.DeltaTime, &frame.Global->GameManagerHFSM, default);
    }

    // State change handlers
    public void OnCharacterSelectionStart(Frame frame)
    {
        frame.Global->State = GameState.CharacterSelection;
    }

    public void OnGameStart(Frame frame)
    {
        frame.Global->State = GameState.Playing;
    }

    public void OnGameOver(Frame frame, QBoolean value)
    {
        frame.Global->State = GameState.Over;
    }
}
```

## Game Manager HFSM Definition

The Game Manager HFSM defines the following states and transitions:

```csharp
// Example of game manager HFSM setup (simplified)
public static HFSMRoot CreateGameManagerHFSM()
{
    HFSMRoot root = new HFSMRoot();
    
    // Main states
    var waitingForPlayers = root.AddState("WaitingForPlayers");
    var characterSelection = root.AddState("CharacterSelection");
    var arenaPresentation = root.AddState("ArenaPresentation");
    var countdown = root.AddState("Countdown");
    var playing = root.AddState("Playing");
    var gameOver = root.AddState("GameOver");
    
    // Define transitions
    waitingForPlayers.AddTransition(characterSelection, new HasEnoughPlayers());
    characterSelection.AddTransition(arenaPresentation, new TimerDecision("CharacterSelection", 30));
    arenaPresentation.AddTransition(countdown, new TimerDecision("ArenaPresentation", 5));
    countdown.AddTransition(playing, new TimerDecision("Countdown", 3));
    playing.AddTransition(gameOver, new TimerDecision("Playing", 300));
    playing.AddTransition(gameOver, new TeamHasWon());
    
    // Define state behaviors
    waitingForPlayers.SetEnterAction(new WaitingForPlayersEnter());
    characterSelection.SetEnterAction(new CharacterSelectionEnter());
    arenaPresentation.SetEnterAction(new ArenaPresentationEnter());
    countdown.SetEnterAction(new CountdownEnter());
    playing.SetEnterAction(new PlayingEnter());
    gameOver.SetEnterAction(new GameOverEnter());
    
    return root;
}
```

## Match System

The `MatchSystem` updates match timers and handles match flow:

```csharp
[Preserve]
public unsafe class MatchSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Only update timer during "Playing" state
        if (frame.Global->State != GameState.Playing)
            return;
            
        // Update match timer
        frame.Global->MatchTimer += frame.DeltaTime;
        
        // Check for time-based match end
        if (frame.Global->MatchTimer >= frame.Global->MatchDuration)
        {
            int winningTeam = DetermineWinningTeam(frame);
            frame.Events.GameOver(winningTeam);
            frame.Signals.OnGameOver(frame, true);
        }
    }
    
    private int DetermineWinningTeam(Frame frame)
    {
        // Get team scores
        TeamData* teams = frame.Global->Teams;
        
        // Find team with highest score
        int winningTeam = 0;
        byte highestScore = teams[0].Score;
        
        for (int i = 1; i < teams.Length; i++)
        {
            if (teams[i].Score > highestScore)
            {
                winningTeam = i;
                highestScore = teams[i].Score;
            }
        }
        
        return winningTeam;
    }
}
```

## Team Data System

The `TeamDataSystem` tracks team scores and monitors victory conditions:

```csharp
[Preserve]
public unsafe class TeamDataSystem : SystemMainThread
{
    // Score threshold for victory
    private const byte SCORE_THRESHOLD = 10;
    
    // Time required to hold score threshold (in seconds)
    private const byte HOLD_TIME_REQUIRED = 15;
    
    // Update interval in frames
    private const byte UPDATE_INTERVAL = 30;
    
    private byte _updateCounter = 0;

    public override void Update(Frame frame)
    {
        // Only update in "Playing" state
        if (frame.Global->State != GameState.Playing)
            return;
            
        // Update at specified interval
        _updateCounter++;
        if (_updateCounter < UPDATE_INTERVAL)
            return;
            
        _updateCounter = 0;
        
        // Count coins for each team
        UpdateTeamScores(frame);
        
        // Check victory conditions
        CheckVictoryConditions(frame);
    }
    
    private void UpdateTeamScores(Frame frame)
    {
        // Reset team scores
        for (int i = 0; i < frame.Global->Teams.Length; i++)
        {
            frame.Global->Teams[i].Score = 0;
        }
        
        // Count coins held by each team
        var characters = frame.Filter<Character, TeamInfo, Inventory>();
        while (characters.NextUnsafe(out EntityRef entity, out Character* character,
            out TeamInfo* teamInfo, out Inventory* inventory))
        {
            byte coinCount = CountCoins(frame, inventory);
            frame.Global->Teams[teamInfo->Index].Score += coinCount;
        }
    }
    
    private byte CountCoins(Frame frame, Inventory* inventory)
    {
        byte count = 0;
        
        // Count coin items in inventory
        for (int i = 0; i < inventory->Items.Length; i++)
        {
            var item = inventory->Items[i];
            if (item.Type == EItemType.Coin)
            {
                count++;
            }
        }
        
        return count;
    }
    
    private void CheckVictoryConditions(Frame frame)
    {
        // Check each team for victory condition
        for (int i = 0; i < frame.Global->Teams.Length; i++)
        {
            TeamData* team = &frame.Global->Teams[i];
            
            // Check if team has enough coins
            if (team->Score >= SCORE_THRESHOLD)
            {
                // Increment score timer
                team->ScoreTimer++;
                
                // Check if timer reached threshold
                if (team->ScoreTimer >= HOLD_TIME_REQUIRED)
                {
                    // Team wins
                    frame.Events.GameOver(i);
                    frame.Signals.OnGameOver(frame, true);
                    return;
                }
            }
            else
            {
                // Reset timer if score drops below threshold
                team->ScoreTimer = 0;
            }
        }
    }
}
```

## Character Selection System

The `CharacterSelectionSystem` handles the pre-match character selection phase:

```csharp
[Preserve]
public unsafe class CharacterSelectionSystem : SystemMainThreadFilter<CharacterSelectionSystem.Filter>,
    ISignalOnCharacterSelectionStart
{
    public struct Filter
    {
        public EntityRef Entity;
        public CharacterSelection* CharacterSelection;
        public PlayerLink* PlayerLink;
    }

    public void OnCharacterSelectionStart(Frame frame)
    {
        // Create character selection entities for each player
        for (int i = 0; i < frame.RuntimeConfig.PlayerCount; i++)
        {
            if (frame.PlayerIsBot(i))
                continue;
                
            EntityRef selectionEntity = frame.Create(frame.RuntimeConfig.CharacterSelectionPrototype);
            
            CharacterSelection* selection = frame.Unsafe.GetPointer<CharacterSelection>(selectionEntity);
            selection->PlayerRef = i;
            
            PlayerLink* playerLink = frame.Unsafe.GetPointer<PlayerLink>(selectionEntity);
            playerLink->PlayerRef = i;
        }
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Process player inputs for character selection
        QuantumDemoInputTopDown* input = frame.GetPlayerInput(filter.PlayerLink->PlayerRef);
        
        // Change character selection based on input
        if (input->MoveDirection.X > FP._0_50 && filter.CharacterSelection->SelectedIndex < 2)
        {
            filter.CharacterSelection->SelectedIndex++;
            frame.Events.CharacterChanged(filter.Entity, filter.CharacterSelection->SelectedIndex);
        }
        else if (input->MoveDirection.X < -FP._0_50 && filter.CharacterSelection->SelectedIndex > 0)
        {
            filter.CharacterSelection->SelectedIndex--;
            frame.Events.CharacterChanged(filter.Entity, filter.CharacterSelection->SelectedIndex);
        }
        
        // Confirm selection
        if (input->Fire && filter.CharacterSelection->IsConfirmed == false)
        {
            filter.CharacterSelection->IsConfirmed = true;
            frame.Events.CharacterConfirmed(filter.Entity, filter.CharacterSelection->SelectedIndex);
            
            // Check if all players have selected
            CheckAllPlayersSelected(frame);
        }
    }
    
    private void CheckAllPlayersSelected(Frame frame)
    {
        // Count confirmed selections
        int confirmedCount = 0;
        int totalPlayers = 0;
        
        var selections = frame.Filter<CharacterSelection>();
        while (selections.Next(out EntityRef entity, out CharacterSelection selection))
        {
            totalPlayers++;
            if (selection.IsConfirmed)
            {
                confirmedCount++;
            }
        }
        
        // If all players confirmed, move to next phase
        if (confirmedCount == totalPlayers && totalPlayers > 0)
        {
            frame.Events.CharacterSelectionComplete();
        }
    }
}
```

## Player Joining System

The `PlayerJoiningSystem` handles players joining and manages substitution with bots:

```csharp
[Preserve]
public unsafe class PlayerJoiningSystem : SystemMainThread
{
    public override void OnInit(Frame frame)
    {
        // Initialize game with a minimum number of players/bots
        if (frame.RuntimeConfig.AutoFillWithBots)
        {
            for (int i = 0; i < frame.RuntimeConfig.MinimumPlayerCount; i++)
            {
                int playerRef = i;
                int teamIndex = i % 2; // Alternate teams
                
                // If player is connected, create player character
                if (!frame.PlayerIsBot(playerRef))
                {
                    CreatePlayerCharacter(frame, playerRef, teamIndex);
                }
                // Otherwise create bot
                else
                {
                    CreateBotCharacter(frame, playerRef, teamIndex);
                }
            }
        }
    }

    private void CreatePlayerCharacter(Frame frame, int playerRef, int teamIndex)
    {
        // Create character entity for player
        EntityRef characterEntity = frame.Create(frame.RuntimeConfig.DefaultCharacterPrototype);
        
        // Setup player link
        PlayerLink* playerLink = frame.Unsafe.GetPointer<PlayerLink>(characterEntity);
        playerLink->PlayerRef = playerRef;
        
        // Setup team info
        TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(characterEntity);
        teamInfo->Index = teamIndex;
        
        // Add bot component (inactive by default)
        Bot* bot = frame.Unsafe.GetPointer<Bot>(characterEntity);
        bot->IsActive = false;
        
        // Setup other character components
        InitializeCharacter(frame, characterEntity);
    }
    
    private void CreateBotCharacter(Frame frame, int playerRef, int teamIndex)
    {
        // Create character entity for bot
        EntityRef characterEntity = frame.Create(frame.RuntimeConfig.DefaultCharacterPrototype);
        
        // Setup player link
        PlayerLink* playerLink = frame.Unsafe.GetPointer<PlayerLink>(characterEntity);
        playerLink->PlayerRef = playerRef;
        
        // Setup team info
        TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(characterEntity);
        teamInfo->Index = teamIndex;
        
        // Setup bot
        AISetupHelper.Botify(frame, characterEntity);
        
        // Setup other character components
        InitializeCharacter(frame, characterEntity);
    }
    
    private void InitializeCharacter(Frame frame, EntityRef entity)
    {
        // Initialize character components
        CharacterInfo characterInfo = frame.FindAsset<CharacterInfo>(frame.RuntimeConfig.DefaultCharacterInfo.Id);
        
        // Initialize attributes
        InitializeAttributes(frame, entity, characterInfo);
        
        // Initialize inventory
        Inventory* inventory = frame.Unsafe.GetPointer<Inventory>(entity);
        inventory->Items = new QList<InventoryItem>(frame.AllocatorHandle, 5);
        
        // Initialize health
        Health* health = frame.Unsafe.GetPointer<Health>(entity);
        health->Current = characterInfo.MaxHealth;
        
        // Initialize respawn
        Respawn* respawn = frame.Unsafe.GetPointer<Respawn>(entity);
        respawn->RespawnPosition = GetRespawnPosition(frame, frame.Get<TeamInfo>(entity).Index);
        
        // Set random name for player/bot
        Player* player = frame.Unsafe.GetPointer<Player>(entity);
        player->Name = GetRandomName(frame);
    }
    
    private FPVector2 GetRespawnPosition(Frame frame, int teamIndex)
    {
        // Find suitable respawn position based on team
        // ... (implementation details)
        
        return FPVector2.Zero; // Simplified
    }
    
    private string GetRandomName(Frame frame)
    {
        // Get random name from list
        string[] names = {
            "Striker", "Phantom", "Viper", "Shadow", "Blitz",
            "Thunder", "Havoc", "Nova", "Rogue", "Spectre"
        };
        
        int randomIndex = frame.RandomNext() % names.Length;
        return names[randomIndex];
    }
}
```

## Respawn System

The `RespawnSystem` handles character respawning after death:

```csharp
[Preserve]
public unsafe class RespawnSystem : SystemMainThreadFilter<RespawnSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Respawn* Respawn;
        public Health* Health;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Only process dead characters
        if (!filter.Health->IsDead || !filter.Respawn->IsDead)
            return;
        
        // Update respawn timer
        filter.Respawn->Timer += frame.DeltaTime;
        
        // Check if respawn time elapsed
        if (filter.Respawn->Timer >= filter.Respawn->RespawnDelay)
        {
            // Reset respawn data
            filter.Respawn->Timer = 0;
            filter.Respawn->IsDead = false;
            
            // Reset health
            filter.Health->IsDead = false;
            filter.Health->Current = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Health);
            
            // Set temporary immortality
            frame.Signals.OnSetCharacterImmune(filter.Entity, FP._3);
            
            // Position character at respawn point
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(filter.Entity);
            transform->Position = filter.Respawn->RespawnPosition;
            
            // Clear inventory (drop coins)
            if (frame.Has<Inventory>(filter.Entity))
            {
                Inventory* inventory = frame.Unsafe.GetPointer<Inventory>(filter.Entity);
                DropAllCoins(frame, filter.Entity, inventory, transform->Position);
                inventory->Items.Clear();
            }
            
            // Send respawn event
            frame.Events.CharacterRespawned(filter.Entity);
        }
    }
    
    private void DropAllCoins(Frame frame, EntityRef character, Inventory* inventory, FPVector2 position)
    {
        // Count coins in inventory
        int coinCount = 0;
        for (int i = 0; i < inventory->Items.Length; i++)
        {
            if (inventory->Items[i].Type == EItemType.Coin)
            {
                coinCount++;
            }
        }
        
        // Spawn dropped coins
        for (int i = 0; i < coinCount; i++)
        {
            // Calculate random drop position
            FP angle = FP.FromFloat_UNSAFE(frame.RandomInRange(0, 360));
            FP distance = FP.FromFloat_UNSAFE(frame.RandomInRange(1, 3));
            FPVector2 dropPos = position + FPVector2.FromAngle(angle) * distance;
            
            // Create coin entity
            EntityRef coinEntity = frame.Create(frame.RuntimeConfig.CoinPrototype);
            
            // Set position
            Transform2D* coinTransform = frame.Unsafe.GetPointer<Transform2D>(coinEntity);
            coinTransform->Position = dropPos;
        }
    }
}
```

## Objective Point System (Coins)

The `ObjectivePointSystem` manages collectible coins in the game:

```csharp
[Preserve]
public unsafe class ObjectivePointSystem : SystemMainThreadFilter<ObjectivePointSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public ObjectivePoint* ObjectivePoint;
        public Transform2D* Transform;
        public PhysicsCollider2D* Collider;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Skip if not active
        if (!filter.ObjectivePoint->IsActive)
            return;
            
        // Check for characters in range
        var hits = Physics2D.OverlapShape(frame, filter.Collider->Shape, *filter.Transform);
        foreach (var hit in hits)
        {
            // Only process character entities
            if (!frame.Has<Character>(hit) || !frame.Has<Inventory>(hit))
                continue;
                
            // Skip dead characters
            if (frame.Has<Health>(hit) && frame.Get<Health>(hit).IsDead)
                continue;
                
            // Add coin to character inventory
            AddCoinToInventory(frame, hit);
            
            // Deactivate coin
            filter.ObjectivePoint->IsActive = false;
            
            // Set respawn timer
            frame.Timer.Set(filter.Entity, "RespawnTimer", frame.RuntimeConfig.CoinRespawnTime, () => {
                if (frame.Exists(filter.Entity))
                {
                    ObjectivePoint* point = frame.Unsafe.GetPointer<ObjectivePoint>(filter.Entity);
                    point->IsActive = true;
                }
            });
            
            // Send collection event
            frame.Events.CoinCollected(hit);
            
            break;
        }
    }
    
    private void AddCoinToInventory(Frame frame, EntityRef character)
    {
        Inventory* inventory = frame.Unsafe.GetPointer<Inventory>(character);
        
        // Create coin item
        InventoryItem coinItem = new InventoryItem
        {
            Type = EItemType.Coin,
            Value = 1
        };
        
        // Add to inventory
        inventory->Items.Add(frame, coinItem);
    }
}
```

## Game State-Specific Commands

Various commands handle specific game state changes:

```csharp
// Trigger character selection phase
public unsafe class TriggerCharacterSelectionCommand : Command
{
    public override void Execute(Frame frame)
    {
        frame.Events.StartCharacterSelection();
        frame.Signals.OnCharacterSelectionStart(frame);
    }
}

// Trigger arena presentation before match
public unsafe class TriggerArenaPresentationCommand : Command
{
    public override void Execute(Frame frame)
    {
        frame.Events.ArenaPresentation();
    }
}

// Trigger match countdown
public unsafe class TriggerCountdownCommand : Command
{
    public override void Execute(Frame frame)
    {
        frame.Events.CountdownStarted();
        
        // Disable player controls during countdown
        frame.Signals.OnToggleControllers(frame, false);
    }
}

// Start the actual match
public unsafe class StartGameCommand : Command
{
    public override void Execute(Frame frame)
    {
        // Set match duration
        frame.Global->MatchDuration = frame.RuntimeConfig.MatchDuration;
        
        // Reset match timer
        frame.Global->MatchTimer = 0;
        
        // Enable player controls
        frame.Signals.OnToggleControllers(frame, true);
        
        // Trigger game start
        frame.Events.CountdownStopped();
        frame.Signals.OnGameStart(frame);
    }
}
```

## HFSM Decision Classes

Custom HFSM decision classes implement game state transitions:

```csharp
// Check if a team has won the match
public class TeamHasWon : HFSMDecision
{
    private const byte SCORE_THRESHOLD = 10;
    private const byte HOLD_TIME_REQUIRED = 15;
    
    public override Boolean Decide(Frame frame, EntityRef entity)
    {
        // Check each team
        for (int i = 0; i < frame.Global->Teams.Length; i++)
        {
            TeamData* team = &frame.Global->Teams[i];
            
            // Check win condition
            if (team->Score >= SCORE_THRESHOLD && team->ScoreTimer >= HOLD_TIME_REQUIRED)
            {
                return true;
            }
        }
        
        return false;
    }
}

// Check if enough players have joined
public class HasEnoughPlayers : HFSMDecision
{
    public override Boolean Decide(Frame frame, EntityRef entity)
    {
        int playerCount = 0;
        
        // Count connected players
        for (int i = 0; i < frame.RuntimeConfig.PlayerCount; i++)
        {
            if (!frame.PlayerIsBot(i))
            {
                playerCount++;
            }
        }
        
        // Check if minimum player count reached
        return playerCount >= frame.RuntimeConfig.MinimumPlayerCountToStart;
    }
}
```

## Best Practices

1. **HFSM for Game Flow**: Use Hierarchical Finite State Machine for game state management
2. **Clear Game States**: Define explicit game states with clear transitions
3. **Team-Based Logic**: Organize team data and victory conditions
4. **Modular Systems**: Separate concerns into distinct systems
5. **Event-Based Communication**: Use events for synchronizing game state changes
6. **Timed State Transitions**: Use timers for state duration management
7. **Data-Driven Configuration**: Use runtime config for game parameters

## Implementation Notes

1. The game manager uses an HFSM to control the overall game flow
2. The coin grab game mode tracks team scores and victory conditions
3. Character selection occurs before the match starts
4. Players can be replaced by bots when they disconnect
5. All game state changes are communicated through events
6. Match timing and score tracking use deterministic calculations
7. Game configuration parameters are defined in runtime config