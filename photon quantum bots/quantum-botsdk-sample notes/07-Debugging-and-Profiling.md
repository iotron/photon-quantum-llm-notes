# Debugging and Profiling Bots

This document details the tools and techniques for debugging and profiling AI bots in the Photon Quantum Bot SDK.

## Debug System Overview

The Bot SDK includes a comprehensive debugging system that allows developers to visualize and inspect AI behavior at runtime. The debugging system consists of several components:

1. **BotSDKDebuggerSystem** - Core system for collecting debug information
2. **Unity-side Debugger Window** - Editor window for viewing debug data
3. **Runtime Visualization** - Gizmos and on-screen information

## BotSDKDebuggerSystem

### Core Concept

The `BotSDKDebuggerSystem` collects and tracks debug information about AI agents during simulation. It works by capturing state changes, decisions, and other relevant data that can be displayed in the Unity editor.

### Implementation

```csharp
public unsafe class BotSDKDebuggerSystem : SystemMainThreadFilter
{
    // Collection of debug entries
    private Dictionary<EntityRef, AIDebugData> _debugEntries = new Dictionary<EntityRef, AIDebugData>();
    
    // Configuration
    public bool CollectDebugData = true;
    
    public override void Update(Frame frame)
    {
        if (!CollectDebugData)
            return;
            
        // Process BT agents
        var btAgents = frame.GetComponentIterator<BTAgent>();
        foreach (var (entity, agent) in btAgents)
        {
            UpdateBTDebugData(frame, entity, agent);
        }
        
        // Process HFSM agents
        var hfsmAgents = frame.GetComponentIterator<HFSMAgent>();
        foreach (var (entity, agent) in hfsmAgents)
        {
            UpdateHFSMDebugData(frame, entity, agent);
        }
        
        // Process UT agents
        var utAgents = frame.GetComponentIterator<UTAgent>();
        foreach (var (entity, agent) in utAgents)
        {
            UpdateUTDebugData(frame, entity, agent);
        }
        
        // Clean up old entries
        CleanUpOldEntries();
    }
    
    // Helper methods for updating debug data for each agent type
    private void UpdateBTDebugData(Frame frame, EntityRef entity, BTAgent agent) { /* ... */ }
    private void UpdateHFSMDebugData(Frame frame, EntityRef entity, HFSMAgent agent) { /* ... */ }
    private void UpdateUTDebugData(Frame frame, EntityRef entity, UTAgent agent) { /* ... */ }
    
    // Get debug data for a specific entity
    public AIDebugData GetDebugData(EntityRef entity)
    {
        if (_debugEntries.TryGetValue(entity, out var data))
            return data;
        return null;
    }
}
```

## Unity Debugger Window

### Core Concept

The Unity debugger window provides a visual interface for inspecting AI behavior. It displays:

1. Active agents in the scene
2. Current states and behaviors
3. Decision trees and transitions
4. Performance metrics
5. Blackboard values

### Implementation

The debugger window is implemented as a custom Unity editor window:

```csharp
public class BotSDKDebuggerWindow : EditorWindow
{
    // Selected entity for debugging
    private EntityRef _selectedEntity;
    
    // View mode (BT, HFSM, UT)
    private AIDebugViewMode _viewMode;
    
    // Scroll position
    private Vector2 _scrollPosition;
    
    // Show window
    [MenuItem("Quantum/Bot SDK/Debugger")]
    public static void ShowWindow()
    {
        GetWindow<BotSDKDebuggerWindow>("Bot SDK Debugger");
    }
    
    // Draw the window
    private void OnGUI()
    {
        DrawToolbar();
        
        _scrollPosition = EditorGUILayout.BeginScrollView(_scrollPosition);
        
        if (Application.isPlaying && QuantumRunner.Default != null)
        {
            DrawAgentList();
            
            if (_selectedEntity != default)
            {
                DrawEntityDebugInfo();
            }
        }
        else
        {
            EditorGUILayout.HelpBox("Game must be running to use the debugger.", MessageType.Info);
        }
        
        EditorGUILayout.EndScrollView();
    }
    
    // Draw toolbar with options
    private void DrawToolbar() { /* ... */ }
    
    // Draw list of active agents
    private void DrawAgentList() { /* ... */ }
    
    // Draw debug info for the selected entity
    private void DrawEntityDebugInfo()
    {
        var debuggerSystem = QuantumRunner.Default.Game.Frames.Verified.GetOrCreateSystem<BotSDKDebuggerSystem>();
        var debugData = debuggerSystem.GetDebugData(_selectedEntity);
        
        if (debugData == null)
            return;
            
        switch (_viewMode)
        {
            case AIDebugViewMode.BT:
                DrawBTDebugInfo(debugData);
                break;
                
            case AIDebugViewMode.HFSM:
                DrawHFSMDebugInfo(debugData);
                break;
                
            case AIDebugViewMode.UT:
                DrawUTDebugInfo(debugData);
                break;
                
            case AIDebugViewMode.Blackboard:
                DrawBlackboardDebugInfo(debugData);
                break;
        }
    }
    
    // Draw behavior tree debug info
    private void DrawBTDebugInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw HFSM debug info
    private void DrawHFSMDebugInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw utility theory debug info
    private void DrawUTDebugInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw blackboard debug info
    private void DrawBlackboardDebugInfo(AIDebugData debugData) { /* ... */ }
}
```

## Runtime Visualization

### Core Concept

Runtime visualization provides immediate visual feedback in the scene view. This includes:

1. State labels above agents
2. Decision path visualization
3. Target indicators
4. Range visualizations

### Implementation

Runtime visualization is implemented through Gizmos and Debug.DrawLine:

```csharp
public class AIVisualizationBehaviour : MonoBehaviour
{
    // Entity to visualize
    public EntityRef Entity;
    
    // Visualization options
    public bool ShowState = true;
    public bool ShowPath = true;
    public bool ShowTargets = true;
    public bool ShowRanges = true;
    
    // Color configuration
    public Color StateColor = Color.white;
    public Color PathColor = Color.green;
    public Color TargetColor = Color.red;
    public Color RangeColor = Color.yellow;
    
    private void OnDrawGizmos()
    {
        if (!Application.isPlaying || QuantumRunner.Default == null || Entity == default)
            return;
            
        var frame = QuantumRunner.Default.Game.Frames.Verified;
        if (frame == null)
            return;
            
        var debuggerSystem = frame.GetOrCreateSystem<BotSDKDebuggerSystem>();
        var debugData = debuggerSystem.GetDebugData(Entity);
        
        if (debugData == null)
            return;
            
        if (ShowState)
            DrawStateInfo(debugData);
            
        if (ShowPath)
            DrawPathInfo(debugData);
            
        if (ShowTargets)
            DrawTargetInfo(debugData);
            
        if (ShowRanges)
            DrawRangeInfo(debugData);
    }
    
    // Draw state information above the agent
    private void DrawStateInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw path information
    private void DrawPathInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw target information
    private void DrawTargetInfo(AIDebugData debugData) { /* ... */ }
    
    // Draw range information
    private void DrawRangeInfo(AIDebugData debugData) { /* ... */ }
}
```

## Profiling AI Performance

### Core Concept

Profiling helps identify performance bottlenecks in AI code. The Bot SDK includes built-in profiling tools that track:

1. Execution time of AI systems
2. Memory usage
3. Number of active agents
4. Decision evaluations per frame
5. Action executions per frame

### Implementation

```csharp
public class BotSDKProfiler
{
    // Profiling data
    public struct ProfileData
    {
        public long TotalFrameTime;
        public long BTUpdateTime;
        public long HFSMUpdateTime;
        public long UTUpdateTime;
        
        public int ActiveBTAgents;
        public int ActiveHFSMAgents;
        public int ActiveUTAgents;
        
        public int BTNodeEvaluations;
        public int HFSMDecisionEvaluations;
        public int UTScoreCalculations;
        
        public int AIActionExecutions;
        public int AIFunctionExecutions;
    }
    
    // Current frame data
    private ProfileData _currentFrameData;
    
    // Reset profiling data
    public void BeginFrame()
    {
        _currentFrameData = new ProfileData();
    }
    
    // Record system update time
    public void RecordSystemTime(string systemName, long elapsedTicks)
    {
        switch (systemName)
        {
            case "BTSystem":
                _currentFrameData.BTUpdateTime = elapsedTicks;
                break;
                
            case "HFSMSystem":
                _currentFrameData.HFSMUpdateTime = elapsedTicks;
                break;
                
            case "UTSystem":
                _currentFrameData.UTUpdateTime = elapsedTicks;
                break;
        }
    }
    
    // Record counts
    public void RecordAgentCounts(int btAgents, int hfsmAgents, int utAgents)
    {
        _currentFrameData.ActiveBTAgents = btAgents;
        _currentFrameData.ActiveHFSMAgents = hfsmAgents;
        _currentFrameData.ActiveUTAgents = utAgents;
    }
    
    // Record evaluation counts
    public void RecordEvaluationCounts(int btNodes, int hfsmDecisions, int utScores)
    {
        _currentFrameData.BTNodeEvaluations = btNodes;
        _currentFrameData.HFSMDecisionEvaluations = hfsmDecisions;
        _currentFrameData.UTScoreCalculations = utScores;
    }
    
    // Record execution counts
    public void RecordExecutionCounts(int actions, int functions)
    {
        _currentFrameData.AIActionExecutions = actions;
        _currentFrameData.AIFunctionExecutions = functions;
    }
    
    // Get current profile data
    public ProfileData GetCurrentFrameData()
    {
        return _currentFrameData;
    }
}
```

## Debug Logging

### Core Concept

Debug logging provides detailed information about AI behavior for analysis. The Bot SDK includes configurable logging levels:

1. **None** - No logging
2. **Error** - Only errors
3. **Warning** - Errors and warnings
4. **Info** - General information
5. **Verbose** - Detailed information

### Implementation

```csharp
public static class BotSDKLogger
{
    // Log levels
    public enum LogLevel
    {
        None,
        Error,
        Warning,
        Info,
        Verbose
    }
    
    // Current log level
    public static LogLevel CurrentLogLevel = LogLevel.Warning;
    
    // Log methods
    public static void LogError(string message)
    {
        if (CurrentLogLevel >= LogLevel.Error)
            Debug.LogError($"[BotSDK Error] {message}");
    }
    
    public static void LogWarning(string message)
    {
        if (CurrentLogLevel >= LogLevel.Warning)
            Debug.LogWarning($"[BotSDK Warning] {message}");
    }
    
    public static void LogInfo(string message)
    {
        if (CurrentLogLevel >= LogLevel.Info)
            Debug.Log($"[BotSDK Info] {message}");
    }
    
    public static void LogVerbose(string message)
    {
        if (CurrentLogLevel >= LogLevel.Verbose)
            Debug.Log($"[BotSDK Verbose] {message}");
    }
}
```

## Debugging Complex AI Behaviors

### Behavior Tree Debugging

When debugging behavior trees, it's helpful to visualize the active path:

```csharp
private void DrawBTDebugView(BTDebugData debugData)
{
    // Draw the tree structure
    DrawTreeStructure(debugData.RootNode, Vector2.zero, 0);
    
    // Highlight active path
    for (int i = 0; i < debugData.ActivePath.Count; i++)
    {
        Rect nodeRect = GetNodeRect(debugData.ActivePath[i]);
        
        // Highlight node
        EditorGUI.DrawRect(nodeRect, new Color(0, 1, 0, 0.2f));
        
        // Draw line to parent if not root
        if (i > 0)
        {
            Rect parentRect = GetNodeRect(debugData.ActivePath[i - 1]);
            DrawNodeConnection(parentRect, nodeRect, Color.green);
        }
    }
    
    // Show node status
    foreach (var nodeStatus in debugData.NodeStatus)
    {
        Rect nodeRect = GetNodeRect(nodeStatus.Key);
        Color statusColor = GetStatusColor(nodeStatus.Value);
        
        // Draw status indicator
        Rect statusRect = new Rect(nodeRect.x + nodeRect.width - 10, nodeRect.y, 10, 10);
        EditorGUI.DrawRect(statusRect, statusColor);
    }
}
```

### HFSM Debugging

For hierarchical state machines, show the active state hierarchy:

```csharp
private void DrawHFSMDebugView(HFSMDebugData debugData)
{
    // Draw state hierarchy
    DrawStateHierarchy(debugData.RootState, Vector2.zero, 0);
    
    // Highlight active state path
    for (int i = 0; i < debugData.ActiveStatePath.Count; i++)
    {
        Rect stateRect = GetStateRect(debugData.ActiveStatePath[i]);
        
        // Highlight state
        EditorGUI.DrawRect(stateRect, new Color(0, 1, 0, 0.2f));
        
        // Draw line to parent if not root
        if (i > 0)
        {
            Rect parentRect = GetStateRect(debugData.ActiveStatePath[i - 1]);
            DrawStateConnection(parentRect, stateRect, Color.green);
        }
    }
    
    // Show transition history
    for (int i = 0; i < debugData.TransitionHistory.Count; i++)
    {
        var transition = debugData.TransitionHistory[i];
        Rect sourceRect = GetStateRect(transition.Source);
        Rect targetRect = GetStateRect(transition.Target);
        
        // Draw transition arrow
        DrawTransitionArrow(sourceRect, targetRect, Color.yellow);
        
        // Show transition time
        string timeText = $"{transition.Time}";
        Vector2 midpoint = (sourceRect.center + targetRect.center) / 2;
        Rect timeRect = new Rect(midpoint.x - 20, midpoint.y - 10, 40, 20);
        EditorGUI.LabelField(timeRect, timeText);
    }
}
```

### Utility Theory Debugging

For utility-based systems, visualize the utility scores:

```csharp
private void DrawUTDebugView(UTDebugData debugData)
{
    // Draw action list
    for (int i = 0; i < debugData.Actions.Count; i++)
    {
        var action = debugData.Actions[i];
        Rect actionRect = new Rect(20, 20 + i * 60, 300, 50);
        
        // Draw action background
        EditorGUI.DrawRect(actionRect, new Color(0.2f, 0.2f, 0.2f, 1));
        
        // Draw action name
        EditorGUI.LabelField(new Rect(actionRect.x + 5, actionRect.y + 5, 200, 20), action.Name);
        
        // Draw utility score
        float score = action.Score;
        Rect scoreBarRect = new Rect(actionRect.x + 5, actionRect.y + 25, 290 * score, 20);
        
        // Color based on whether this is the selected action
        Color barColor = action.IsSelected ? Color.green : Color.gray;
        EditorGUI.DrawRect(scoreBarRect, barColor);
        
        // Draw score text
        EditorGUI.LabelField(new Rect(actionRect.x + 5, actionRect.y + 25, 290, 20), $"{score:F2}");
    }
    
    // Draw consideration breakdown for selected action
    if (debugData.SelectedActionIndex >= 0 && debugData.SelectedActionIndex < debugData.Actions.Count)
    {
        var selectedAction = debugData.Actions[debugData.SelectedActionIndex];
        
        EditorGUILayout.Space(debugData.Actions.Count * 60 + 40);
        EditorGUILayout.LabelField("Consideration Breakdown", EditorStyles.boldLabel);
        
        for (int i = 0; i < selectedAction.Considerations.Count; i++)
        {
            var consideration = selectedAction.Considerations[i];
            Rect considerationRect = new Rect(20, 20 + debugData.Actions.Count * 60 + 40 + i * 40, 300, 30);
            
            // Draw consideration name
            EditorGUI.LabelField(new Rect(considerationRect.x, considerationRect.y, 150, 20), consideration.Name);
            
            // Draw raw input value
            EditorGUI.LabelField(new Rect(considerationRect.x + 160, considerationRect.y, 60, 20), $"In: {consideration.RawInput:F2}");
            
            // Draw response curve output
            EditorGUI.LabelField(new Rect(considerationRect.x + 220, considerationRect.y, 80, 20), $"Out: {consideration.Output:F2}");
        }
    }
}
```

## Best Practices

### Effective Debugging

1. **Start simple** - Begin with a simple AI behavior and gradually add complexity
2. **Isolate issues** - Test individual actions and functions before combining them
3. **Visual indicators** - Use gizmos to visualize AI state in the scene
4. **Conditional debugging** - Enable detailed logging only when needed
5. **Test scenarios** - Create specific test scenarios for different AI behaviors

### Performance Optimization

1. **Profile early and often** - Identify bottlenecks before they become problems
2. **Limit AI updates** - Not all agents need to update every frame
3. **Optimize heavy operations** - Expensive calculations should be minimized
4. **Use spatial partitioning** - For finding nearby entities or targets
5. **Batch similar operations** - Process similar AI types together
6. **Scale complexity with distance** - Use simpler AI for distant entities

### Testing

1. **Unit test AI components** - Test individual actions and functions
2. **Integration test AI systems** - Test how components work together
3. **Stress test with many agents** - Verify performance with many AI agents
4. **Edge case testing** - Test behavior in unusual situations
5. **Automated testing** - Create automated tests for regression testing

## Common Issues and Solutions

### AI Freezing or Not Responding

**Possible causes:**
- Infinite loops in decision logic
- Missing transitions or conditions
- Errors in action execution

**Solutions:**
- Check for cyclical dependencies in state transitions
- Ensure all states have valid exit conditions
- Add timeouts to prevent getting stuck in states
- Verify that actions handle all error cases

### Performance Problems

**Possible causes:**
- Too many active agents
- Expensive calculations in update loops
- Inefficient search algorithms
- Excessive debug visualization

**Solutions:**
- Implement agent prioritization (update important agents more frequently)
- Cache results of expensive calculations
- Use spatial partitioning for proximity queries
- Disable debug visualization in builds

### Inconsistent Behavior

**Possible causes:**
- Non-deterministic operations
- Race conditions between systems
- Random numbers not properly seeded
- Frame-dependent logic

**Solutions:**
- Use Quantum's deterministic math and random functions
- Ensure systems update in the correct order
- Verify that all operations are deterministic
- Test behavior at different frame rates
