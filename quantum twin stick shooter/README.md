# Quantum Twin Stick Shooter Documentation

This repository contains comprehensive documentation for the Quantum Twin Stick Shooter 3.0.2 sample project. The documentation is designed to help you understand how to implement multiplayer games using Photon Quantum's deterministic networking framework.

## Overview

Quantum Twin Stick Shooter is a sample game built with Photon Quantum 3.0.2 that demonstrates a multiplayer top-down twin stick shooter with team-based gameplay. It showcases key features of Quantum, including:

- Deterministic ECS (Entity Component System) architecture
- Predict/rollback networking
- Bot SDK integration with advanced AI systems
- Data-driven skills and attributes
- Team-based gameplay with Coin Grab game mode
- Unity integration for visualization

The documentation in this repository explains in detail how these systems are implemented, with code examples and best practices.

## Technical Information

- **Unity Version**: 2021.3.30f1
- **Quantum Version**: 3.0.2 (Build 620)
- **Platforms**: PC (Windows/Mac), and Mobile (Android)

## Documentation Structure

1. [**Project Overview**](00-project-overview.md) - High-level overview of the Quantum Twin Stick Shooter
2. [**Input System**](01-input-system.md) - How player and AI input is handled 
3. [**Movement System**](02-movement-system.md) - Character movement and KCC integration
4. [**AI System**](03-ai-system.md) - Bot SDK implementation with HFSM and context steering
5. [**Skills System**](04-skills-system.md) - Character abilities and combat mechanics
6. [**Attributes System**](05-attributes-system.md) - Character stats and modifiers
7. [**Game Management System**](06-game-management-system.md) - Game flow and match management
8. [**Inventory System**](07-inventory-system.md) - Item collection and management
9. [**Unity Integration**](08-unity-integration.md) - Visualization and input collection

Each document is structured to provide clear explanations and accurate code examples that can be used as reference when implementing similar systems.

## Key Features

### AI Implementation
- **Bot SDK**: Comprehensive use of Quantum's Bot SDK
- **HFSM**: Hierarchical Finite State Machine for AI decision making
- **AI Director**: Team-level coordination of AI characters
- **Data-Driven Sensors**: Configurable perception systems for AI
- **Context Steering**: Multiple weighted vectors for movement decisions
- **AI Memory**: Time-based information storage and recall
- **Bot Replacement**: Automatic replacement of disconnected players with bots

### Game Systems
- **Skill System**: Data-driven abilities with customizable behavior
- **Attributes System**: Flexible stat management with modifiers
- **Team-Based Gameplay**: Coin collection with scoring system
- **Game Flow Management**: HFSM-based game state control
- **Unified Input**: Same input structure used for both players and bots
- **KCC Integration**: Top-down character controller

## Game Highlights

- **Coin Grab Game Mode**: Collect coins scattered around the map. The team that keeps 10+ coins for 15 seconds wins.
- **Three Unique Characters**: Each with two unique abilities
- **Team-Based Gameplay**: Coordinate with teammates to collect and protect coins
- **Tactical AI Behaviors**: Bots make intelligent decisions based on game state
- **Cross-Platform Support**: Works on PC and mobile devices

## How to Use This Documentation

- **For learning Quantum**: Start with the Project Overview, then read through the documents in order to understand the fundamental concepts of Quantum.
- **For implementing specific features**: Go directly to the relevant system document.
- **For reference**: Use the code examples as templates for your own implementation.

The code examples are extracted directly from the Quantum Twin Stick Shooter sample project and represent actual working implementations of the various systems.

## LLM Optimization Note

These notes have been specifically crafted for optimal use by Large Language Models. The documentation:

- Uses precise code examples with accurate syntax
- Provides contextual explanations of code functionality
- Follows consistent formatting and structure
- Includes best practices and implementation patterns
- Provides clear descriptions of interfaces between systems

This makes the documentation ideal for generating accurate code when queried about Quantum implementation patterns.

## Additional Resources

For more information about Photon Quantum:

- [Quantum Documentation](https://doc.photonengine.com/quantum/current/getting-started/quantum-intro)
- [Photon Quantum Discord](https://discord.gg/photonengine)
- [Quantum Forum](https://forum.photonengine.com/categories/quantum-showcase-discussion)
- [Download Quantum Samples](https://dashboard.photonengine.com/download/quantum)