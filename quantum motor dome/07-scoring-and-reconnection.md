# Quantum Motor Dome Scoring and Reconnection

This document explains the scoring system and reconnection mechanics in Quantum Motor Dome, covering how players earn points and the mechanics of trail reconnection.

## Scoring System Overview

The game features multiple ways for players to earn points:

1. **Trail Reconnection**: Connecting your ship's head to its own trail
2. **Player Elimination**: Eliminating other players by causing them to collide with your trail
3. **Pickup Collection**: Collecting trail pickups increases trail length (score)

Points are stored in the global player data dictionary:

```qtn
struct PlayerData
{
	bool ready;
	Int16 points;
}

global
{
	dictionary<Int32, PlayerData> playerData;
	// Other global properties...
}
```

## Trail Growth and Score

The Ship component tracks each player's score, which directly correlates to trail length:

```qtn
component Ship
{
	[Header("Runtime Properties")]
	FP BoostAmount;
	int Score;
	list<FPVector3> Segments;
	list<PhysicsQueryRef> SegmentQueries;
	
	// Other properties...
}
```

The Score property serves two purposes:
1. It represents the number of trail segments the ship should have
2. It's used for calculating points in reconnection and other scoring opportunities

## Trail Pickup Collection

Collecting trail pickups increases the ship's score (trail length):

```csharp
public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
{
    if (!f.TryGet(info.Other, out TrailPickup pickup)) return;
    if (!f.Unsafe.TryGetPointer(info.Entity, out Ship* ship)) return;
    if (!f.TryGet(info.Entity, out PlayerLink link)) return;

    // Increase score (trail length)
    int oldScore = ship->Score;
    ship->Score += ship->Score > 0 ? 5 : 2;
    f.Events.PlayerScoreChanged(link.Player, oldScore, ship->Score);
    
    // Rest of implementation...
}
```

Key aspects of trail pickup scoring:
1. **Progressive Value**: Pickups are worth more (5 segments) for ships that already have a trail
2. **Starter Value**: Pickups are worth less (2 segments) for ships with no trail
3. **Event Notification**: Fires an event to update UI elements with the new score

## Reconnection Mechanics

The reconnection mechanic is a core gameplay element where players connect their ship back to their own trail to score points.

### Detection

Reconnection is detected in the collision system:

```csharp
private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
{
    // Check if this is a self-collision
    if (hitEntity == entity)
    {
        // Only the head segment can reconnect
        if (segmentIndex == 0)
        {
            Ship* ship = f.Unsafe.GetPointer<Ship>(entity);
            Collections.QList<FPVector3> segments = f.ResolveList(ship->Segments);
            
            // Require minimum segment count for reconnection
            if (segments.Count < 10) return;
            
            // Check alignment between ship heading and trail direction
            Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
            FP dot = FPVector3.Dot(
                transform->Forward,
                (segments[1] - segments[0]).Normalized
            );
            
            // Reconnection successful if alignment is good
            if (dot > spec.connectThreshold)
            {
                // Reconnection successful!
                HandleReconnection(f, entity, ship, segments);
            }
        }
    }
    
    // Rest of collision handling...
}
```

Key aspects of reconnection detection:
1. **Segment Index Check**: Only the head segment (segmentIndex == 0) can reconnect
2. **Minimum Length**: Requires a minimum number of segments (typically 10)
3. **Alignment Check**: Checks that the ship is facing in roughly the same direction as the trail
4. **Threshold Comparison**: Uses a configurable threshold for the alignment dot product

### Alignment Requirement

The alignment check ensures that reconnection requires skill and intentionality:

```csharp
// Check alignment between ship heading and trail direction
Transform3D* transform = f.Unsafe.GetPointer<Transform3D>(entity);
FP dot = FPVector3.Dot(
    transform->Forward,
    (segments[1] - segments[0]).Normalized
);

// Reconnection successful if alignment is good
if (dot > spec.connectThreshold)
{
    // Reconnection successful!
    // Implementation...
}
```

This calculation:
1. Gets the ship's forward direction
2. Gets the direction of the first trail segment
3. Calculates the dot product (cosine of the angle between them)
4. Compares against the connectThreshold (typically 0.7-0.9)

The configuration is stored in the `ShipSpec` asset:

```csharp
public partial class ShipSpec : AssetObject
{
    // Other properties...
    [Range(0, 1)] public FP connectThreshold;
    public FP despawnAfterConnectDelay;
}
```

### Point Calculation

When reconnection is successful, points are awarded based on trail length:

```csharp
private void HandleReconnection(Frame f, EntityRef entity, Ship* ship, Collections.QList<FPVector3> segments)
{
    // Get player link
    f.Unsafe.TryGetPointer(entity, out PlayerLink* link);
    
    // Award points based on trail length (squared for exponential reward)
    int points = ship->Score * ship->Score / 10;
    f.Global->playerData.Resolve(f, out var dict);
    dict.TryGetValuePointer(link->Player, out var pd);
    pd->points += (short)points;
    
    // Send event
    f.Events.PlayerReconnected(entity, segments.Count);
    
    // Add delay for respawn
    f.Add<Delay>(entity, new Delay { 
        TimeRemaining = spec.despawnAfterConnectDelay 
    });
    f.Events.PlayerDataChanged(link->Player, f.Number);
}
```

Key aspects of reconnection scoring:
1. **Quadratic Scaling**: Points awarded are proportional to the square of the trail length
2. **Division Factor**: The division by 10 balances the scoring to reasonable values
3. **Event Notification**: Fires events for UI feedback and visual effects
4. **Delayed Respawn**: Adds a delay before respawning to show the reconnection effect

### Visual Feedback

When reconnection occurs, the Unity side provides visual feedback:

```csharp
public class ReconnectionEffect : MonoBehaviour
{
    [SerializeField] private ParticleSystem reconnectionVFX;
    [SerializeField] private AudioClip reconnectionSound;
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventPlayerReconnected>(this, OnPlayerReconnected);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventPlayerReconnected>(this);
    }
    
    private void OnPlayerReconnected(EventPlayerReconnected evt)
    {
        // Find entity view
        var entityView = QuantumEntityView.FindEntityView(evt.Entity);
        if (entityView == null) return;
        
        // Play visual effect
        Instantiate(reconnectionVFX, entityView.transform.position, Quaternion.identity);
        
        // Play sound effect (volume based on segment count)
        float volume = Mathf.Clamp01(evt.SegmentCount / 50f);
        AudioSource.PlayClipAtPoint(reconnectionSound, entityView.transform.position, volume);
    }
}
```

### Reconnection Animation

The `ShipView` class handles the visual representation of reconnection:

```csharp
public unsafe class ShipView : MonoBehaviour
{
    public Transform pivot;
    public Transform socket;
    public Transform reconnectTarget;
    
    int? reconnectTick = null;
    
    private void Update()
    {
        if (reconnectTick.HasValue)
        {
            // Animate reconnection
            socket.rotation = Quaternion.RotateTowards(socket.rotation, pivot.rotation, 360 * Time.deltaTime);

            pivot.position = Vector3.MoveTowards(pivot.position, reconnectTarget.position, connectionSmoothSpeed * Time.deltaTime);
            pivot.rotation = Quaternion.RotateTowards(pivot.rotation, reconnectTarget.rotation, 360 * Time.deltaTime);

            return;
        }
        
        // Normal update...
    }
    
    void PlayerDataChangedCallback(EventPlayerDataChanged evt)
    {
        if (evt.Player == PlayerRef)
        {
            reconnectTick = evt.Tick;
            QuantumEvent.UnsubscribeListener<EventPlayerDataChanged>(this);
        }
    }
}
```

This animation:
1. Rotates the socket (start of the trail) to align with the ship's rotation
2. Moves the ship toward the reconnection target position
3. Rotates the ship to align with the reconnection target rotation

## Player Elimination Scoring

Players can earn points by eliminating other players:

```csharp
private void HandleCollision(Frame f, EntityRef entity, EntityRef hitEntity, int segmentIndex, ShipSpec spec)
{
    // Self-collision handling...
    // Ship-to-ship collision handling...
    
    // This must be a ship-to-trail collision
    DestroyShip(f, entity);
    
    // Award points to the owner of the trail
    f.Unsafe.TryGetPointer(entity, out PlayerLink* victimLink);
    f.Unsafe.TryGetPointer(hitEntity, out PlayerLink* killerLink);
    
    if (victimLink != null && killerLink != null && victimLink->Player != killerLink->Player)
    {
        f.Global->playerData.Resolve(f, out var dict);
        dict.TryGetValuePointer(killerLink->Player, out var pd);
        pd->points += 50;
        
        f.Events.PlayerKilled(victimLink->Player, killerLink->Player);
    }
}
```

Key aspects of elimination scoring:
1. **Fixed Value**: Eliminations are worth a fixed number of points (typically 50)
2. **Owner Verification**: Ensures the eliminating player isn't the same as the eliminated player
3. **Event Notification**: Fires an event for UI feedback

## Score Tracking and Display

Scores are displayed in the UI through events:

```csharp
public class ScoreboardUI : MonoBehaviour
{
    [SerializeField] private GameObject scoreEntryPrefab;
    [SerializeField] private Transform scoreboardContainer;
    
    private Dictionary<PlayerRef, ScoreEntry> scoreEntries = new Dictionary<PlayerRef, ScoreEntry>();
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventPlayerScoreChanged>(this, OnPlayerScoreChanged);
        QuantumEvent.Subscribe<EventPlayerKilled>(this, OnPlayerKilled);
        QuantumEvent.Subscribe<EventPlayerReconnected>(this, OnPlayerReconnected);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventPlayerScoreChanged>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerKilled>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerReconnected>(this);
    }
    
    private void OnPlayerScoreChanged(EventPlayerScoreChanged evt)
    {
        UpdateScore(evt.Player);
    }
    
    private void OnPlayerKilled(EventPlayerKilled evt)
    {
        UpdateScore(evt.Killer);
    }
    
    private void OnPlayerReconnected(EventPlayerReconnected evt)
    {
        // Find player ref from entity
        QuantumRunner.Default.Game.Frames.Verified.TryGetComponent<PlayerLink>(
            evt.Entity, out var playerLink);
        
        if (playerLink != null)
        {
            UpdateScore(playerLink.Player);
        }
    }
    
    private void UpdateScore(PlayerRef player)
    {
        // Get player score from global dictionary
        var game = QuantumRunner.Default.Game;
        game.Frames.Verified.Global.playerData.TryGetValue(
            player, out var playerData);
        
        // Update UI
        if (scoreEntries.TryGetValue(player, out var entry))
        {
            entry.UpdateScore(playerData.points);
        }
        else
        {
            // Create new score entry
            var newEntry = Instantiate(scoreEntryPrefab, scoreboardContainer).GetComponent<ScoreEntry>();
            newEntry.Initialize(player, playerData.points);
            scoreEntries[player] = newEntry;
        }
        
        // Sort scoreboard by score
        SortScoreboard();
    }
    
    private void SortScoreboard()
    {
        // Sort children by score
        var entries = scoreboardContainer.GetComponentsInChildren<ScoreEntry>()
            .OrderByDescending(e => e.Score)
            .ToList();
            
        // Update sibling indices to reorder
        for (int i = 0; i < entries.Count; i++)
        {
            entries[i].transform.SetSiblingIndex(i);
        }
    }
}
```

## Score Events

The scoring system generates several events for Unity visualization:

```qtn
event PlayerScoreChanged { player_ref Player; Int32 OldScore; Int32 NewScore; }
event PlayerKilled { player_ref Victim; player_ref Killer; }
event PlayerReconnected { entity_ref Entity; Int32 SegmentCount; }
event PlayerDataChanged { player_ref Player; Int32 Tick; }
```

These events enable:
1. **Score Updates**: Updating UI elements with new scores
2. **Kill Feed**: Showing kill notifications in the UI
3. **Reconnection Effects**: Playing visual and audio effects for reconnection
4. **Respawn Animation**: Triggering ship respawn animation

## Postgame Score Summary

When the game ends, scores are summarized in the postgame screen:

```csharp
public unsafe class PostgameSystem : SystemMainThread, IGameState_Postgame
{
    public override bool StartEnabled => false;
    
    public override void OnEnabled(Frame f)
    {
        // Calculate final scores and rankings
        var playerDataDict = f.Global->playerData.Resolve(f, out var dict);
        
        // Sort players by score
        var sortedPlayers = playerDataDict.OrderByDescending(kvp => kvp.Value.points).ToList();
        
        // Send final scores event
        f.Events.GameResults(
            sortedPlayers.Select(kvp => kvp.Key).ToArray(),
            sortedPlayers.Select(kvp => kvp.Value.points).ToArray()
        );
        
        // Start postgame timer
        f.Global->clock = FrameTimer.FromSeconds(f, 10);
    }
    
    public override void Update(Frame f)
    {
        // Check if postgame timer has expired
        if (!f.Global->clock.IsRunning(f))
        {
            // Return to lobby
            GameStateSystem.SetState(f, GameState.Lobby);
        }
    }
}
```

## Best Practices

1. **Square Scaling**: Scale reconnection points quadratically with trail length to reward skilled play
2. **Visual Feedback**: Provide clear visual and audio feedback for scoring events
3. **Skill Requirement**: Use alignment checks to ensure reconnection requires skill
4. **Minimum Thresholds**: Require a minimum trail length for reconnection to prevent abuse
5. **Balanced Values**: Balance point values between different scoring methods
6. **Event Communication**: Use events to communicate score changes to the Unity view
7. **State Tracking**: Store scores in the global state for persistence
8. **Verification**: Verify player ownership before awarding points
9. **Animation Timing**: Use delays to ensure scoring animations can complete
