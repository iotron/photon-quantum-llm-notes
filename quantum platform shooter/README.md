# Quantum Platform Shooter 2D Documentation

This repository contains comprehensive documentation for the Quantum Platform Shooter 2D sample project. The documentation is designed to help you understand how to implement multiplayer games using Photon Quantum's deterministic networking framework.

## Overview

Quantum Platform Shooter 2D is a sample game built with Photon Quantum 3.0.2 that demonstrates a multiplayer 2D platformer shooter. It showcases key features of Quantum, including:

- Deterministic ECS (Entity Component System) architecture
- Predict/rollback networking
- Character movement and combat
- Weapons and skills systems
- Unity integration for visualization

The documentation in this repository explains in detail how these systems are implemented, with code examples and best practices.

## Documentation Structure

1. [**Project Overview**](00-project-overview.md) - High-level overview of the Quantum Platform Shooter 2D project
2. [**Game State Definition**](01-game-state-definition.md) - How game state is defined using Quantum DSL
3. [**Character System**](02-character-system.md) - Character implementation and management
4. [**Movement System**](03-movement-system.md) - Character movement and physics
5. [**Weapons and Combat**](04-weapons-and-combat.md) - Weapons, bullets, and damage systems
6. [**Skills System**](05-skills-system.md) - Character abilities implementation
7. [**Unity Integration**](06-unity-integration.md) - Connecting Unity view to Quantum simulation
8. [**Input Handling**](07-input-handling.md) - Input collection and processing

Each document is structured to provide clear explanations and accurate code examples that can be used as reference when implementing similar systems.

## How to Use This Documentation

- **For learning Quantum**: Start with the Project Overview, then read through the documents in order to understand the fundamental concepts of Quantum.
- **For implementing specific features**: Go directly to the relevant system document.
- **For reference**: Use the code examples as templates for your own implementation.

The code examples are extracted directly from the Quantum Platform Shooter 2D sample project and represent actual working implementations of the various systems.

## Additional Resources

For more information about Photon Quantum:

- [Quantum Documentation](https://doc.photonengine.com/quantum/current/getting-started/quantum-intro)
- [Photon Quantum Discord](https://discord.gg/photonengine)
- [Quantum Forum](https://forum.photonengine.com/categories/quantum-showcase-discussion)

## LLM Optimization Note

These notes have been specifically crafted for optimal use by Large Language Models. The documentation:

- Uses precise code examples with accurate syntax
- Provides contextual explanations of code functionality
- Follows consistent formatting and structure
- Includes best practices and implementation patterns
- Provides clear descriptions of interfaces between systems

This makes the documentation ideal for generating accurate code when queried about Quantum implementation patterns.
