# AI Integration in KartSystem

## Overview

The `KartSystem` class is central to the Quantum Karts game, managing both player-controlled and AI-controlled karts. It's responsible for:

1. Spawning karts for both players and AI
2. Handling player connections and disconnections
3. Managing AI lifecycle (creation, destruction, toggling)
4. Processing inputs from both players and AI
5. Updating kart physics and game state

## System Definition

The KartSystem implements several interfaces to handle various events:

```csharp
public unsafe class KartSystem : SystemMainThreadFilter<KartSystem.Filter>, 
    ISignalOnPlayerConnected, 
    ISignalOnPlayerDisconnected,
    ISignalOnPlayerAdded, 
    ISignalRaceStateChanged, 
    ISignalPlayerFinished, 
    ISignalOnComponentAdded<RaceProgress>,
    ISignalOnComponentRemoved<RaceProgress>
{
    // Implementation
}
```

## AI Integration Points

### 1. Spawning AI Drivers

The KartSystem has several methods for spawning AI drivers:

```csharp
private void SpawnAIDrivers(Frame frame)
{
    RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
    byte count = frame.RuntimeConfig.AICount;

    for (int i = 0; i < count; i++)
    {
        SpawnAIDriver(frame, rs.GetRandomAIConfig(frame));
    }
}
```

### 2. AI Driver Creation

```csharp
private void SpawnAIDriver(Frame frame, AssetRef<AIDriverSettings> driverAsset)
{
    if (driverAsset == null)
    {
        RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
        driverAsset = rs.GetRandomAIConfig(frame);
    }

    var driverData = frame.FindAsset(driverAsset);
    EntityRef kartEntity = SpawnKart(frame, driverData.KartVisuals, driverData.KartStats);
    frame.Add<AIDriver>(kartEntity);

    if (frame.Unsafe.TryGetPointer(kartEntity, out AIDriver* ai) && 
        frame.Unsafe.TryGetPointerSingleton(out Race* race))
    {
        ai->AIIndex = race->SpawnedAIDrivers++;
    }

    ToggleKartEntityAI(frame, kartEntity, true);
}
```

### 3. Auto-Filling Empty Slots

The system can automatically fill the race with AI karts to reach the desired player count:

```csharp
private void FillWithAI(Frame frame)
{
    int playerCount = frame.ComponentCount<Kart>();
    int missingDrivers = frame.RuntimeConfig.DriverCount - playerCount;

    if (missingDrivers <= 0)
    {
        return;
    }

    RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);

    for (int i = 0; i < missingDrivers; i++)
    {
        SpawnAIDriver(frame, rs.GetRandomAIConfig(frame));
    }
}
```

### 4. Toggling AI Control

A key method that enables or disables AI control for a kart:

```csharp
private void ToggleKartEntityAI(Frame frame, EntityRef kartEntity, bool useAI, 
    AssetRef<AIDriverSettings> settings = default)
{
    if (kartEntity == default) { return; }

    if (useAI)
    {
        AddResult result = frame.Add<AIDriver>(kartEntity);

        if (result != 0)
        {
            AIDriver* drivingAI = frame.Unsafe.GetPointer<AIDriver>(kartEntity);

            if (settings == default)
            {
                RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
                settings = rs.GetRandomAIConfig(frame);
            }

            drivingAI->SettingsRef = settings;
            drivingAI->UpdateTarget(frame, kartEntity);
        }
    }
    else if (frame.Unsafe.TryGetPointer(kartEntity, out AIDriver* ai))
    {
        frame.Remove<AIDriver>(kartEntity);
    }
}
```

### 5. Player Disconnect Handling

When a player disconnects, their kart is taken over by an AI:

```csharp
public void OnPlayerDisconnected(Frame frame, PlayerRef player)
{
    ToggleKartEntityAI(frame, FindPlayerKartEntity(frame, player), true);
}
```

### 6. Player Connect Handling

When a player connects, any AI controlling their kart is removed:

```csharp
public void OnPlayerConnected(Frame frame, PlayerRef player)
{
    ToggleKartEntityAI(frame, FindPlayerKartEntity(frame, player), false);
}
```

### 7. Race State Changes

AI drivers are spawned when the race is in the waiting state and can be automatically added to fill slots during countdown:

```csharp
public void RaceStateChanged(Frame frame, RaceState state)
{
    if (state == RaceState.Waiting)
    {
        SpawnAIDrivers(frame);
        return;
    }

    if (state == RaceState.Countdown && frame.RuntimeConfig.FillWithAI)
    {
        FillWithAI(frame);
        return;
    }
}
```

### 8. Player Finish Handling

When a player finishes, their kart is taken over by AI:

```csharp
public void PlayerFinished(Frame f, EntityRef entity)
{
    ToggleKartEntityAI(f, entity, true);
}
```

## Input Processing

The most important integration point is in the `Update` method, where the KartSystem processes inputs from both players and AI:

```csharp
public override void Update(Frame frame, ref Filter filter)
{
    Input input = default;

    // Check if the race has started
    if (!frame.Unsafe.TryGetPointerSingleton(out Race* race) || 
        (race->CurrentRaceState < RaceState.InProgress))
    {
        // Pre-race handling code
        return;
    }

    filter.RaceProgress->Update(frame, filter);

    if (frame.Unsafe.TryGetPointer(filter.Entity, out RespawnMover* respawnMover))
    {
        // Skip kart control during respawn
        return;
    }

    // Get input from AI or player
    if (frame.Unsafe.TryGetPointer(filter.Entity, out AIDriver* ai))
    {
        ai->Update(frame, filter, ref input);
    }
    else if (frame.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* playerLink))
    {
        input = *frame.GetPlayerInput(playerLink->Player);
    }

    // Process respawn requests
    if (input.Respawn)
    {
        frame.Add<RespawnMover>(filter.Entity);
    }

    // Process powerup usage
    if (input.Powerup.WasPressed && 
        frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
    {
        weapons->UseWeapon(frame, filter);
    }

    // Process hit reactions
    filter.KartHitReceiver->Update(frame, filter);
    if (filter.KartHitReceiver->HitTimer > 0)
    {
        input.Direction = FPVector2.Zero;
        filter.Drifting->Direction = 0;
    }

    // Update kart components with processed input
    filter.KartInput->Update(frame, input);
    filter.Wheels->Update(frame);
    filter.Drifting->Update(frame, filter);
    filter.Kart->Update(frame, filter);
}
```

## Kart Spawning

Both player and AI karts are spawned using the same method, which ensures consistent behavior:

```csharp
private EntityRef SpawnKart(Frame frame, AssetRef<KartVisuals> visuals, AssetRef<KartStats> stats)
{
    int driverIndex = frame.ComponentCount<Kart>();

    RaceSettings settings = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
    var prototype = frame.FindAsset(settings.KartPrototype);
    var entity = frame.Create(prototype);

    frame.Unsafe.TryGetPointerSingleton<RaceTrack>(out RaceTrack* track);

    if (frame.Unsafe.TryGetPointer<Transform3D>(entity, out var transform))
    {
        track->GetStartPosition(frame, driverIndex, out FPVector3 pos, out FPQuaternion rot);
        transform->Position = pos;
        transform->Rotation = rot;
    }

    if (frame.Unsafe.TryGetPointer(entity, out RaceProgress* raceProgress))
    {
        raceProgress->Initialize(track->TotalLaps);
    }

    Kart* kartComp = frame.Unsafe.GetPointer<Kart>(entity);

    kartComp->VisualAsset = visuals.Id;
    kartComp->StatsAsset = stats.Id;

    return entity;
}
```

## Configuration

The KartSystem uses several configuration parameters from `RuntimeConfig`:

- `AICount`: Number of AI drivers to spawn initially
- `DriverCount`: Total desired number of drivers (players + AI)
- `FillWithAI`: Whether to automatically fill empty slots with AI
- `RaceSettings`: Reference to race settings (including AI configurations)

## Performance Considerations

- AI processing is done on the main thread to ensure determinism
- Each AI makes decisions independently without coordination
- The AI logic is lightweight to ensure good performance with many AI karts
