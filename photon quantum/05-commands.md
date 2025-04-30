# Quantum Commands

## Introduction

Quantum Commands provide an alternative to sending data to the Quantum simulation beyond using regular Inputs. Key differences:

- Unlike Inputs, Commands are **not** required to be sent every tick
- Can be triggered in specific situations only when needed
- Fully reliable - the server will always accept and confirm them
- Locally executed immediately in predicted frames
- For remote clients, there's a delay until the Command is received (cannot predict the tick in which the command will be received)

Commands are implemented as C# classes that inherit from `Photon.Deterministic.DeterministicCommand`. They can contain any serializable data.

```csharp
namespace Quantum
{
  using Photon.Deterministic;

  public class CommandSpawnEnemy : DeterministicCommand
  {
    public AssetRefEntityPrototype EnemyPrototype;

    public override void Serialize(BitStream stream)
    {
      stream.Serialize(ref EnemyPrototype);
    }

    public void Execute(Frame frame)
    {
      frame.Create(EnemyPrototype);
    }
  }
}
```

## Commands Setup in the Simulation

After defining Command classes, they need to be registered in the `DeterministicCommandSetup`'s factories:

1. Navigate to `Assets/QuantumUser/Simulation`
2. Open the script `CommandSetup.User.cs`
3. Add desired commands to the factory:

```csharp
// CommandSetup.User.cs

namespace Quantum {
  using System.Collections.Generic;
  using Photon.Deterministic;

  public static partial class DeterministicCommandSetup {
    static partial void AddCommandFactoriesUser(ICollection<IDeterministicCommandFactory> factories, RuntimeConfig gameConfig, SimulationConfig simulationConfig) {
      // user commands go here
      // new instances will be created when a FooCommand is received (de-serialized)
      factories.Add(new FooCommand());

      // BazCommand instances will be acquired from/disposed back to a pool automatically
      factories.Add(new DeterministicCommandPool<BazCommand>());
    }
  }
}
```

## Sending Commands From The View

Commands can be sent from anywhere inside Unity:

```csharp
namespace Quantum
{
  using UnityEngine;

  public class EnemySpawnerUI : MonoBehaviour
  {
    [SerializeField] private AssetRefEntityPrototype _enemyPrototype;

    public void SpawnEnemy()
    {
      CommandSpawnEnemy command = new CommandSpawnEnemy()
      {
        EnemyPrototype = _enemyPrototype,
      };
      QuantumRunner.Default.Game.SendCommand(command);
    }
  }
}
```

### SendCommand Overloads

The `SendCommand()` method has two overloads:

```csharp
void SendCommand(DeterministicCommand command);
void SendCommand(Int32 player, DeterministicCommand command);
```

Specify the player index (PlayerRef) if multiple players are controlled from the same machine. Games with only one local player can ignore the player index field.

## Polling Commands From The Simulation

To receive and handle Commands inside the simulation, poll the frame for a specific player:

```csharp
using Photon.Deterministic;
namespace Quantum
{
    public class PlayerCommandsSystem : SystemMainThread
    {
        public override void Update(Frame frame)
        {
            for (int i = 0; i < f.PlayerCount; i++)
            {
                 var command = frame.GetPlayerCommand(i) as CommandSpawnEnemy;
                 command?.Execute(frame);
            }
        }
    }
}
```

### Implementation Note

The API doesn't enforce or implement a specific callback mechanism or design pattern for Commands. Developers must choose how to consume, interpret, and execute Commands, such as:
- Encoding them into signals
- Using a Chain of Responsibility
- Implementing command execution as a method within the command class

## Examples for Collections

### Serializing Lists

```csharp
namespace Quantum
{
    using System.Collections.Generic;
    using Photon.Deterministic;
    
    public class ExampleCommand : DeterministicCommand
    {
        public List<EntityRef> Entities = new List<EntityRef>();
        
        public override void Serialize(BitStream stream)
        {
            var count = Entities.Count;
            stream.Serialize(ref count);
            if (stream.Writing)
            {
                foreach (var e in Entities)
                {
                    var copy = e;
                    stream.Serialize(ref copy.Index);
                    stream.Serialize(ref copy.Version);
                }
            }
            else
            {
                for (int i = 0; i < count; i++)
                {
                    EntityRef readEntity = default;
                    stream.Serialize(ref readEntity.Index);
                    stream.Serialize(ref readEntity.Version);
                    Entities.Add(readEntity);
                }   
            }
        }
    }
}
```

### Serializing Arrays

Using manual size tracking:

```csharp
namespace Quantum
{
    using Photon.Deterministic;
    
    public class ExampleCommand : DeterministicCommand
    {
        public EntityRef[] Entities = new EntityRef[10];
        public int EntitiesCount;
        
        public override void Serialize(BitStream stream)
        {
            stream.Serialize(ref EntitiesCount);
            for (int i = 0; i < EntitiesCount; i++)
            {
                stream.Serialize(ref Entities[i].Index);
                stream.Serialize(ref Entities[i].Version);
            }
        }
    }
}
```

Using `SerializeArrayLength` helper:

```csharp
namespace Quantum
{
    using Photon.Deterministic;
    
    public class ExampleCommand : DeterministicCommand
    {
        public EntityRef[] Entities;
        
        public override void Serialize(BitStream stream)
        {
            stream.SerializeArrayLength(ref Entities);
            for (int i = 0; i < Entities.Length; i++)
            {
                EntityRef e = Entities[i];
                stream.Serialize(ref e.Index);
                stream.Serialize(ref e.Version);
                Entities[i] = e;
            }
        }
    }
}
```

## Compound Commands

Only one command can be attached to an input stream per tick. Even if a client sends multiple Deterministic Commands in one tick, they will arrive separately on consecutive ticks. 

To overcome this limitation, you can use `CompoundCommand`, which is provided by the SDK and allows packing multiple Deterministic Commands into a single command:

### Instantiating and Sending Compound Commands

```csharp
var compound = new Quantum.Core.CompoundCommand();
compound.Commands.Add(new FooCommand());
compound.Commands.Add(new BazCommand());

QuantumRunner.Default.Game.SendCommand(compound);
```

### Intercepting and Processing Compound Commands

```csharp
public override void Update(Frame frame) {
  for (var i = 0; i < frame.PlayerCount; i++) {
      var compoundCommand = frame.GetPlayerCommand(i) as CompoundCommand;
      if (compoundCommand != null) {
        foreach (var cmd in compoundCommand.Commands) {
          // execute individual commands logic
        }
      }
  }
}
```

## Best Practices

1. **Use Commands for Occasional Actions**: Reserve commands for actions that don't need to be polled every frame.

2. **Keep Serialization Efficient**: Optimize serialization code to minimize bandwidth usage.

3. **Pool Commands**: For frequently used commands, consider using `DeterministicCommandPool` to reduce memory allocations.

4. **Use Compound Commands**: When multiple related actions need to happen at the same tick, pack them into a compound command.

5. **Consider Local Prediction**: Remember that commands are executed immediately in local predicted frames but have a delay on remote clients.

6. **Verify Validity**: Always verify command data before executing to prevent cheating or exploitation.

7. **Separate Command Logic**: Keep the command execution logic separate from the command definition for better maintainability.
