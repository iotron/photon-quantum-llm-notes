# Quantum Networking Considerations for Bots

## Deterministic Bot Implementation in Networked Games

The Photon Quantum framework uses a deterministic lockstep simulation model, where all game logic must produce identical results on all connected clients. This places specific requirements on bot implementation in a networked context.

## Core Networking Principles

### Deterministic Execution

All bot decision-making must be fully deterministic and based solely on:
1. The current state of the frame
2. Fixed asset data
3. Deterministic random number generation (when needed)

```csharp
// Example of deterministic bot spawning
public void SpawnBots(Frame f, int botCount) {
    for (int i = 0; i < botCount; i++) {
        // Use deterministic RNG from the frame
        var botTypeIndex = f.Global->RngSession.Next(0, Configs.Length);
        var botPrefabIndex = f.Global->RngSession.Next(0, Prefabs.Length);
        
        // Spawn bot with deterministic parameters
        var prototype = Prefabs[botPrefabIndex];
        var position = SpawnPositions[i];
        
        // Create entity
        var botEntity = f.Create(prototype);
        
        // Configure bot
        if (f.Unsafe.TryGetPointer<Bot>(botEntity, out var bot)) {
            bot->Config = Configs[botTypeIndex];
            bot->NickIndex = f.Global->RngSession.Next(0, Nicknames.Length);
            // Additional setup...
        }
    }
}
```

### Avoiding Client-Specific Data

Bots should never use:
- Local player input that hasn't been synchronized
- System time or non-deterministic random functions
- Client-specific settings or information

### Network Event Synchronization

When client-specific events must affect bots (e.g., a local player's action), they must be properly synchronized through the Quantum frame:

```csharp
// Client-side code to request a bot difficulty adjustment
public void RequestBotDifficultyAdjustment(bool increase) {
    // Send an input command that will be processed deterministically by all peers
    var input = new QTuple<bool>(increase);
    QuantumRunner.Default.Game.SendCommand(AdjustBotDifficultyCommand.Create(input));
}

// Server-side command handler (executed deterministically on all peers)
public class AdjustBotDifficultyCommand : DeterministicCommand {
    public bool Increase;
    
    public override void Execute(Frame f) {
        // Find bot controller entity
        if (f.TryFindSingleton<BotController>(out var controllerEntity)) {
            var controller = f.GetPointer<BotController>(controllerEntity);
            
            // Adjust difficulty deterministically
            if (Increase) {
                controller->DifficultyLevel = FPMath.Min(controller->DifficultyLevel + FP._0_10, FP._1_00);
            } else {
                controller->DifficultyLevel = FPMath.Max(controller->DifficultyLevel - FP._0_10, FP._0_10);
            }
            
            // Apply to all bots
            f.Foreach((EntityRef entity, ref Bot bot) => {
                // Apply difficulty adjustment...
            });
        }
    }
}
```

## Bot Spawning in Networked Games

### Network-Synchronized Spawning

In a networked game, bot spawning should be controlled by the server or a designated client (typically the host/master client):

```csharp
// Server-side bot spawning system
public class ServerBotSpawnSystem : SystemSignalsOnly, ISignalOnPlayerDataSet {
    public void OnPlayerDataSet(Frame f, PlayerRef player) {
        // Calculate how many bots to spawn based on player count
        var humanPlayerCount = f.PlayerCount;
        var desiredTotalRacers = f.RuntimeConfig.DesiredRacerCount;
        var botsToSpawn = FPMath.Max(0, desiredTotalRacers - humanPlayerCount);
        
        // Only host/master spawns bots to avoid duplicates
        if (f.PlayerIsLocal(player) && player == PlayerRef.GetFirst()) {
            SpawnBots(f, (int)botsToSpawn);
        }
    }
    
    private void SpawnBots(Frame f, int botCount) {
        var botContainer = f.FindAsset<BotConfigContainer>();
        for (int i = 0; i < botCount; i++) {
            botContainer.GetBot(f, default, out var prototype);
            // Spawn the bot...
        }
    }
}
```

### Staggered Bot Spawning

For race games where all bots shouldn't appear simultaneously, implement staggered spawning:

```csharp
public class StaggeredBotSpawnSystem : SystemMainThread, ISignalRaceStart {
    public void OnRaceStart(Frame f) {
        // Schedule bot spawning over time
        var botContainer = f.FindAsset<BotConfigContainer>();
        var interval = botContainer.BotStartInterval;
        var spawnDelay = FP._0;
        
        for (int i = 0; i < botContainer.MaxBots; i++) {
            // Schedule each bot with increasing delay
            f.Events.ScheduleBot(f.Number + (spawnDelay.AsInt));
            spawnDelay += interval;
        }
    }
}

// Signal handler for scheduled bot spawning
public class BotScheduleSystem : SystemSignalsOnly, ISignalScheduleBot {
    public void OnScheduleBot(Frame f) {
        // Only host/master spawns bots to avoid duplicates
        if (f.PlayerIsLocalAndFirstPeer) {
            // Spawn a single bot...
        }
    }
}
```

## Network Optimization for Bots

### Minimizing Network Impact

Bots don't directly add network traffic in Quantum's deterministic model, as their behavior is computed locally on each client. However, they increase:
1. Simulation complexity
2. Frame verification data size

Optimize by:

#### Pooling Bot Entities

```csharp
// Bot entity pooling system
public class BotPoolSystem : SystemMainThread {
    private List<EntityRef> _inactivePool = new List<EntityRef>();
    
    public EntityRef GetBotFromPool(Frame f, AssetRef<EntityPrototype> prototype) {
        if (_inactivePool.Count > 0) {
            // Reuse existing entity
            var entity = _inactivePool[_inactivePool.Count - 1];
            _inactivePool.RemoveAt(_inactivePool.Count - 1);
            
            // Reset entity state
            if (f.Unsafe.TryGetPointer<Bot>(entity, out var bot)) {
                *bot = default;
                // Configure bot...
            }
            
            return entity;
        } else {
            // Create new entity if pool is empty
            return f.Create(prototype);
        }
    }
    
    public void ReturnBotToPool(EntityRef entity) {
        _inactivePool.Add(entity);
        // Reset state or deactivate...
    }
}
```

#### Smart Bot Count Scaling

```csharp
// Dynamic bot scaling based on network conditions
public class DynamicBotScalingSystem : SystemMainThread {
    public override void Update(Frame f) {
        // Check if simulation is struggling
        var performanceMetrics = f.GetPerformanceMetrics();
        if (performanceMetrics.AverageFrameTimeMs > 16) {
            // Reduce bot count if performance is poor
            ReduceBotCount(f);
        }
    }
    
    private void ReduceBotCount(Frame f) {
        // Find lowest priority bot and remove it
        EntityRef botToRemove = default;
        var lowestPriority = FP.MaxValue;
        
        f.Foreach((EntityRef entity, ref Bot bot, ref RacerPlayerLink link) => {
            // Skip player-controlled racers
            if (link.Player.IsValid) return;
            
            // Calculate priority (e.g., distance to player)
            var priority = CalculateBotPriority(f, entity);
            if (priority < lowestPriority) {
                lowestPriority = priority;
                botToRemove = entity;
            }
        });
        
        if (botToRemove.IsValid) {
            // Return to pool instead of destroying
            f.Get<BotPoolSystem>().ReturnBotToPool(botToRemove);
        }
    }
}
```

## Network Error Handling for Bots

### Resynchronization After Network Issues

When network issues occur, bots should gracefully recover:

```csharp
public class BotResynchronizationSystem : SystemSignalsOnly, ISignalOnGameResyncFinished {
    public void OnGameResyncFinished(Frame f) {
        // Reset any stateful bot behavior that might be affected by resync
        f.Foreach((EntityRef entity, ref Bot bot) => {
            // Reset temporary bot state
            bot.Input = default;
            
            // Re-evaluate raceline position
            if (bot.RacingLineReset.IsValid) {
                bot.RacelineIndex = bot.RacelineIndexReset;
            }
        });
    }
}
```

### Handling Disconnected Players

When players disconnect, adjust bot behavior appropriately:

```csharp
public class PlayerDisconnectSystem : SystemSignalsOnly, ISignalOnPlayerDisconnected {
    public void OnPlayerDisconnected(Frame f, PlayerRef player) {
        // Find player's racer entity
        EntityRef playerRacer = default;
        f.Foreach((EntityRef entity, ref RacerPlayerLink link) => {
            if (link.Player == player) {
                playerRacer = entity;
                return;
            }
        });
        
        if (playerRacer.IsValid) {
            // Option 1: Convert player racer to bot
            if (f.TryGet<Racer>(playerRacer, out var racer)) {
                var bot = new Bot();
                // Configure bot with appropriate settings
                bot.Config = f.FindAsset<BotConfigContainer>().Configs[0];
                bot.NickIndex = f.Global->RngSession.Next(0, Nicknames.Length);
                
                // Add bot component to former player entity
                f.Add(playerRacer, bot);
                
                // Remove player link
                f.Remove<RacerPlayerLink>(playerRacer);
            }
            
            // Option 2: Remove player and spawn a replacement bot
            // f.Destroy(playerRacer);
            // SpawnReplacementBot(f);
        }
    }
}
```

## Performance Considerations

### Bot LOD (Level of Detail) System

Implement varying levels of bot AI complexity based on distance from human players:

```csharp
public class BotLODSystem : SystemMainThread {
    public FP HighDetailDistance = 50;
    public FP MediumDetailDistance = 100;
    
    public override void Update(Frame f) {
        // Find local player entities
        List<EntityRef> localPlayerEntities = new List<EntityRef>();
        f.Foreach((EntityRef entity, ref RacerPlayerLink link) => {
            if (f.PlayerIsLocal(link.Player)) {
                localPlayerEntities.Add(entity);
            }
        });
        
        // Update bot LOD based on distance to closest local player
        f.Foreach((EntityRef entity, ref Bot bot) => {
            var transform = f.Get<Transform2D>(entity);
            var closestDistance = FP.MaxValue;
            
            foreach (var playerEntity in localPlayerEntities) {
                var playerTransform = f.Get<Transform2D>(playerEntity);
                var distance = FPVector2.Distance(transform.Position, playerTransform.Position);
                closestDistance = FPMath.Min(closestDistance, distance);
            }
            
            // Set LOD level
            if (closestDistance <= HighDetailDistance) {
                bot.LODLevel = BotLODLevel.High;
            } else if (closestDistance <= MediumDetailDistance) {
                bot.LODLevel = BotLODLevel.Medium;
            } else {
                bot.LODLevel = BotLODLevel.Low;
            }
        });
    }
}

// BOT Update with LOD considerations
public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
    // Apply different AI complexities based on LOD level
    switch (filter.Bot->LODLevel) {
        case BotLODLevel.High:
            // Full AI with all features
            UpdateBotHighDetail(f, ref filter);
            break;
            
        case BotLODLevel.Medium:
            // Simplified AI (e.g., less frequent updates, simpler physics)
            UpdateBotMediumDetail(f, ref filter);
            break;
            
        case BotLODLevel.Low:
            // Minimal AI (basic movement, no collision avoidance)
            UpdateBotLowDetail(f, ref filter);
            break;
    }
}
```

By implementing these networking strategies, you can ensure that bots in your Quantum racing game perform consistently for all players while minimizing network overhead and optimizing performance.
