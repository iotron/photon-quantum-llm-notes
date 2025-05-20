# Quantum Karts Bot Implementation - Overview

## Introduction

This document provides an overview of the bot (AI) implementation in the Quantum Karts game. The Quantum Karts game uses Photon Quantum for its multiplayer netcode and deterministic physics simulation. The bots are implemented using a deterministic approach that allows them to seamlessly participate in multiplayer races with human players.

## Key Components

The AI system in Quantum Karts consists of the following key components:

1. **AIDriver** - The main component attached to AI-controlled karts that handles decision making and inputs
2. **AIDriverSettings** - Asset that defines AI behavior parameters and customization
3. **KartSystem** - System that handles gameplay logic for both AI and player-controlled karts
4. **RaceSystem** - System that manages race progression, checkpoints, and positioning

## AI Architecture

The AI architecture in Quantum Karts follows a relatively simple but effective design:

1. **Waypoint Following** - AI drivers follow a predefined path of checkpoints on the track
2. **Predictive Steering** - The AI looks ahead to future waypoints to smooth out its driving
3. **Drift Management** - AI decides when to drift based on turn angles
4. **Weapon Usage** - AI can use powerups/weapons based on game conditions
5. **Recovery Logic** - AI can detect when it's stuck and trigger a respawn

## Signal & Events

The Quantum Karts game uses a signal and event system for communication between different parts of the code:

- **ISignalOnPlayerConnected/Disconnected** - Handles player connections
- **ISignalRaceStateChanged** - Responds to race state changes (waiting, countdown, racing)
- **ISignalPlayerFinished** - Handles when a player/bot finishes the race

## AI Spawning Mechanisms

The game includes multiple methods for spawning AI drivers:

1. **Default AI Count** - Spawns a configured number of AI drivers when the race is in waiting state
2. **Fill with AI** - Automatically fills empty slots with AI drivers up to a configured driver count
3. **Player Replacement** - Replaces disconnected players with AI to maintain race integrity

In the following documents, we'll dive deeper into each aspect of the AI implementation.
