# Debugging and Visualization Tools

This document details the debugging and visualization tools available for bot development in the twin stick shooter game.

## BotSDKDebuggerSystem

The twin stick shooter includes a comprehensive debugging system for bots:

```csharp
public static class BotSDKDebuggerSystem
{
    #region Constants and Static Fields
    private const int MAX_CONCURRENT_DEBUGGABLE_ENTITIES = 10;
    private static Dictionary<int, EntityDebugData> s_entityToData = new Dictionary<int, EntityDebugData>();
    private static List<EntityDebugData> s_allEntityData = new List<EntityDebugData>();
    #endregion
    
    #region Entity Debug Data
    private class EntityDebugData
    {
        public int EntityId;
        public string EntityLabel;
        public Dictionary<Type, object> Components = new Dictionary<Type, object>();
        public Dictionary<string, object> BlackboardValues = new Dictionary<string, object>();
        public HFSMDebugData HFSMData;
        public AIMemoryDebugData MemoryData;
        
        public EntityDebugData(int entityId, string label)
        {
            EntityId = entityId;
            EntityLabel = label;
        }
    }
    
    private class HFSMDebugData
    {
        public string CurrentState;
        public List<string> StateHierarchy = new List<string>();
        public Dictionary<string, bool> TransitionConditions = new Dictionary<string, bool>();
        public float TimeInCurrentState;
    }
    
    private class AIMemoryDebugData
    {
        public List<MemoryEntryDebugData> Entries = new List<MemoryEntryDebugData>();
    }
    
    private class MemoryEntryDebugData
    {
        public string Type;
        public float ExpirationTime;
        public Dictionary<string, object> Data = new Dictionary<string, object>();
    }
    #endregion
    
    #region Public Methods
    public static void AddToDebugger<T>(Frame frame, EntityRef entity, T component) where T : struct
    {
        // Skip if we're already at max entities
        if (s_entityToData.Count >= MAX_CONCURRENT_DEBUGGABLE_ENTITIES && !s_entityToData.ContainsKey(entity.Id))
            return;
        
        // Create entity data if it doesn't exist
        if (!s_entityToData.ContainsKey(entity.Id))
        {
            string label = $"Bot {entity.Id}";
            if (frame.Has<Character>(entity))
            {
                var character = frame.Get<Character>(entity);
                label = $"{character.CharacterClass} Bot {entity.Id}";
            }
            
            var entityData = new EntityDebugData(entity.Id, label);
            s_entityToData[entity.Id] = entityData;
            s_allEntityData.Add(entityData);
        }
        
        // Add component data
        var data = s_entityToData[entity.Id];
        data.Components[typeof(T)] = component;
        
        // If this is a HFSMAgent, initialize HFSM debug data
        if (typeof(T) == typeof(HFSMAgent))
        {
            data.HFSMData = new HFSMDebugData();
        }
        
        // If entity has AIMemory, initialize memory debug data
        if (frame.Has<AIMemory>(entity))
        {
            data.MemoryData = new AIMemoryDebugData();
        }
        
        // If entity has AIBlackboardComponent, fetch initial values
        if (frame.Has<AIBlackboardComponent>(entity))
        {
            UpdateBlackboardValues(frame, entity);
        }
    }
    
    public static void RemoveFromDebugger(int entityId)
    {
        if (!s_entityToData.ContainsKey(entityId))
            return;
        
        var data = s_entityToData[entityId];
        s_allEntityData.Remove(data);
        s_entityToData.Remove(entityId);
    }
    
    public static void UpdateDebugData(Frame frame)
    {
        foreach (var entityData in s_allEntityData)
        {
            EntityRef entity = new EntityRef { Id = entityData.EntityId };
            
            if (!frame.Exists(entity))
            {
                // Entity no longer exists, remove from debugger
                s_entityToData.Remove(entityData.EntityId);
                s_allEntityData.Remove(entityData);
                continue;
            }
            
            // Update HFSM data if available
            if (entityData.HFSMData != null && frame.Has<HFSMAgent>(entity))
            {
                UpdateHFSMData(frame, entity, entityData.HFSMData);
            }
            
            // Update AIMemory data if available
            if (entityData.MemoryData != null && frame.Has<AIMemory>(entity))
            {
                UpdateMemoryData(frame, entity, entityData.MemoryData);
            }
            
            // Update blackboard values
            if (frame.Has<AIBlackboardComponent>(entity))
            {
                UpdateBlackboardValues(frame, entity);
            }
        }
    }
    #endregion
    
    #region Private Helper Methods
    private static void UpdateHFSMData(Frame frame, EntityRef entity, HFSMDebugData hfsmData)
    {
        var agent = frame.Get<HFSMAgent>(entity);
        
        // Get current state
        if (agent.CurrentStateEntity != default)
        {
            var stateComponent = frame.Get<HFSMStateComponent>(agent.CurrentStateEntity);
            hfsmData.CurrentState = stateComponent.Name;
            
            // Build state hierarchy
            hfsmData.StateHierarchy.Clear();
            EntityRef currentState = agent.CurrentStateEntity;
            while (currentState != default)
            {
                var state = frame.Get<HFSMStateComponent>(currentState);
                hfsmData.StateHierarchy.Add(state.Name);
                
                currentState = state.ParentState;
            }
            
            // Update transitions
            hfsmData.TransitionConditions.Clear();
            var transitions = frame.ResolveList(stateComponent.Transitions);
            for (int i = 0; i < transitions.Count; i++)
            {
                HFSMTransition transition = frame.Get<HFSMTransition>(transitions[i]);
                var targetState = frame.Get<HFSMStateComponent>(transition.TargetState);
                
                // Evaluate transition
                bool result = HFSMManager.EvaluateTransition(frame, entity, transition);
                hfsmData.TransitionConditions[targetState.Name] = result;
            }
            
            // Update time in current state
            hfsmData.TimeInCurrentState = Convert.ToSingle(stateComponent.TimeInState);
        }
        else
        {
            hfsmData.CurrentState = "None";
            hfsmData.StateHierarchy.Clear();
            hfsmData.TransitionConditions.Clear();
            hfsmData.TimeInCurrentState = 0f;
        }
    }
    
    private static void UpdateMemoryData(Frame frame, EntityRef entity, AIMemoryDebugData memoryData)
    {
        var aiMemory = frame.Get<AIMemory>(entity);
        var entries = frame.ResolveList(aiMemory.MemoryEntries);
        
        memoryData.Entries.Clear();
        
        for (int i = 0; i < entries.Count; i++)
        {
            var entry = entries[i];
            
            var entryData = new MemoryEntryDebugData
            {
                Type = GetMemoryTypeName(entry.Data.Field),
                ExpirationTime = Convert.ToSingle(entry.ExpirationTime)
            };
            
            // Extract specific memory data
            switch (entry.Data.Field)
            {
                case MemoryData.AREAAVOIDANCE:
                    var areaData = frame.Raw.ResolvePtr<MemoryDataAreaAvoidance>(entry.Data.AreaAvoidance);
                    entryData.Data["Entity"] = areaData->Entity.Id;
                    entryData.Data["RunDistance"] = Convert.ToSingle(areaData->RunDistance);
                    entryData.Data["Weight"] = Convert.ToSingle(areaData->Weight);
                    break;
                    
                case MemoryData.LINEAVOIDANCE:
                    var lineData = frame.Raw.ResolvePtr<MemoryDataLineAvoidance>(entry.Data.LineAvoidance);
                    entryData.Data["Entity"] = lineData->Entity.Id;
                    entryData.Data["Direction"] = new Vector2(
                        Convert.ToSingle(lineData->Direction.X),
                        Convert.ToSingle(lineData->Direction.Y));
                    entryData.Data["Weight"] = Convert.ToSingle(lineData->Weight);
                    break;
                    
                // Add cases for other memory types
            }
            
            memoryData.Entries.Add(entryData);
        }
    }
    
    private static void UpdateBlackboardValues(Frame frame, EntityRef entity)
    {
        var blackboard = frame.Get<AIBlackboardComponent>(entity);
        var entityData = s_entityToData[entity.Id];
        
        // This is simplified since we can't easily iterate the blackboard in the real game
        // In a real implementation, you would use reflection or other means to extract values
        
        // Example:
        if (blackboard.Has("TargetEntity"))
        {
            entityData.BlackboardValues["TargetEntity"] = blackboard.Get<EntityRef>("TargetEntity").Id;
        }
        
        if (blackboard.Has("TargetVisible"))
        {
            entityData.BlackboardValues["TargetVisible"] = blackboard.Get<bool>("TargetVisible");
        }
        
        // And so on for other known values
    }
    
    private static string GetMemoryTypeName(int field)
    {
        switch (field)
        {
            case MemoryData.AREAAVOIDANCE:
                return "AreaAvoidance";
            case MemoryData.LINEAVOIDANCE:
                return "LineAvoidance";
            // Other cases
            default:
                return "Unknown";
        }
    }
    #endregion
}
```

This comprehensive debugging system allows developers to track and visualize bot behavior at runtime.

## Unity Editor Integration

### Debug Window

```csharp
public class BotDebugWindow : EditorWindow
{
    [MenuItem("Quantum/Bot SDK/Debug Window")]
    public static void ShowWindow()
    {
        GetWindow<BotDebugWindow>("Bot Debugger");
    }
    
    private Vector2 _scrollPosition;
    private int _selectedEntityIndex = -1;
    private string _selectedTab = "HFSM";
    private string[] _tabs = { "HFSM", "Blackboard", "Memory", "Components" };
    
    private void OnGUI()
    {
        // Update data when in play mode
        if (Application.isPlaying && QuantumRunner.Default != null)
        {
            var runner = QuantumRunner.Default;
            var frame = runner.Game.Frames.Verified;
            
            // Call our update method
            BotSDKDebuggerSystem.UpdateDebugData(frame);
        }
        
        GUILayout.Label("Bot Debugger", EditorStyles.boldLabel);
        
        using (new EditorGUILayout.HorizontalScope())
        {
            // Entity list
            using (new EditorGUILayout.VerticalScope(GUILayout.Width(200)))
            {
                GUILayout.Label("Entities", EditorStyles.boldLabel);
                
                _scrollPosition = EditorGUILayout.BeginScrollView(_scrollPosition);
                
                for (int i = 0; i < BotSDKDebuggerSystem.EntityCount; i++)
                {
                    var entityData = BotSDKDebuggerSystem.GetEntityData(i);
                    if (GUILayout.Toggle(_selectedEntityIndex == i, entityData.EntityLabel, "Button"))
                    {
                        if (_selectedEntityIndex != i)
                        {
                            _selectedEntityIndex = i;
                        }
                    }
                }
                
                EditorGUILayout.EndScrollView();
            }
            
            // Entity details
            if (_selectedEntityIndex >= 0 && _selectedEntityIndex < BotSDKDebuggerSystem.EntityCount)
            {
                var entityData = BotSDKDebuggerSystem.GetEntityData(_selectedEntityIndex);
                
                using (new EditorGUILayout.VerticalScope())
                {
                    // Tabs
                    using (new EditorGUILayout.HorizontalScope())
                    {
                        foreach (var tab in _tabs)
                        {
                            if (GUILayout.Toggle(_selectedTab == tab, tab, "Button"))
                            {
                                _selectedTab = tab;
                            }
                        }
                    }
                    
                    // Tab content
                    using (new EditorGUILayout.VerticalScope("box"))
                    {
                        switch (_selectedTab)
                        {
                            case "HFSM":
                                DrawHFSMTab(entityData);
                                break;
                            case "Blackboard":
                                DrawBlackboardTab(entityData);
                                break;
                            case "Memory":
                                DrawMemoryTab(entityData);
                                break;
                            case "Components":
                                DrawComponentsTab(entityData);
                                break;
                        }
                    }
                }
            }
            else
            {
                EditorGUILayout.LabelField("Select an entity to view details");
            }
        }
        
        // Auto-repaint while in play mode
        if (Application.isPlaying)
        {
            Repaint();
        }
    }
    
    private void DrawHFSMTab(BotSDKDebuggerSystem.EntityDebugData entityData)
    {
        if (entityData.HFSMData == null)
        {
            EditorGUILayout.LabelField("No HFSM data available");
            return;
        }
        
        EditorGUILayout.LabelField("Current State", entityData.HFSMData.CurrentState);
        EditorGUILayout.LabelField("Time in State", $"{entityData.HFSMData.TimeInCurrentState:F2} seconds");
        
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("State Hierarchy", EditorStyles.boldLabel);
        
        foreach (var state in entityData.HFSMData.StateHierarchy)
        {
            EditorGUILayout.LabelField($"- {state}");
        }
        
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("Transition Conditions", EditorStyles.boldLabel);
        
        foreach (var transition in entityData.HFSMData.TransitionConditions)
        {
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField($"To {transition.Key}");
                
                if (transition.Value)
                {
                    using (new GUIColorScope(Color.green))
                    {
                        EditorGUILayout.LabelField("TRUE", GUILayout.Width(50));
                    }
                }
                else
                {
                    using (new GUIColorScope(Color.red))
                    {
                        EditorGUILayout.LabelField("FALSE", GUILayout.Width(50));
                    }
                }
            }
        }
    }
    
    private void DrawBlackboardTab(BotSDKDebuggerSystem.EntityDebugData entityData)
    {
        EditorGUILayout.LabelField("Blackboard Values", EditorStyles.boldLabel);
        
        if (entityData.BlackboardValues.Count == 0)
        {
            EditorGUILayout.LabelField("No blackboard values available");
            return;
        }
        
        foreach (var pair in entityData.BlackboardValues)
        {
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField(pair.Key, GUILayout.Width(150));
                EditorGUILayout.LabelField(pair.Value?.ToString() ?? "null");
            }
        }
    }
    
    private void DrawMemoryTab(BotSDKDebuggerSystem.EntityDebugData entityData)
    {
        if (entityData.MemoryData == null)
        {
            EditorGUILayout.LabelField("No memory data available");
            return;
        }
        
        EditorGUILayout.LabelField("Memory Entries", EditorStyles.boldLabel);
        
        if (entityData.MemoryData.Entries.Count == 0)
        {
            EditorGUILayout.LabelField("No memory entries available");
            return;
        }
        
        foreach (var entry in entityData.MemoryData.Entries)
        {
            using (new EditorGUILayout.VerticalScope("box"))
            {
                EditorGUILayout.LabelField($"Type: {entry.Type}");
                EditorGUILayout.LabelField($"Expires: {entry.ExpirationTime:F2}");
                
                foreach (var pair in entry.Data)
                {
                    using (new EditorGUILayout.HorizontalScope())
                    {
                        EditorGUILayout.LabelField(pair.Key, GUILayout.Width(100));
                        EditorGUILayout.LabelField(pair.Value?.ToString() ?? "null");
                    }
                }
            }
        }
    }
    
    private void DrawComponentsTab(BotSDKDebuggerSystem.EntityDebugData entityData)
    {
        EditorGUILayout.LabelField("Components", EditorStyles.boldLabel);
        
        if (entityData.Components.Count == 0)
        {
            EditorGUILayout.LabelField("No component data available");
            return;
        }
        
        foreach (var component in entityData.Components)
        {
            using (new EditorGUILayout.VerticalScope("box"))
            {
                EditorGUILayout.LabelField(component.Key.Name, EditorStyles.boldLabel);
                
                // Display component properties
                // This would require reflection or custom serialization in a real implementation
                EditorGUILayout.LabelField("Component data available");
            }
        }
    }
    
    // Helper class for scope-based GUI color changes
    private class GUIColorScope : GUI.Scope
    {
        private readonly Color _originalColor;
        
        public GUIColorScope(Color color)
        {
            _originalColor = GUI.color;
            GUI.color = color;
        }
        
        protected override void CloseScope()
        {
            GUI.color = _originalColor;
        }
    }
}
```

This debug window provides a comprehensive interface for monitoring and debugging bot behavior.

## Scene Visualization

```csharp
public class BotVisualization : MonoBehaviour
{
    public bool ShowTargetLines = true;
    public bool ShowPathfinding = true;
    public bool ShowAvoidance = true;
    public bool ShowFieldOfView = true;
    public bool ShowAttackRange = true;
    
    [Header("Colors")]
    public Color TargetLineColor = Color.red;
    public Color PathfindingColor = Color.blue;
    public Color AvoidanceColor = Color.yellow;
    public Color FieldOfViewColor = new Color(0.5f, 0.5f, 0.5f, 0.2f);
    public Color AttackRangeColor = new Color(1.0f, 0.0f, 0.0f, 0.2f);
    
    private void OnEnable()
    {
        QuantumCallback.Subscribe(this, (CallbackOnDrawGizmos callback) => OnDrawGizmos(callback.Frame));
    }
    
    private void OnDisable()
    {
        QuantumCallback.Unsubscribe(this);
    }
    
    private void OnDrawGizmos(Frame frame)
    {
        if (frame == null)
            return;
        
        var bots = frame.Filter<Bot, Transform2D>();
        while (bots.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            if (bot.IsActive == false)
                continue;
            
            Vector3 position = transform.Position.ToUnityVector3();
            
            // Draw target line
            if (ShowTargetLines && frame.Has<AIBlackboardComponent>(entity))
            {
                var blackboard = frame.Get<AIBlackboardComponent>(entity);
                if (blackboard.Has("TargetEntity"))
                {
                    EntityRef targetEntity = blackboard.Get<EntityRef>("TargetEntity");
                    if (frame.Exists(targetEntity) && frame.Has<Transform2D>(targetEntity))
                    {
                        Vector3 targetPosition = frame.Get<Transform2D>(targetEntity).Position.ToUnityVector3();
                        Gizmos.color = TargetLineColor;
                        Gizmos.DrawLine(position, targetPosition);
                    }
                }
            }
            
            // Draw pathfinding
            if (ShowPathfinding && frame.Has<NavMeshPathfinder>(entity))
            {
                var pathfinder = frame.Get<NavMeshPathfinder>(entity);
                var path = frame.ResolveList(pathfinder.Path);
                
                if (path.Count > 1)
                {
                    Gizmos.color = PathfindingColor;
                    
                    Vector3 lastPoint = position;
                    for (int i = 0; i < path.Count; i++)
                    {
                        Vector3 point = path[i].Position.ToUnityVector3();
                        Gizmos.DrawLine(lastPoint, point);
                        Gizmos.DrawSphere(point, 0.1f);
                        lastPoint = point;
                    }
                }
            }
            
            // Draw avoidance
            if (ShowAvoidance && frame.Has<AIMemory>(entity))
            {
                var aiMemory = frame.Get<AIMemory>(entity);
                var memoryEntries = frame.ResolveList(aiMemory.MemoryEntries);
                
                Gizmos.color = AvoidanceColor;
                
                for (int i = 0; i < memoryEntries.Count; i++)
                {
                    var entry = memoryEntries[i];
                    
                    switch (entry.Data.Field)
                    {
                        case MemoryData.AREAAVOIDANCE:
                            var areaData = frame.Raw.ResolvePtr<MemoryDataAreaAvoidance>(entry.Data.AreaAvoidance);
                            if (frame.Exists(areaData->Entity) && frame.Has<Transform2D>(areaData->Entity))
                            {
                                Vector3 avoidPosition = frame.Get<Transform2D>(areaData->Entity).Position.ToUnityVector3();
                                float radius = areaData->RunDistance.AsFloat;
                                
                                Gizmos.DrawWireSphere(avoidPosition, radius);
                                Gizmos.DrawLine(position, avoidPosition);
                            }
                            break;
                            
                        case MemoryData.LINEAVOIDANCE:
                            var lineData = frame.Raw.ResolvePtr<MemoryDataLineAvoidance>(entry.Data.LineAvoidance);
                            if (frame.Exists(lineData->Entity) && frame.Has<Transform2D>(lineData->Entity))
                            {
                                Vector3 avoidPosition = frame.Get<Transform2D>(lineData->Entity).Position.ToUnityVector3();
                                Vector3 direction = lineData->Direction.ToUnityVector3().normalized;
                                
                                Gizmos.DrawLine(avoidPosition, avoidPosition + direction * 5f);
                                Gizmos.DrawLine(position, avoidPosition);
                            }
                            break;
                    }
                }
            }
            
            // Draw field of view
            if (ShowFieldOfView && frame.Has<HFSMAgent>(entity))
            {
                var hfsmAgent = frame.Get<HFSMAgent>(entity);
                var aiConfig = frame.FindAsset<AIConfig>(hfsmAgent.Config.Id);
                
                if (aiConfig != null)
                {
                    Gizmos.color = FieldOfViewColor;
                    
                    float sightRange = aiConfig.SightRange.AsFloat;
                    float fieldOfView = aiConfig.FieldOfView.AsFloat;
                    
                    Vector3 forward = transform.Up.ToUnityVector3();
                    
                    // Draw field of view arc
                    DrawFieldOfViewArc(position, forward, sightRange, fieldOfView);
                }
            }
            
            // Draw attack range
            if (ShowAttackRange && frame.Has<AttackComponent>(entity))
            {
                var attackComponent = frame.Get<AttackComponent>(entity);
                
                Gizmos.color = AttackRangeColor;
                Gizmos.DrawWireSphere(position, attackComponent.AttackRange.AsFloat);
            }
        }
    }
    
    private void DrawFieldOfViewArc(Vector3 position, Vector3 forward, float radius, float angle)
    {
        float halfAngle = angle * 0.5f;
        int segments = 20;
        
        Vector3 left = Quaternion.Euler(0, 0, halfAngle) * forward;
        Vector3 right = Quaternion.Euler(0, 0, -halfAngle) * forward;
        
        Gizmos.DrawLine(position, position + left * radius);
        Gizmos.DrawLine(position, position + right * radius);
        
        Vector3 prevPoint = position + left * radius;
        
        for (int i = 1; i <= segments; i++)
        {
            float t = i / (float)segments;
            float currentAngle = halfAngle - t * angle;
            
            Vector3 direction = Quaternion.Euler(0, 0, currentAngle) * forward;
            Vector3 point = position + direction * radius;
            
            Gizmos.DrawLine(prevPoint, point);
            prevPoint = point;
        }
    }
}
```

This visualization component draws gizmos to help visualize:
1. Target lines
2. Pathfinding
3. Avoidance areas
4. Field of view
5. Attack ranges

## Runtime Debug GUI

```csharp
public class BotRuntimeDebugUI : MonoBehaviour
{
    [Header("UI Configuration")]
    public bool ShowDebugUI = true;
    public KeyCode ToggleKey = KeyCode.F12;
    public GameObject DebugCanvasPrefab;
    
    [Header("Display Options")]
    public bool ShowBotStatus = true;
    public bool ShowBotBlackboard = true;
    public bool ShowBotMemory = true;
    public bool ShowBotDecisions = true;
    
    private GameObject _debugCanvas;
    private Dictionary<int, BotStatusUI> _botStatusUIs = new Dictionary<int, BotStatusUI>();
    
    private void Start()
    {
        if (DebugCanvasPrefab != null)
        {
            _debugCanvas = Instantiate(DebugCanvasPrefab);
            _debugCanvas.SetActive(ShowDebugUI);
        }
    }
    
    private void Update()
    {
        if (Input.GetKeyDown(ToggleKey))
        {
            ShowDebugUI = !ShowDebugUI;
            
            if (_debugCanvas != null)
            {
                _debugCanvas.SetActive(ShowDebugUI);
            }
        }
        
        if (!ShowDebugUI || _debugCanvas == null)
            return;
        
        if (QuantumRunner.Default != null)
        {
            var frame = QuantumRunner.Default.Game.Frames.Verified;
            UpdateBotStatusUIs(frame);
        }
    }
    
    private void UpdateBotStatusUIs(Frame frame)
    {
        // Get all active bots
        List<EntityRef> activeBots = new List<EntityRef>();
        
        var bots = frame.Filter<Bot, Transform2D>();
        while (bots.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            if (bot.IsActive)
            {
                activeBots.Add(entity);
                
                // Create UI for bot if it doesn't exist
                if (!_botStatusUIs.ContainsKey(entity.Id))
                {
                    GameObject botStatusGO = new GameObject($"BotStatus_{entity.Id}");
                    botStatusGO.transform.SetParent(_debugCanvas.transform);
                    
                    BotStatusUI botStatusUI = botStatusGO.AddComponent<BotStatusUI>();
                    botStatusUI.Initialize(entity.Id);
                    
                    _botStatusUIs[entity.Id] = botStatusUI;
                }
                
                // Update UI
                _botStatusUIs[entity.Id].UpdateFromFrame(frame, entity);
            }
        }
        
        // Remove UIs for bots that no longer exist or are inactive
        List<int> botsToRemove = new List<int>();
        
        foreach (var kvp in _botStatusUIs)
        {
            bool botExists = false;
            foreach (var bot in activeBots)
            {
                if (bot.Id == kvp.Key)
                {
                    botExists = true;
                    break;
                }
            }
            
            if (!botExists)
            {
                botsToRemove.Add(kvp.Key);
                Destroy(kvp.Value.gameObject);
            }
        }
        
        foreach (int id in botsToRemove)
        {
            _botStatusUIs.Remove(id);
        }
    }
}

public class BotStatusUI : MonoBehaviour
{
    [Header("UI Components")]
    public Text BotIdText;
    public Text StateText;
    public Text HealthText;
    public Slider HealthBar;
    public Transform BlackboardPanel;
    public Transform MemoryPanel;
    public Text BlackboardText;
    public Text MemoryText;
    
    [Header("Display Options")]
    public bool FollowBot = true;
    public Vector3 Offset = new Vector3(0, 2, 0);
    public float MaxDisplayDistance = 20f;
    
    private int _botId;
    private Transform _botTransform;
    private Canvas _canvas;
    private bool _initialized;
    
    public void Initialize(int botId)
    {
        _botId = botId;
        
        // Create UI components if they don't exist
        // This would be more detailed in a real implementation
        if (BotIdText == null)
        {
            GameObject textGO = new GameObject("BotIdText");
            textGO.transform.SetParent(transform);
            BotIdText = textGO.AddComponent<Text>();
            BotIdText.text = $"Bot {_botId}";
        }
        
        _initialized = true;
    }
    
    public void UpdateFromFrame(Frame frame, EntityRef entity)
    {
        if (!_initialized)
            return;
        
        // Update Bot Transform reference
        var view = QuantumRunner.Default.Game.GetView(entity);
        if (view != null)
        {
            _botTransform = view.transform;
        }
        
        // Update UI position if following bot
        if (FollowBot && _botTransform != null)
        {
            // Calculate screen position
            Vector3 screenPos = Camera.main.WorldToScreenPoint(_botTransform.position + Offset);
            
            // Check if bot is in front of camera
            if (screenPos.z < 0)
            {
                gameObject.SetActive(false);
                return;
            }
            
            // Check distance to camera
            float distance = Vector3.Distance(Camera.main.transform.position, _botTransform.position);
            if (distance > MaxDisplayDistance)
            {
                gameObject.SetActive(false);
                return;
            }
            
            gameObject.SetActive(true);
            transform.position = screenPos;
            
            // Scale based on distance
            float scale = Mathf.Lerp(1.0f, 0.5f, distance / MaxDisplayDistance);
            transform.localScale = new Vector3(scale, scale, scale);
        }
        
        // Update UI content
        if (StateText != null && frame.Has<HFSMAgent>(entity))
        {
            var agent = frame.Get<HFSMAgent>(entity);
            if (agent.CurrentStateEntity != default)
            {
                var stateComponent = frame.Get<HFSMStateComponent>(agent.CurrentStateEntity);
                StateText.text = $"State: {stateComponent.Name}";
            }
            else
            {
                StateText.text = "State: None";
            }
        }
        
        if (HealthText != null && HealthBar != null && frame.Has<Health>(entity))
        {
            var health = frame.Get<Health>(entity);
            float healthPercent = (float)(health.CurrentHealth / health.MaxHealth);
            
            HealthText.text = $"HP: {health.CurrentHealth:F0}/{health.MaxHealth:F0}";
            HealthBar.value = healthPercent;
            
            // Color code health bar
            Image fillImage = HealthBar.fillRect.GetComponent<Image>();
            if (fillImage != null)
            {
                if (healthPercent > 0.6f)
                    fillImage.color = Color.green;
                else if (healthPercent > 0.3f)
                    fillImage.color = Color.yellow;
                else
                    fillImage.color = Color.red;
            }
        }
        
        // Update blackboard display
        if (BlackboardText != null && frame.Has<AIBlackboardComponent>(entity))
        {
            var blackboard = frame.Get<AIBlackboardComponent>(entity);
            
            // This is a simplified example, you'd need a different approach to inspect blackboard contents
            // Since we can't easily iterate the blackboard in the real game
            
            string bbText = "Blackboard:\n";
            
            // Check for known keys
            if (blackboard.Has("TargetEntity"))
            {
                bbText += $"Target: {blackboard.Get<EntityRef>("TargetEntity").Id}\n";
            }
            
            if (blackboard.Has("TargetVisible"))
            {
                bbText += $"Visible: {blackboard.Get<bool>("TargetVisible")}\n";
            }
            
            if (blackboard.Has("TargetDistance"))
            {
                bbText += $"Distance: {blackboard.Get<FP>("TargetDistance"):F1}\n";
            }
            
            BlackboardText.text = bbText;
        }
        
        // Update memory display
        if (MemoryText != null && frame.Has<AIMemory>(entity))
        {
            var aiMemory = frame.Get<AIMemory>(entity);
            var entries = frame.ResolveList(aiMemory.MemoryEntries);
            
            string memText = $"Memory ({entries.Count}):\n";
            
            for (int i = 0; i < Mathf.Min(entries.Count, 3); i++) // Show max 3 entries
            {
                var entry = entries[i];
                
                switch (entry.Data.Field)
                {
                    case MemoryData.AREAAVOIDANCE:
                        memText += "Area Avoid\n";
                        break;
                    case MemoryData.LINEAVOIDANCE:
                        memText += "Line Avoid\n";
                        break;
                    default:
                        memText += "Unknown\n";
                        break;
                }
            }
            
            if (entries.Count > 3)
            {
                memText += $"...and {entries.Count - 3} more";
            }
            
            MemoryText.text = memText;
        }
    }
}
```

This runtime debug UI provides an in-game visualization of bot state:
1. Bot status (health, state)
2. Blackboard values
3. Memory entries
4. Decision-making process

## Logging System

```csharp
public static class BotLog
{
    public enum LogLevel
    {
        Verbose,
        Info,
        Warning,
        Error
    }
    
    private static LogLevel _currentLevel = LogLevel.Info;
    private static bool _enabled = true;
    private static List<string> _logBuffer = new List<string>(100);
    private static int _maxBufferSize = 100;
    
    public static void SetLogLevel(LogLevel level)
    {
        _currentLevel = level;
    }
    
    public static void Enable()
    {
        _enabled = true;
    }
    
    public static void Disable()
    {
        _enabled = false;
    }
    
    public static void Verbose(string message, EntityRef entity = default)
    {
        if (_enabled && _currentLevel <= LogLevel.Verbose)
        {
            Log("[VERBOSE]", message, entity);
        }
    }
    
    public static void Info(string message, EntityRef entity = default)
    {
        if (_enabled && _currentLevel <= LogLevel.Info)
        {
            Log("[INFO]", message, entity);
        }
    }
    
    public static void Warning(string message, EntityRef entity = default)
    {
        if (_enabled && _currentLevel <= LogLevel.Warning)
        {
            Log("[WARNING]", message, entity);
        }
    }
    
    public static void Error(string message, EntityRef entity = default)
    {
        if (_enabled && _currentLevel <= LogLevel.Error)
        {
            Log("[ERROR]", message, entity);
        }
    }
    
    private static void Log(string level, string message, EntityRef entity)
    {
        string logMessage = $"[BOT]{level} {(entity != default ? $"[Entity {entity.Id}] " : "")}[{Time.time:F2}] {message}";
        
        Debug.Log(logMessage);
        
        _logBuffer.Add(logMessage);
        if (_logBuffer.Count > _maxBufferSize)
        {
            _logBuffer.RemoveAt(0);
        }
    }
    
    public static List<string> GetRecentLogs()
    {
        return new List<string>(_logBuffer);
    }
    
    public static void ClearLogs()
    {
        _logBuffer.Clear();
    }
}
```

The logging system provides a way to track bot behavior and debug issues:
1. Different log levels for verbose, info, warning, and error
2. Entity-specific logging
3. Log buffering for later analysis

These debugging and visualization tools provide a comprehensive set of capabilities for developing and debugging bot behavior in the twin stick shooter game.
