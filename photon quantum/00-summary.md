# Photon Quantum Documentation Summary

This collection of notes provides a comprehensive reference for Photon Quantum, a high-performance deterministic multiplayer framework for Unity. These documents focus on code accuracy and practical usage of the Quantum ECS framework.

## Core Concepts

1. [**Quantum Introduction**](01-quantum-intro.md)
   - Overview of Photon Quantum's architecture
   - Predict/rollback networking explanation
   - ECS (Entity Component System) architecture
   - Quantum and Unity integration

2. [**Domain-Specific Language (DSL)**](02-quantum-dsl.md)
   - Core syntax for defining game state
   - Components, structs, and data types
   - Collection types (lists, dictionaries, hashsets)
   - DSL special types (entity_ref, player_ref, etc.)

3. [**Entity Prototypes**](03-entity-prototypes.md)
   - Data-driven entity composition
   - Creating and configuring prototypes in Unity
   - Runtime instantiation from prototypes
   - EntityView system

## Communication and Input

4. [**Input System**](04-input.md)
   - Defining and polling input in DSL
   - Optimizing input bandwidth
   - Input vs. Commands
   - Button state handling

5. [**Commands**](05-commands.md)
   - Occasional action transmission
   - Command definition and serialization
   - Compound commands
   - Command setup and registration

6. [**Events**](06-events.md)
   - Frame events for simulation-to-view communication
   - Event subscription in Unity
   - Special keywords (synced, nothashed, local/remote)
   - Extending events

## ECS Implementation

7. [**Systems**](07-systems.md)
   - SystemMainThread, SystemMainThreadFilter, SystemSignalsOnly
   - System lifecycle and control
   - Entity creation and management API
   - Stateless requirements and determinism

8. [**Components**](08-components.md)
   - Component definition and usage
   - Safe and unsafe API
   - Singleton components
   - Filters and component iterators

## How to Use These Notes

- Start with the [Introduction](01-quantum-intro.md) for a high-level overview
- Review the [DSL](02-quantum-dsl.md) document to understand how to define game state
- Explore [Entity Prototypes](03-entity-prototypes.md) for the data-driven approach to entity creation
- Dig into the communication patterns ([Input](04-input.md), [Commands](05-commands.md), [Events](06-events.md))
- Study the ECS implementation details ([Systems](07-systems.md), [Components](08-components.md))

Each document contains detailed code examples that can be directly applied to your Quantum projects. The focus is on providing clear, accurate code snippets that demonstrate best practices for working with the Quantum framework.

## Sample Project Documentation

For an in-depth look at a complete Quantum game implementation, check out the [**Quantum Platform Shooter 2D**](../quantum%20platform%20shooter/00-project-overview.md) documentation. This sample project demonstrates:

- A complete multiplayer game built with Quantum
- Character movement and combat systems
- Weapons and skills implementation
- Unity-Quantum integration
- Input handling across platforms

The Platform Shooter documentation includes:
1. [Project Overview](../quantum%20platform%20shooter/00-project-overview.md)
2. [Game State Definition](../quantum%20platform%20shooter/01-game-state-definition.md)
3. [Character System](../quantum%20platform%20shooter/02-character-system.md)
4. [Movement System](../quantum%20platform%20shooter/03-movement-system.md)
5. [Weapons and Combat](../quantum%20platform%20shooter/04-weapons-and-combat.md)
6. [Skills System](../quantum%20platform%20shooter/05-skills-system.md)
7. [Unity Integration](../quantum%20platform%20shooter/06-unity-integration.md)
8. [Input Handling](../quantum%20platform%20shooter/07-input-handling.md)

These detailed breakdowns provide practical examples of how to implement Quantum's core concepts in a real game.

## Additional Resources

- [Asteroids Tutorial](https://doc.photonengine.com/quantum/current/tutorials/asteroids/1-overview)
- [Complete Course to Quantum 3](https://doc.photonengine.com/quantum/current/tutorials/video-tutorial)
- [Game Samples](https://doc.photonengine.com/quantum/current/game-samples/platform-shooter-2d/overview)

These notes are designed to be used as a reference while developing with Photon Quantum. They focus on the code aspects to help with accurate implementation rather than theoretical explanations.
