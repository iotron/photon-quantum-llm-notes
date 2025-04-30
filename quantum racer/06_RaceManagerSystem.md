# Race Manager System Implementation

The `RaceManagerSystem` controls the overall race loop, spawning vehicles, tracking race state, and determining vehicle positions.

## Class Definition

```csharp
[Preserve]
public unsafe class RaceManagerSystem : SystemMainThread, ISignalSpawn
{
    private Comparer _comparer = new Comparer();
    
    // Implementation follows...
}
```

## Race States

The race goes through several states defined in the `RaceState` enum:
```csharp
enum RaceState {
    Start,    // Pre-race countdown
    Running,  // Race in progress
    Finished  // Race completed
}
```

## Key Methods

### OnInit

Initializes the race when a game session starts:

```csharp
public override void OnInit(Frame f)
{
    // Create race manager singleton
    f.GetOrAddSingleton<RaceManager>();
    var raceConfig = f.FindAsset(f.RuntimeConfig.RaceConfig);
    
    if (f.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
    {
        // Initialize vehicle list
        manager->Vehicles = f.AllocateList<EntityRef>();
        // Set countdown timer
        manager->RaceTime = raceConfig.StartCountDown;
        // Set initial state
        manager->State = RaceState.Start;
    }

    // Calculate directions between checkpoints
    var checkpoints = f.Filter<Transform2D, Checkpoint>();
    while (checkpoints.NextUnsafe(out var e, out var t, out var c))
    {
        var otherTransform = f.Get<Transform2D>(c->Next);
        c->DirectionToNext = (otherTransform.Position - t->Position).Normalized;
        Log.Info("computed direction: " + c->DirectionToNext);
    }
}
```

### Update

The main update method that handles the race state progression:

```csharp
public override void Update(Frame f)
{
    if (f.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
    {
        switch (manager->State)
        {
            case RaceState.Start:
                // Countdown timer
                manager->RaceTime -= f.DeltaTime;
                if (manager->RaceTime <= 0)
                {
                    // Start race
                    manager->State = RaceState.Running;
                    manager->RaceTime = 0;
                    // Fill empty slots with bots
                    FillWithBots(f);
                }
                break;
                
            case RaceState.Running:
                // Update race timer
                manager->RaceTime += f.DeltaTime;
                
                // Sort vehicles by position
                var vehicles = f.ResolveList(manager->Vehicles);
                _comparer.SetFrame(f);
                vehicles.Sort(_comparer);
                
                // Update position info for each vehicle
                int count = 0;
                foreach (var car in vehicles)
                {
                    if (f.Unsafe.TryGetPointer<Racer>(car, out var racer))
                    {
                        racer->Position = count + 1;
                        
                        // Track cars ahead and behind
                        if (count > 0) 
                            racer->CarAhead = vehicles[count - 1];
                        else 
                            racer->CarAhead = default;
                            
                        if (count < vehicles.Count - 1) 
                            racer->CarBehind = vehicles[count + 1];
                        else 
                            racer->CarBehind = default;
                            
                        count++;
                    }
                }
                break;
                
            case RaceState.Finished:
                // Race is over, no active updates
                break;
        }
    }
}
```

### FillWithBots

Adds bot players to empty player slots in the race:

```csharp
private void FillWithBots(Frame frame)
{
    var botsConfig = frame.FindAsset(frame.RuntimeConfig.Bots);
    int count = 0;
    
    // Check each player slot
    for (int i = 0; i < frame.PlayerCount; i++)
    {
        // If slot is empty
        if ((frame.GetPlayerInputFlags(i) & DeterministicInputFlags.PlayerNotPresent) != 0)
        {
            count++;
            // Select bot difficulty based on count
            var botConfigRef = botsConfig.Configs[0];
            if (count > botsConfig.MaxBots / 3)
                botConfigRef = botsConfig.Configs[1];
            if (count > (2 * botsConfig.MaxBots) / 3)
                botConfigRef = botsConfig.Configs[2];
                
            // Spawn bot in this slot
            frame.Signals.Spawn(i, frame.FindAsset(botConfigRef));
        }

        // Stop if we've reached max bots
        if (count >= botsConfig.MaxBots) break;
    }
}
```

### ISignalSpawn.Spawn

Handles spawning a new player or bot vehicle:

```csharp
public void Spawn(Frame f, PlayerRef player, BotConfig botConfig)
{
    // Get bot configuration
    var bots = f.FindAsset<BotConfigContainer>(f.RuntimeConfig.Bots);
    bots.GetBot(f, player, out var prototype);
    
    // If not a bot, use player's selected vehicle
    if (botConfig == null)
    {
        var data = f.GetPlayerData(player);
        prototype = data.PlayerAvatar;
    }

    // Create the entity from prototype
    var e = f.Create(prototype);

    // If it's a bot, add the Bot component
    if (botConfig != null)
    {
        f.Add<Bot>(e);
    }

    // Link to player
    if (f.Unsafe.TryGetPointer(e, out RacerPlayerLink* link))
    {
        link->Player = player;
    }

    // Position the vehicle in the starting grid
    if (f.Unsafe.TryGetPointer(e, out Transform2D* t))
    {
        var spawnConfig = f.FindAsset<SpawnConfig>(f.Map.UserAsset);
        var playersPerRow = spawnConfig.PlayersPerRow;
        
        // Calculate grid position
        FP x = (player % playersPerRow) * spawnConfig.SpawnLateralSeparation;
        FP y = (player / playersPerRow) * spawnConfig.SpawnForwardSeparation;
        y += spawnConfig.SpawnForwardSeparation * (player % playersPerRow) / playersPerRow;

        t->Position = spawnConfig.BaseSpawn + new FPVector2(x, y);
        
        // Setup racer component
        if (f.Unsafe.TryGetPointer(e, out Racer* racer))
        {
            var config = f.FindAsset(racer->Config);
            
            if (f.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
            {
                // Set initial checkpoint
                racer->NextCheckpoint = manager->StartCheckpoint;
                racer->LastCheckpointPosition = t->Position;
                racer->Energy = config.InitialEnergy;
                
                // Add to vehicle list
                var vehicles = f.ResolveList(manager->Vehicles);
                vehicles.Add(e);

                // Configure bot-specific properties
                if (f.Unsafe.TryGetPointer<Bot>(e, out var bot))
                {
                    bot->Config = botConfig;
                    bot->NickIndex = player;
                    bot->RacingLineCheckpoint = manager->StartBotCheckpoint;
                    bot->RacingLineReset = manager->StartBotCheckpoint;
                    bot->StartTimer = bots.BotStartInterval * player;
                    
                    // Select a random raceline
                    var racelineToPick = f.Global->RngSession.Next(0, spawnConfig.AvailableRacelines.Length);
                    bot->Raceline = spawnConfig.AvailableRacelines[racelineToPick];
                }
            }

            // Set physics body mass
            if (f.Unsafe.TryGetPointer(e, out PhysicsBody2D* body))
            {
                body->Mass = config.Mass;
            }
        }
    }
}
```

## Position Calculation and Sorting

The `Comparer` private class handles sorting vehicles by their race position:

```csharp
private class Comparer : IComparer<EntityRef>
{
    private Frame _frame;

    public void SetFrame(Frame f)
    {
        _frame = f;
    }

    public int Compare(EntityRef x, EntityRef y)
    {
        if (_frame.Unsafe.TryGetPointer<Racer>(x, out var xRacer) &&
            _frame.Unsafe.TryGetPointer<Racer>(y, out var yRacer))
        {
            // Calculate total distance for sorting
            var xTotal = xRacer->LapData.TotalDistance != 0 ? xRacer->LapData.TotalDistance : -x.Index;
            var yTotal = yRacer->LapData.TotalDistance != 0 ? yRacer->LapData.TotalDistance : -y.Index;
            
            // Add a bonus to finished vehicles
            if (xRacer->Finished) xTotal += (_frame.PlayerCount - xRacer->Position) * 100;
            if (yRacer->Finished) yTotal += (_frame.PlayerCount - yRacer->Position) * 100;
            
            // Compare distances
            if (xTotal > yTotal)
                return -1;
            if (xTotal < yTotal)
                return 1;
        }
        return 0;
    }
}
```

## Implementation Notes

- Uses a state machine for race progression
- Manages race countdown and runtime timers
- Spawns vehicles in a grid formation
- Tracks race positions in real-time
- Uses dynamic bot difficulty based on quantity
- Maintains vehicle proximity awareness (ahead/behind)
- Tracks race position using lap count, checkpoints, and distance traveled
