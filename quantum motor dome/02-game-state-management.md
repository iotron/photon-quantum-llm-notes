# Quantum Motor Dome Game State Management

This document explains the state management system in Quantum Motor Dome, covering how the game transitions between different states and how systems are activated/deactivated accordingly.

## Game State Definition

The game state is defined as an enum in the Quantum DSL:

```qtn
enum GameState
{
	Off = 0,
	Lobby,
	Pregame,
	Intro,
	Countdown,
	Game,
	Outro,
	Postgame
}
```

These states represent the different phases of gameplay:

- **Off**: Initial state before game starts
- **Lobby**: Players are joining and waiting
- **Pregame**: Preparing for the game to start
- **Intro**: Playing introduction sequence
- **Countdown**: Counting down to start the game
- **Game**: Main gameplay phase
- **Outro**: End of game sequence
- **Postgame**: Showing results before returning to lobby

## Global State Variables

The global state variables keep track of the current game state:

```qtn
global
{
	FrameTimer clock;
	dictionary<Int32, PlayerData> playerData;
	
	FrameTimer StateTimer;
    GameState DelayedState;
    
    GameState CurrentState;
    GameState PreviousState;
}
```

Key variables:
- `CurrentState`: The active game state
- `PreviousState`: The previous game state (for transition events)
- `StateTimer`: Timer for delayed state transitions
- `DelayedState`: The state to transition to when the timer expires

## System Interfaces

Systems can implement game state interfaces to specify which states they should be active in:

```csharp
public interface IGameState { }
public interface IGameState_Lobby : IGameState { }
public interface IGameState_Pregame : IGameState { }
public interface IGameState_Intro : IGameState { }
public interface IGameState_Countdown : IGameState { }
public interface IGameState_Game : IGameState { }
public interface IGameState_Outro : IGameState { }
public interface IGameState_Postgame : IGameState { }
```

Example implementation:

```csharp
// This system is only active during the Game state
public unsafe class ShipMovementSystem : SystemMainThreadFilter<ShipFilter>, IGameState_Game
{
    public override bool StartEnabled => false;
    
    // System implementation...
}

// This system is active during both Game and Countdown states
public unsafe class PickupSystem<P> : SystemSignalsOnly, ISignalOnTriggerEnter3D, IGameState_Game, IGameState_Countdown
{
    public override bool StartEnabled => false;
    
    // System implementation...
}
```

## GameStateSystem

The `GameStateSystem` is the central component that manages state transitions and system activation:

```csharp
unsafe class GameStateSystem : SystemMainThread
{
    static readonly ReadOnlyDictionary<GameState, Type> stateTable =
        new(new Dictionary<GameState, Type>()
        {
            { GameState.Lobby, typeof(IGameState_Lobby) },
            { GameState.Pregame, typeof(IGameState_Pregame) },
            { GameState.Intro, typeof(IGameState_Intro) },
            { GameState.Countdown, typeof(IGameState_Countdown) },
            { GameState.Game, typeof(IGameState_Game) },
            { GameState.Outro, typeof(IGameState_Outro) },
            { GameState.Postgame, typeof(IGameState_Postgame) }
        });

    public override void OnInit(Frame f)
    {
        // immediately start the game
        f.Global->StateTimer = FrameTimer.FromSeconds(f, 0);
        
        f.Global->DelayedState = 0;
        f.Global->PreviousState = 0;
        SetState(f, GameState.Lobby);
    }

    public override void Update(Frame f)
    {
        var timer = f.Global->StateTimer;
        bool didStateTimerExpireThisFrame = timer.IsRunning(f) == false && timer.TargetFrame == f.Number;
        if (didStateTimerExpireThisFrame)
        {
            f.Global->StateTimer = FrameTimer.None;
            SetState(f, f.Global->DelayedState);
            f.Global->DelayedState = 0;
        }

        if (f.Global->CurrentState != f.Global->PreviousState)
        {
            if (stateTable.TryGetValue(f.Global->CurrentState, out Type t))
            {
                // Disable systems that should not be active in the current state
                foreach (SystemBase sys in f.SystemsAll
                    .Where(s => s.GetType().GetInterfaces().Contains(typeof(IGameState)) && !s.GetType().GetInterfaces().Contains(t)))
                {
                    f.SystemDisable(sys.GetType());
                }

                // Enable systems that should be active in the current state
                foreach (SystemBase sys in f.SystemsAll
                    .Where(s => s.GetType().GetInterfaces().Contains(typeof(IGameState)) && s.GetType().GetInterfaces().Contains(t)))
                {
                    if (!f.SystemIsEnabledSelf(sys.GetType()))
                        f.SystemEnable(sys.GetType());
                }
            }

            // Fire event for state change
            f.Events.GameStateChanged(f.Global->CurrentState, f.Global->PreviousState);
            f.Global->PreviousState = f.Global->CurrentState;
        }
    }

    public static void SetStateDelayed(Frame f, GameState state, FP delay)
    {
        f.Global->DelayedState = state;
        f.Global->StateTimer = FrameTimer.FromSeconds(f, delay);
    }

    public static void SetState(Frame f, GameState state)
    {
        f.Global->CurrentState = state;
    }
}
```

This system has three main functions:
1. **Immediate state transitions** through `SetState()`
2. **Delayed state transitions** through `SetStateDelayed()`
3. **System activation/deactivation** based on the current state

## State-Specific Systems

Various systems in the game implement state interfaces to be activated only during specific game states:

### Lobby State Systems

```csharp
public unsafe class LobbySystem : SystemMainThread, IGameState_Lobby
{
    public override bool StartEnabled => false;

    public override void Update(Frame f)
    {
        // Check if all players are ready
        bool allReady = true;
        foreach (var key in f.Global->playerData.Resolve(f, out var dict).Keys)
        {
            var pd = dict[key];
            if (!pd.ready)
            {
                allReady = false;
                break;
            }
        }

        // If all players are ready, transition to Pregame
        if (allReady && f.Global->playerData.Resolve(f, out _).Count > 0)
        {
            GameStateSystem.SetState(f, GameState.Pregame);
        }
    }
}
```

### Pregame State Systems

```csharp
public unsafe class PregameSystem : SystemMainThread, IGameState_Pregame
{
    public override bool StartEnabled => false;

    public override void OnEnabled(Frame f)
    {
        // Spawn map entities
        // Implementation details...
        
        // Transition to Intro after setup
        GameStateSystem.SetState(f, GameState.Intro);
    }
}
```

### Intro State Systems

```csharp
public unsafe class IntroSystem : SystemMainThread, IGameState_Intro
{
    public override bool StartEnabled => false;

    public override void OnEnabled(Frame f)
    {
        // Reset player data
        f.Global->playerData.Resolve(f, out var dict).Clear();
        foreach (var (entity, link) in f.Unsafe.GetComponentBlockIterator<PlayerLink>())
        {
            dict.Add(link.Player, new PlayerData());
        }
        
        // Wait for player input to continue
        // Implementation details...
    }
    
    // Process intro finished command
    public void IntroFinished(Frame f, IntroFinishedCommand cmd)
    {
        GameStateSystem.SetState(f, GameState.Countdown);
    }
}
```

### Countdown State Systems

```csharp
public unsafe class CountdownSystem : SystemMainThread, IGameState_Countdown
{
    public override bool StartEnabled => false;
    FP countdownTime = 3;
    
    public override void OnEnabled(Frame f)
    {
        // Start countdown timer
        f.Global->clock = FrameTimer.FromSeconds(f, countdownTime);
    }

    public override void Update(Frame f)
    {
        // Check if countdown has finished
        if (!f.Global->clock.IsRunning(f))
        {
            GameStateSystem.SetState(f, GameState.Game);
        }
    }
}
```

### Game State Systems

```csharp
public unsafe class GameClockSystem : SystemMainThread, IGameState_Game
{
    public override bool StartEnabled => false;
    FP gameTime = 180; // 3 minutes
    
    public override void OnEnabled(Frame f)
    {
        // Start game timer
        f.Global->clock = FrameTimer.FromSeconds(f, gameTime);
    }

    public override void Update(Frame f)
    {
        // Check if game time has expired
        if (!f.Global->clock.IsRunning(f))
        {
            GameStateSystem.SetState(f, GameState.Outro);
        }
    }
}
```

### Outro State Systems

```csharp
public unsafe class OutroSystem : SystemMainThread, IGameState_Outro
{
    public override bool StartEnabled => false;
    FP outroTime = 5;
    
    public override void OnEnabled(Frame f)
    {
        // Start outro timer
        f.Global->clock = FrameTimer.FromSeconds(f, outroTime);
    }

    public override void Update(Frame f)
    {
        // Check if outro has finished
        if (!f.Global->clock.IsRunning(f))
        {
            GameStateSystem.SetState(f, GameState.Postgame);
        }
    }
}
```

### Postgame State Systems

```csharp
public unsafe class PostgameSystem : SystemMainThread, IGameState_Postgame
{
    public override bool StartEnabled => false;
    FP postgameTime = 10;
    
    public override void OnEnabled(Frame f)
    {
        // Calculate final scores
        // Implementation details...
        
        // Start postgame timer
        f.Global->clock = FrameTimer.FromSeconds(f, postgameTime);
    }

    public override void Update(Frame f)
    {
        // Check if postgame has finished
        if (!f.Global->clock.IsRunning(f))
        {
            // Return to lobby
            GameStateSystem.SetState(f, GameState.Lobby);
        }
    }
}
```

## Delayed State Transitions

The system supports delayed state transitions using `FrameTimer`:

```csharp
// Transition to Postgame after 5 seconds
GameStateSystem.SetStateDelayed(f, GameState.Postgame, 5);
```

Implementation in GameStateSystem:

```csharp
public static void SetStateDelayed(Frame f, GameState state, FP delay)
{
    f.Global->DelayedState = state;
    f.Global->StateTimer = FrameTimer.FromSeconds(f, delay);
}
```

## Game State Events

State changes trigger events to synchronize with the Unity view:

```qtn
synced event GameStateChanged{ GameState NewState; GameState OldState; }
```

These events are subscribed to in Unity:

```csharp
public class GameStateBridge : MonoBehaviour
{
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventGameStateChanged>(this, OnGameStateChanged);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventGameStateChanged>(this);
    }
    
    private void OnGameStateChanged(EventGameStateChanged evt)
    {
        switch (evt.NewState)
        {
            case GameState.Lobby:
                UIScreen.Focus(InterfaceManager.Instance.lobbyScreen);
                break;
            case GameState.Pregame:
                // Implementation details...
                break;
            case GameState.Intro:
                // Play intro sequence
                break;
            case GameState.Countdown:
                UIScreen.Focus(InterfaceManager.Instance.countdownScreen);
                break;
            case GameState.Game:
                UIScreen.Focus(InterfaceManager.Instance.hudScreen);
                break;
            case GameState.Outro:
                // Play outro sequence
                break;
            case GameState.Postgame:
                UIScreen.Focus(InterfaceManager.Instance.resultsScreen);
                break;
        }
    }
}
```

## Integration with Player State

Player states can also affect game state:

```csharp
// In LobbySystem
public override void Update(Frame f)
{
    // Check if all players are ready
    bool allReady = true;
    foreach (var key in f.Global->playerData.Resolve(f, out var dict).Keys)
    {
        var pd = dict[key];
        if (!pd.ready)
        {
            allReady = false;
            break;
        }
    }

    // If all players are ready, transition to Pregame
    if (allReady && f.Global->playerData.Resolve(f, out _).Count > 0)
    {
        GameStateSystem.SetState(f, GameState.Pregame);
    }
}
```

## Best Practices

1. **Interface-Based Activation**: Use interfaces to specify when systems should be active
2. **Clear State Transitions**: Create clear paths between states
3. **Event-Based Synchronization**: Use events to keep Unity view in sync with game state
4. **Timer-Based Progression**: Use timers for automated state progression
5. **Centralized State Management**: Use a single system for all state transitions
6. **Declarative System Design**: Systems declare which states they belong to
7. **Delayed State Transitions**: Support both immediate and delayed transitions
