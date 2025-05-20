# Integration Guide: Adding Bots to Your Quantum Racing Game

This guide covers the practical steps for integrating the bot system into a Quantum racing game project, from initial setup to testing and deployment.

## Setup and Prerequisites

### Required Components and Systems

1. **Core Quantum Components**:
   - Ensure you have the Quantum SDK integrated into your Unity project
   - Set up basic Quantum framework components (QuantumGame, QuantumRunner, etc.)

2. **Required Bot Assets**:
   - Bot configurations (BotConfig assets)
   - Bot entity prefabs
   - Raceline data assets

3. **Required Systems**:
   - BotSystem
   - RacerSystem
   - RacerVelocityClampSystem
   - Other core racing systems

## Step 1: Creating the Basic Bot Components

### Define the Bot Component Structure

Create a file `Bot.qtn` in your Quantum DSL folder:

```csharp
component Bot {
    // References to track entities
    entity_ref RacingLineCheckpoint;
    entity_ref RacingLineReset;
    
    // Configuration and state
    asset_ref<BotConfig> Config;
    Input Input;
    int NickIndex;
    FP StartTimer;
    
    // Raceline navigation
    int RacelineIndex;
    int RacelineIndexReset;
    asset_ref<CheckpointData> Raceline;
    
    // Dynamic stats
    FP MaxSpeed;
    FP CurrentSpeed;
}
```

### Create the BotConfig Asset Class

Create a file `BotConfig.cs` in your simulation folder:

```csharp
namespace Quantum {
    using Photon.Deterministic;

    public unsafe class BotConfig : AssetObject {
        // Core configuration parameters
        public FP MaxSpeed = 10;
        public FPVector2 OverlapRelativeOffset = new FPVector2(0, 0);
        public FP OverlapDistance = 3;
        public FP CheckpointDetectionDistance = 5;
        public FP CheckpointDetectionDotThreshold = FP._0_50;
        public bool Debug = true;
        public FP RacelineSpeedFactor = 1;
        public FP LookAhead = FP._0_50;
        public bool SmoothLookAhead = false;
        public bool UseDirectionToNext;
        public FP RadiansSlowdownThreshold = FP.PiOver4;
        public FP SlowdownFactor = FP._0_50;
        
        // Implementation of bot behavior
        public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
            // Bot behavior implementation
            // ...
        }
        
        // Helper methods
        private void UpdateCheckpoint(Frame f, ref BotSystem.Filter filter) {
            // Implementation
        }
        
        private void GetCheckpointData(Frame f, ref BotSystem.Filter filter, 
            out FPVector2 checkpointPosition, out FPVector2 referencePosition,
            out FPVector2 directionToFollow, out FP maxSpeed,
            out FPVector2 directionToNext, out FP referenceSpeed) {
            // Implementation
        }
    }
}
```

### Create the BotSystem

Create a file `BotSystem.cs` in your simulation folder:

```csharp
namespace Quantum {
    using Photon.Deterministic;
    using UnityEngine.Scripting;

    [Preserve]
    public unsafe class BotSystem : SystemMainThreadFilter<BotSystem.Filter> {
        public override void Update(Frame f, ref Filter filter) {
            var botConfig = f.FindAsset(filter.Bot->Config);
            botConfig.UpdateBot(f, ref filter);
        }

        public struct Filter {
            public EntityRef Entity;
            public Transform2D* Transform;
            public Bot* Bot;
            public PhysicsBody2D* Body;
            public Racer* Racer;
        }
    }
}
```

## Step 2: Setting Up Raceline Recording and Data

### Create the CheckpointData Asset Class

Create a file `CheckpointData.cs` in your simulation folder:

```csharp
namespace Quantum {
    using Photon.Deterministic;
    using System.Collections.Generic;

    public class CheckpointData : AssetObject {
        public List<RacelineEntry> Raceline;
        public FP ReferenceRotationSpeed = 120;
        public FP DistanceBetweenMarks = 4;
    }
}
```

### Define the RacelineEntry Structure

Create a file `RacelineEntry.qtn` in your Quantum DSL folder:

```csharp
struct RacelineEntry {
    FP DesiredSpeed;
    FPVector2 Position;
}
```

### Create the Raceline Recording System

Create a file `RacelineRecorder.cs` in your view folder:

```csharp
namespace Quantum {
    using UnityEditor;
    using System.Collections.Generic;
    using Photon.Deterministic;

    public class RacelineContext : EntityViewContext {
        public CheckpointData CheckpointData;
    }
    
    public class RacelineRecorder : QuantumEntityViewComponent<RacelineContext> {
        private FPVector2 _lastPos;
        public FP distanceInterval = 4;
        public int StartLap = 2;
        public bool Record = false;

        public override void OnActivate(Frame frame) {
            var t = PredictedFrame.Get<Transform2D>(EntityRef);
            _lastPos = t.Position;
            if (Record) {
                ViewContext.CheckpointData.Raceline.Clear();
            }
        }

        public override void OnUpdateView() {
            if (Record == false) return;
            var racer = PredictedFrame.Get<Racer>(EntityRef);
            
            #if UNITY_EDITOR
            if (racer.LapData.Laps + 1 > StartLap) {
                var config = PredictedFrame.FindAsset(racer.Config);
                ViewContext.CheckpointData.ReferenceRotationSpeed = config.RotationSpeed;
                EditorUtility.SetDirty(ViewContext.CheckpointData);
            }
            #endif
            
            if (racer.LapData.Laps + 1 != StartLap) return;
            
            var t = PredictedFrame.Get<Transform2D>(EntityRef);
            var body = PredictedFrame.Get<PhysicsBody2D>(EntityRef);
            var distance = t.Position - _lastPos;
            if (distance.Magnitude >= distanceInterval) {
                var checkpoint = new RacelineEntry() {
                    Position = t.Position,
                    DesiredSpeed = body.Velocity.Magnitude
                };
                
                if (ViewContext.CheckpointData.Raceline == null)
                    ViewContext.CheckpointData.Raceline = new List<RacelineEntry>();
                
                ViewContext.CheckpointData.Raceline.Add(checkpoint);
                _lastPos = t.Position;
            }
        }
    }
}
```

### Create an Inspector Extension for Raceline Recording

Create a file `RacelineRecorderInspector.cs` in an editor folder:

```csharp
#if UNITY_EDITOR
namespace Quantum.Editor {
    using UnityEngine;
    using UnityEditor;

    [CustomEditor(typeof(RacelineRecorder))]
    public class RacelineRecorderInspector : UnityEditor.Editor {
        public override void OnInspectorGUI() {
            DrawDefaultInspector();
            
            var recorder = (RacelineRecorder)target;
            var context = recorder.GetComponent<EntityViewContext>() as RacelineContext;
            
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Raceline Recording", EditorStyles.boldLabel);
            
            if (context == null || context.CheckpointData == null) {
                EditorGUILayout.HelpBox("Please assign a CheckpointData asset to the EntityViewContext", MessageType.Warning);
                return;
            }
            
            EditorGUILayout.LabelField($"Recording to: {context.CheckpointData.name}");
            
            if (recorder.Record) {
                GUI.color = Color.red;
                if (GUILayout.Button("Stop Recording")) {
                    recorder.Record = false;
                    EditorUtility.SetDirty(recorder);
                }
                
                EditorGUILayout.LabelField($"Points recorded: {context.CheckpointData.Raceline?.Count ?? 0}");
            } else {
                GUI.color = Color.green;
                if (GUILayout.Button("Start Recording")) {
                    recorder.Record = true;
                    EditorUtility.SetDirty(recorder);
                }
            }
            GUI.color = Color.white;
            
            if (GUILayout.Button("Clear Recorded Data")) {
                if (EditorUtility.DisplayDialog("Clear Raceline Data", 
                    "Are you sure you want to clear all recorded raceline data?", "Yes", "Cancel")) {
                    if (context.CheckpointData.Raceline != null) {
                        context.CheckpointData.Raceline.Clear();
                        EditorUtility.SetDirty(context.CheckpointData);
                    }
                }
            }
        }
    }
}
#endif
```

## Step 3: Creating Bot Configuration Assets

### Create a BotConfigContainer

Create a file `BotConfigContainer.cs` in your simulation folder:

```csharp
namespace Quantum {
    using Photon.Deterministic;

    public unsafe class BotConfigContainer : AssetObject {
        public AssetRef<BotConfig>[] Configs;
        public AssetRef<EntityPrototype>[] Prefabs;
        public string[] Nicknames;
        
        public int MaxBots = 32;
        public FP BotStartInterval = 0;
        
        public void GetBot(Frame f, PlayerRef player, out AssetRef<EntityPrototype> prototype) {
            var prototypeIndex = f.Global->RngSession.Next(0, Prefabs.Length);
            prototype = Prefabs[prototypeIndex];
        }
    }
}
```

### Create Bot Configuration Assets in Unity

1. Create a derived BotConfig class for each difficulty level:

```csharp
// BotBasic.cs
namespace Quantum {
    using Photon.Deterministic;
    
    public class BotBasic : BotConfig {
        public BotBasic() {
            MaxSpeed = 7;
            RacelineSpeedFactor = FP._0_75;
            // Configure other parameters...
        }
    }
}
```

2. Create scriptable object assets:
   - In Unity, go to Assets → Create → Quantum → Bot Configs
   - Create instances of your BotConfig-derived classes
   - Configure parameters in the inspector

3. Create a container asset:
   - Create an instance of BotConfigContainer
   - Assign your BotConfig assets to the Configs array
   - Assign bot prefabs to the Prefabs array
   - Add a list of bot nicknames

## Step 4: Setting Up Bot Spawning

### Create a Bot Spawning System

Create a file `BotSpawningSystem.cs` in your simulation folder:

```csharp
namespace Quantum {
    using Photon.Deterministic;
    using UnityEngine.Scripting;

    [Preserve]
    public unsafe class BotSpawningSystem : SystemSignalsOnly, ISignalRaceStart {
        public void OnRaceStart(Frame f) {
            // Only host should spawn bots
            if (!f.PlayerIsLocalAndFirstPeer) return;
            
            // Find bot configuration container
            var botContainer = f.FindAsset<BotConfigContainer>(f.RuntimeConfig.BotContainerAsset);
            if (botContainer == null) return;
            
            // Calculate how many bots to spawn
            var humanPlayerCount = f.PlayerCount;
            var desiredRacerCount = f.RuntimeConfig.DesiredRacerCount;
            var botsToSpawn = FPMath.Min(botContainer.MaxBots, desiredRacerCount - humanPlayerCount);
            
            // Get race manager
            if (!f.TryFindSingleton<RaceManager>(out var raceManagerEntity)) return;
            var raceManager = f.Unsafe.GetPointer<RaceManager>(raceManagerEntity);
            
            // Find spawn points
            var spawnConfig = f.FindAsset<SpawnConfig>(f.Map.UserAsset);
            if (spawnConfig == null) return;
            
            // Spawn bots
            for (int i = 0; i < botsToSpawn; i++) {
                // Get a bot prefab
                botContainer.GetBot(f, default, out var botPrefab);
                
                // Calculate spawn position
                var spawnIndex = humanPlayerCount + i;
                if (spawnIndex >= spawnConfig.SpawnPositions.Length) {
                    // Wrap around or use random position if not enough spawn points
                    spawnIndex = spawnIndex % spawnConfig.SpawnPositions.Length;
                }
                
                var spawnPosition = spawnConfig.SpawnPositions[spawnIndex];
                var spawnRotation = spawnConfig.SpawnRotations[spawnIndex];
                
                // Create bot entity
                var botEntity = f.Create(botPrefab);
                
                // Set transform
                if (f.Unsafe.TryGetPointer<Transform2D>(botEntity, out var transform)) {
                    transform->Position = spawnPosition;
                    transform->Rotation = spawnRotation;
                }
                
                // Configure bot
                if (f.Unsafe.TryGetPointer<Bot>(botEntity, out var bot)) {
                    // Select a raceline
                    var racelineIndex = f.Global->RngSession.Next(0, spawnConfig.AvailableRacelines.Length);
                    bot->Raceline = spawnConfig.AvailableRacelines[racelineIndex];
                    
                    // Set delayed start
                    bot->StartTimer = i * botContainer.BotStartInterval;
                    
                    // Set nickname
                    bot->NickIndex = f.Global->RngSession.Next(0, botContainer.Nicknames.Length);
                }
                
                // Add to race manager vehicles
                if (raceManager->Vehicles.IsNull) {
                    var list = f.AllocateList(out raceManager->Vehicles, 16);
                    list.Add(botEntity);
                } else {
                    var list = f.ResolveList(raceManager->Vehicles);
                    list.Add(botEntity);
                }
            }
        }
    }
}
```

### Configure Quantum Runtime Settings

Ensure these settings are added to your `RuntimeConfig` in the Quantum SDK:

```csharp
// RuntimeConfig extensions
public AssetRef BotContainerAsset;
public int DesiredRacerCount = 8;
```

## Step 5: Creating and Recording Racelines

### Setting Up Raceline Recording

1. Create a CheckpointData asset:
   - Go to Assets → Create → Quantum → CheckpointData
   - Name it appropriately for your track (e.g., "Track1_Raceline")

2. Add recording components to a player vehicle:
   - Add a `RacelineContext` component
   - Assign your CheckpointData asset to it
   - Add a `RacelineRecorder` component
   - Configure distance interval (typically 3-5 units)
   - Set which lap to start recording (typically lap 2)

### Recording Process

1. Play the game in editor
2. Drive your vehicle around the track
3. Click "Start Recording" in the inspector when you're ready
4. Drive optimally around the track
5. Recording will automatically start on the configured lap
6. Points will be recorded at the specified distance intervals
7. The recording stops automatically after the lap
8. Save the CheckpointData asset

### Managing Multiple Racelines

For optimal bot behavior, create multiple racelines:
1. A clean, middle-of-the-road raceline for basic bots
2. An aggressive, corner-cutting raceline for advanced bots
3. Alternative lines for overtaking

## Step 6: Testing and Optimization

### Testing Bot Behavior

1. Enable debug visualization:
   - Set the `Debug` flag to true in your BotConfig assets
   - In Play mode, observe the debug rays and markers:
     - Green rays: Bot is following the raceline at full speed
     - Yellow/Red rays: Bot is slowing down for turns
     - Red circles: Reference positions on the raceline

2. Test with different numbers of bots:
   - Start with 1-2 bots to isolate issues
   - Gradually increase to test performance

3. Test bot interactions:
   - Watch for appropriate overtaking behavior
   - Check for collisions or traffic jams

### Optimizing Bot Performance

1. CPU Performance:
   - Adjust look-ahead distance based on speed
   - Use appropriate raceline point density
   - Consider LOD system for distant bots

2. Memory Optimization:
   - Use a single raceline asset for multiple bots
   - Pool bot entities when possible

3. Network Considerations:
   - Ensure all bot decisions are deterministic
   - Test synchronization across different network conditions

## Step 7: Customizing Bot Appearance

### Creating Bot Prefabs

1. Design vehicle prefabs for bots:
   - Create visually distinct vehicles
   - Add appropriate view components

2. Configure bot nickname display:
   - Create a UI component for displaying bot names
   - Connect it to the Bot.NickIndex

3. Add visual indicators:
   - Add distinct visual elements to indicate bot difficulty
   - Consider color-coding (e.g., green for easy, red for hard)

### Example: Bot Nickname Setup

```csharp
// Bot nickname display component
public class BotNicknameDisplay : QuantumMonoBehaviour {
    public TMPro.TextMeshProUGUI nameText;
    
    public override void OnEntityInstantiated() {
        if (quantum.Unsafe.TryGetPointer<Bot>(EntityRef, out var bot)) {
            var botContainer = quantum.FindAsset<BotConfigContainer>(quantum.RuntimeConfig.BotContainerAsset);
            if (botContainer != null && bot->NickIndex < botContainer.Nicknames.Length) {
                nameText.text = botContainer.Nicknames[bot->NickIndex];
            }
        }
    }
}
```

## Step 8: Final Integration

### Incorporating Bots into Game Flow

1. Add bot-related UI:
   - Display bot count settings in the lobby
   - Add bot difficulty selection option

2. Integrate with race management:
   - Ensure bots are counted in race standings
   - Handle bot finishing positions

3. Add bot statistics:
   - Track bot performance metrics
   - Display bot lap times and positions

4. Fine-tune difficulty:
   - Balance bot parameters based on testing
   - Consider dynamic difficulty adjustment

### Example: Dynamic Bot Difficulty Adjustment

```csharp
// Dynamic difficulty adjustment system
[Preserve]
public unsafe class DynamicBotDifficultySystem : SystemMainThread {
    public override void Update(Frame f) {
        // Find local player
        EntityRef localPlayerEntity = EntityRef.None;
        f.Foreach((EntityRef entity, ref RacerPlayerLink link) => {
            if (f.PlayerIsLocal(link.Player)) {
                localPlayerEntity = entity;
                return;
            }
        });
        
        if (!localPlayerEntity.IsValid) return;
        
        // Get player position
        var playerRacer = f.Unsafe.GetPointer<Racer>(localPlayerEntity);
        var playerPosition = playerRacer->Position;
        
        // Adjust bot behavior based on player position
        f.Foreach((EntityRef entity, ref Bot bot) => {
            var botRacer = f.Unsafe.GetPointer<Racer>(entity);
            var botConfig = f.FindAsset(bot->Config);
            
            // If player is far behind, make bots slightly easier
            if (playerPosition > botRacer->Position + 3) {
                bot->MaxSpeed = botConfig.MaxSpeed * FP._0_90;
            }
            // If player is dominating, make bots slightly harder
            else if (playerPosition < botRacer->Position - 3) {
                bot->MaxSpeed = botConfig.MaxSpeed * FP._1_10;
            }
            // Normal difficulty
            else {
                bot->MaxSpeed = botConfig.MaxSpeed;
            }
        });
    }
}
```

By following this integration guide, you should have a fully functional bot system in your Quantum racing game. The bots will follow optimized racing lines, interact with players and each other, and provide an engaging competitive experience for your players.
