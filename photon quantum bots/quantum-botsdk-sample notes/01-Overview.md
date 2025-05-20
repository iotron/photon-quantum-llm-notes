# Photon Quantum Bot SDK - Overview

This document provides an overview of the Photon Quantum Bot SDK's structure and key components based on the quantum-botsdk-sample-development-3.0.0 project.

## Architecture Overview

The Quantum Bot SDK is designed to work with the Photon Quantum networking framework to provide deterministic AI agents (bots) in multiplayer games. The SDK supports three main AI paradigms:

1. **Behavior Trees (BT)** - A hierarchical structure of nodes that define behavior
2. **Hierarchical Finite State Machines (HFSM)** - A state machine with nested states
3. **Utility Theory (UT)** - Decision making based on scoring various options

## Key Components

The Bot SDK consists of several core components:

- **AI Agents**: Entities that run the AI behaviors (BTAgent, HFSMAgent, UTAgent)
- **AI Blackboards**: Data structures that store information shared between AI components
- **AI Actions**: Executable behaviors that agents can perform
- **AI Functions**: Methods that compute values or make decisions
- **Systems**: Core BotSDK systems that manage the lifecycle of AI agents

## Project Structure

The Bot SDK sample is organized as follows:

- **Assets/Photon/QuantumAddons/QuantumBotSDK/**
  - **Assemblies**: Core SDK assemblies
  - **Runtime**: Unity-facing components and prototypes
  - **Simulation**: Core simulation-level AI functionality
  - **Editor**: Editor extensions for the Bot SDK
  - **Debugger**: Tools for debugging AI behavior

- **Assets/QuantumUser/Simulation/Samples/**
  - **CollectorsSample**: Example game with bot implementations
  - **Spellcaster Sample**: Another example with different bot behaviors

## Integration with Quantum

The Bot SDK integrates with the Quantum framework through:
- Component systems for agent lifecycle management
- Deterministic execution to ensure consistent AI behavior across all clients
- Frame-based updates aligned with Quantum's simulation ticks

## Key Design Patterns

1. **Component-based architecture** - AI behaviors are attached to entities as components
2. **Asset-based configuration** - AI behaviors are configured using assets (BTRoot, HFSMRoot, etc.)
3. **Separation of behavior and data** - Actions operate on entity data but don't store state
4. **Extensible system** - Users can create custom nodes, actions, and functions

## Next Steps

Further documents in this series will explore:
- BT implementation
- HFSM implementation
- UT implementation
- Blackboard system
- Creating custom AI actions and functions
- Debugging and profiling
