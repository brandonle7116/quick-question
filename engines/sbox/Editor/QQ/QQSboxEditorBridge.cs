using Editor;
using Sandbox;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace QQ.EditorBridge;

public static class QQSboxEditorBridge
{
    private const string BridgeVersion = "0.1.0";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = true
    };

    private static string? ProjectRoot;
    private static string? RequestDir;
    private static string? ResponseDir;
    private static string? StateFile;
    private static string? ConsoleFile;
    private static bool BootLogged;

    [Event( "editor.created" )]
    public static void OnEditorCreated()
    {
        EnsureBootstrap();
        WriteConsole( "bridge.boot", "qq S&box editor bridge booted" );
    }

    [Event( "tool.frame" )]
    public static void OnToolFrame()
    {
        EnsureBootstrap();
        WriteHeartbeat();
        ProcessRequests();
    }

    private static void EnsureBootstrap()
    {
        if ( !string.IsNullOrEmpty( ProjectRoot ) && Directory.Exists( ProjectRoot ) )
            return;

        ProjectRoot = ResolveProjectRoot();
        var qqStateDir = Path.Combine( ProjectRoot, ".qq", "state" );
        RequestDir = Path.Combine( qqStateDir, "qq-sbox-editor", "requests" );
        ResponseDir = Path.Combine( qqStateDir, "qq-sbox-editor", "responses" );
        StateFile = Path.Combine( qqStateDir, "qq-sbox-editor-bridge.json" );
        ConsoleFile = Path.Combine( qqStateDir, "qq-sbox-editor-console.jsonl" );

        Directory.CreateDirectory( qqStateDir );
        Directory.CreateDirectory( RequestDir );
        Directory.CreateDirectory( ResponseDir );
        Directory.CreateDirectory( Path.GetDirectoryName( ConsoleFile ) ?? qqStateDir );

        if ( !BootLogged )
        {
            BootLogged = true;
            Log.Info( $"qq S&box editor bridge initialized at {ProjectRoot}" );
        }
    }

    private static string ResolveProjectRoot()
    {
        foreach ( var candidate in EnumerateRootCandidates() )
        {
            var root = FindProjectRootFrom( candidate );
            if ( root is not null )
                return root;
        }

        return Directory.GetCurrentDirectory();
    }

    private static IEnumerable<string> EnumerateRootCandidates()
    {
        var seen = new HashSet<string>( StringComparer.OrdinalIgnoreCase );

        foreach ( var raw in new[]
        {
            Environment.GetEnvironmentVariable( "QQ_PROJECT_DIR" ),
            Directory.GetCurrentDirectory(),
            AppContext.BaseDirectory,
            Path.GetDirectoryName( Assembly.GetExecutingAssembly().Location )
        } )
        {
            var value = raw?.Trim();
            if ( string.IsNullOrEmpty( value ) )
                continue;

            string normalized;
            try
            {
                normalized = Path.GetFullPath( value );
            }
            catch
            {
                continue;
            }

            if ( !seen.Add( normalized ) )
                continue;

            yield return normalized;
        }
    }

    private static string? FindProjectRootFrom( string start )
    {
        var current = new DirectoryInfo( start );
        while ( current is not null )
        {
            if ( ContainsProjectMarker( current.FullName ) )
                return current.FullName;
            current = current.Parent;
        }

        return null;
    }

    private static bool ContainsProjectMarker( string directory )
    {
        if ( File.Exists( Path.Combine( directory, ".sbproj" ) ) )
            return true;

        return Directory.EnumerateFiles( directory, "*.sbproj", SearchOption.TopDirectoryOnly ).Any();
    }

    private static void WriteHeartbeat()
    {
        if ( string.IsNullOrEmpty( StateFile ) || string.IsNullOrEmpty( ProjectRoot ) )
            return;

        var payload = new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["running"] = true,
            ["engine"] = "sbox",
            ["bridgeVersion"] = BridgeVersion,
            ["projectRoot"] = ProjectRoot,
            ["lastHeartbeatUnix"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0
        };

        File.WriteAllText( StateFile, JsonSerializer.Serialize( payload, JsonOptions ) + Environment.NewLine );
    }

    private static void ProcessRequests()
    {
        if ( string.IsNullOrEmpty( RequestDir ) || string.IsNullOrEmpty( ResponseDir ) )
            return;

        foreach ( var requestPath in Directory.EnumerateFiles( RequestDir, "*.json", SearchOption.TopDirectoryOnly ).OrderBy( static p => p, StringComparer.Ordinal ) )
        {
            var request = ReadRequest( requestPath );
            if ( request is null )
            {
                SafeDelete( requestPath );
                continue;
            }

            var response = HandleRequest( request );
            var responsePath = Path.Combine( ResponseDir, $"{request.RequestId}.json" );
            File.WriteAllText( responsePath, JsonSerializer.Serialize( response, JsonOptions ) + Environment.NewLine );
            SafeDelete( requestPath );
        }
    }

    private static RequestPayload? ReadRequest( string path )
    {
        try
        {
            return JsonSerializer.Deserialize<RequestPayload>( File.ReadAllText( path ), JsonOptions );
        }
        catch ( Exception ex )
        {
            WriteConsole( "bridge.error", $"failed to read request {Path.GetFileName( path )}: {ex.Message}" );
            return null;
        }
    }

    private static ResponsePayload HandleRequest( RequestPayload request )
    {
        try
        {
            var args = request.Args ?? new Dictionary<string, JsonElement>( StringComparer.OrdinalIgnoreCase );
            WriteConsole( "bridge.command", $"handling {request.Command}", new Dictionary<string, object?>
            {
                ["requestId"] = request.RequestId,
                ["command"] = request.Command
            } );

            return request.Command switch
            {
                "status" => Ok( "Loaded S&box bridge status", BuildStatusData() ),
                "hierarchy" => Ok( "Loaded S&box hierarchy", new Dictionary<string, object?>
                {
                    ["items"] = BuildHierarchyEntries( GetArgInt( args, "depth", 4 ) )
                } ),
                "find-objects" => Ok( "Found matching S&box objects", new Dictionary<string, object?>
                {
                    ["items"] = FindObjectEntries(
                        GetArgString( args, "filter" ),
                        GetArgString( args, "name" ),
                        GetArgString( args, "type" ),
                        GetArgInt( args, "count", 50 )
                    )
                } ),
                "inspect-object" => Ok( "Loaded S&box object details", new Dictionary<string, object?>
                {
                    ["object"] = SerializeGameObject( ResolveGameObjectFromArgs( args ) )
                } ),
                "get-selection" => Ok( "Loaded S&box selection", new Dictionary<string, object?>
                {
                    ["items"] = GetSelectionEntries()
                } ),
                "play" => Ok( "Entered S&box play mode", PlayScene() ),
                "stop" => Ok( "Stopped S&box play mode", StopScene() ),
                "pause" => Ok( "Toggled S&box pause state", TogglePause() ),
                "save-scene" => Ok( "Saved active S&box scene", SaveActiveScene() ),
                "open-scene" => Ok( "Opened S&box scene", OpenSceneAsset( GetRequiredPathArg( args, "path" ) ) ),
                "new-scene" => Ok( "Created S&box scene", CreateAndOpenSceneAsset( GetRequiredPathArg( args, "path" ) ) ),
                "reload-scene" => Ok( "Reloaded active S&box scene", ReloadActiveScene() ),
                "create-object" => Ok( "Created S&box object", CreateObject( args ) ),
                "destroy-object" => Ok( "Destroyed S&box object", DestroyObject( ResolveGameObjectFromArgs( args ) ) ),
                "duplicate-object" => Ok( "Duplicated S&box object", DuplicateObject( ResolveGameObjectFromArgs( args ) ) ),
                "set-transform" => Ok( "Updated S&box object transform", SetObjectTransform( ResolveGameObjectFromArgs( args ), args ) ),
                "set-parent" => Ok( "Updated S&box object parent", SetObjectParent( ResolveGameObjectFromArgs( args ), GetRequiredGameObjectArg( args, "parent" ) ) ),
                "set-active" => Ok( "Updated S&box object active state", SetObjectActive( ResolveGameObjectFromArgs( args ), GetArgBool( args, "active", true ) ) ),
                "set-property" => Ok( "Updated S&box object property", SetObjectProperty( ResolveGameObjectFromArgs( args ), GetArgString( args, "property" ), GetRequiredArg( args, "value" ) ) ),
                "select-object" => Ok( "Updated S&box selection", SelectObject( ResolveGameObjectFromArgs( args ) ) ),
                "list-scenes" => Ok( "Listed S&box scene assets", new Dictionary<string, object?>
                {
                    ["items"] = EnumerateSceneEntries( GetArgString( args, "filter" ), GetArgInt( args, "count", 200 ) )
                } ),
                "inspect-scene" => Ok( "Loaded S&box scene details", InspectFile( GetRequiredPathArg( args, "path" ), sceneOnly: true ) ),
                "duplicate-scene" => Ok( "Duplicated scene asset", DuplicateFile( GetRequiredPathArg( args, "source" ), GetRequiredPathArg( args, "target" ), sceneOnly: true ) ),
                "rename-scene" => Ok( "Renamed scene asset", RenameFile( GetRequiredPathArg( args, "source" ), GetRequiredPathArg( args, "target" ), sceneOnly: true ) ),
                "delete-scene" => Ok( "Deleted scene asset", DeleteFile( GetRequiredPathArg( args, "path" ), sceneOnly: true ) ),
                "list-assets" => Ok( "Listed S&box assets", new Dictionary<string, object?>
                {
                    ["items"] = EnumerateAssetEntries( GetArgString( args, "filter" ), GetArgInt( args, "count", 200 ) )
                } ),
                "inspect-asset" => Ok( "Loaded asset details", InspectFile( GetRequiredPathArg( args, "path" ), sceneOnly: false ) ),
                "create-directory" => Ok( "Created asset directory", CreateDirectory( GetRequiredPathArg( args, "path" ) ) ),
                "duplicate-asset" => Ok( "Duplicated asset", DuplicateFile( GetRequiredPathArg( args, "source" ), GetRequiredPathArg( args, "target" ), sceneOnly: false ) ),
                "rename-asset" => Ok( "Renamed asset", RenameFile( GetRequiredPathArg( args, "source" ), GetRequiredPathArg( args, "target" ), sceneOnly: false ) ),
                "delete-asset" => Ok( "Deleted asset", DeleteFile( GetRequiredPathArg( args, "path" ), sceneOnly: false ) ),
                _ => Error( "UNSUPPORTED_COMMAND", $"Unsupported S&box bridge command: {request.Command}" )
            };
        }
        catch ( Exception ex )
        {
            WriteConsole( "bridge.error", ex.Message, new Dictionary<string, object?>
            {
                ["command"] = request.Command,
                ["requestId"] = request.RequestId
            } );
            return Error( "COMMAND_FAILED", ex.Message );
        }
    }

    private static Dictionary<string, object?> BuildStatusData()
    {
        var projectRoot = RequireProjectRoot();
        var session = SceneEditorSession.Active;
        var scenePath = session?.Scene?.Source?.ResourcePath ?? string.Empty;
        var selection = session?.Selection?.OfType<GameObject>().Where( static go => go is not Scene && go.IsValid() ).ToArray() ?? Array.Empty<GameObject>();
        return new Dictionary<string, object?>
        {
            ["projectRoot"] = projectRoot,
            ["projectFile"] = FindProjectFile( projectRoot ),
            ["sceneCount"] = EnumerateSceneFiles().Count(),
            ["assetCount"] = EnumerateAssetFiles().Count(),
            ["editorCodePresent"] = Directory.Exists( Path.Combine( projectRoot, "Editor" ) ),
            ["libraryCount"] = Directory.Exists( Path.Combine( projectRoot, "Libraries" ) )
                ? Directory.EnumerateDirectories( Path.Combine( projectRoot, "Libraries" ) ).Count()
                : 0,
            ["playState"] = Game.IsPlaying ? (Game.IsPaused ? "paused" : "playing") : "stopped",
            ["activeScenePath"] = scenePath,
            ["activeSceneId"] = session?.Scene?.Id.ToString() ?? string.Empty,
            ["isPrefabSession"] = session?.IsPrefabSession ?? false,
            ["selectionCount"] = selection.Length,
            ["selection"] = selection.Select( SerializeGameObjectSummary ).ToList()
        };
    }

    private static SceneEditorSession RequireActiveSession()
    {
        return SceneEditorSession.Active ?? throw new InvalidOperationException( "No active S&box scene editor session is available." );
    }

    private static Scene RequireActiveScene()
    {
        return RequireActiveSession().Scene ?? throw new InvalidOperationException( "No active S&box scene is loaded." );
    }

    private static IEnumerable<GameObject> EnumerateGameObjects( Scene scene )
    {
        return scene
            .GetAllObjects( false )
            .Where( static go => go is not Scene && go.IsValid() );
    }

    private static List<Dictionary<string, object?>> BuildHierarchyEntries( int depth )
    {
        var scene = RequireActiveScene();
        return scene.Children
            .OfType<GameObject>()
            .Where( static go => go.IsValid() )
            .Select( go => SerializeHierarchyNode( go, Math.Max( depth, 1 ) ) )
            .ToList();
    }

    private static List<Dictionary<string, object?>> FindObjectEntries( string filter, string name, string typeName, int count )
    {
        var scene = RequireActiveScene();
        return EnumerateGameObjects( scene )
            .Where( go => MatchesObjectFilter( go, filter, name, typeName ) )
            .Take( Math.Max( count, 1 ) )
            .Select( SerializeGameObjectSummary )
            .ToList();
    }

    private static List<Dictionary<string, object?>> GetSelectionEntries()
    {
        return RequireActiveSession()
            .Selection
            .OfType<GameObject>()
            .Where( static go => go is not Scene && go.IsValid() )
            .Select( SerializeGameObjectSummary )
            .ToList();
    }

    private static Dictionary<string, object?> PlayScene()
    {
        var session = RequireActiveSession();
        if ( !Game.IsPlaying )
        {
            EditorScene.Play( session );
        }

        return new Dictionary<string, object?>
        {
            ["playState"] = Game.IsPaused ? "paused" : "playing",
            ["activeScenePath"] = session.Scene?.Source?.ResourcePath ?? string.Empty
        };
    }

    private static Dictionary<string, object?> StopScene()
    {
        if ( Game.IsPlaying )
        {
            EditorScene.Stop();
        }

        return new Dictionary<string, object?>
        {
            ["playState"] = "stopped"
        };
    }

    private static Dictionary<string, object?> TogglePause()
    {
        if ( !Game.IsPlaying )
            throw new InvalidOperationException( "Cannot pause when the editor is not in play mode." );

        Game.IsPaused = !Game.IsPaused;
        return new Dictionary<string, object?>
        {
            ["playState"] = Game.IsPaused ? "paused" : "playing"
        };
    }

    private static Dictionary<string, object?> SaveActiveScene()
    {
        var session = RequireActiveSession();
        session.Save( false );
        return new Dictionary<string, object?>
        {
            ["scenePath"] = session.Scene?.Source?.ResourcePath ?? string.Empty,
            ["saved"] = true
        };
    }

    private static Dictionary<string, object?> OpenSceneAsset( string relativePath )
    {
        var normalized = NormalizeSceneAssetPath( relativePath );
        EditorScene.OpenScene( ResolveSceneFile( normalized ) );
        return new Dictionary<string, object?>
        {
            ["scenePath"] = normalized,
            ["opened"] = true
        };
    }

    private static Dictionary<string, object?> CreateAndOpenSceneAsset( string relativePath )
    {
        var normalized = NormalizeSceneAssetPath( relativePath );
        var absolute = ResolveProjectPath( normalized, requireScene: true, requireExisting: false );
        EnsureParentDirectory( absolute );
        File.WriteAllText( absolute, "scene {}\n" );

        try
        {
            EditorScene.OpenScene( ResolveSceneFile( normalized ) );
        }
        catch
        {
            // Asset discovery can lag behind file creation slightly; return the created path even if live open failed.
        }

        return new Dictionary<string, object?>
        {
            ["scenePath"] = normalized,
            ["created"] = true,
            ["opened"] = SceneEditorSession.Active?.Scene?.Source?.ResourcePath == normalized
        };
    }

    private static Dictionary<string, object?> ReloadActiveScene()
    {
        var session = RequireActiveSession();
        session.Reload();
        return new Dictionary<string, object?>
        {
            ["scenePath"] = session.Scene?.Source?.ResourcePath ?? string.Empty,
            ["reloaded"] = true
        };
    }

    private static Dictionary<string, object?> CreateObject( Dictionary<string, JsonElement> args )
    {
        using var scope = SceneEditorSession.Scope();

        var parent = GetOptionalGameObjectArg( args, "parent" );
        var requestedType = GetArgString( args, "node_type" );
        var desiredName = string.IsNullOrWhiteSpace( GetArgString( args, "name" ) ) ? "Object" : GetArgString( args, "name" );

        using ( SceneEditorSession.Active.UndoScope( "Create Object" ).WithGameObjectCreations().Push() )
        {
            var go = CreateGameObjectOfType( requestedType, desiredName );
            go.Parent = parent;
            if ( !parent.IsValid() )
            {
                go.LocalTransform = new Transform();
            }

            go.MakeNameUnique();
            SceneEditorSession.Active.Selection.Set( go );
            SceneEditorSession.Active.HasUnsavedChanges = true;

            return new Dictionary<string, object?>
            {
                ["object"] = SerializeGameObject( go )
            };
        }
    }

    private static Dictionary<string, object?> DestroyObject( GameObject target )
    {
        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Destroy Object" ).WithGameObjectDestructions( target ).Push() )
        {
            var payload = SerializeGameObjectSummary( target );
            target.Destroy();
            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["object"] = payload,
                ["deleted"] = true
            };
        }
    }

    private static Dictionary<string, object?> DuplicateObject( GameObject target )
    {
        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Duplicate Object" ).WithGameObjectCreations().Push() )
        {
            var clone = target.Clone();
            clone.WorldTransform = target.WorldTransform;
            if ( target.Parent.IsValid() )
            {
                target.AddSibling( clone, false );
            }

            SceneEditorSession.Active.Selection.Set( clone );
            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["source"] = SerializeGameObjectSummary( target ),
                ["object"] = SerializeGameObject( clone )
            };
        }
    }

    private static Dictionary<string, object?> SetObjectTransform( GameObject target, Dictionary<string, JsonElement> args )
    {
        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Set Object Transform" ).WithGameObjectChanges( target, GameObjectUndoFlags.Properties ).Push() )
        {
            if ( args.TryGetValue( "position", out var positionValue ) && TryReadVector3( positionValue, out var position ) )
            {
                target.LocalPosition = position;
            }

            if ( args.TryGetValue( "rotation", out var rotationValue ) && TryReadVector3( rotationValue, out var rotationAngles ) )
            {
                target.LocalRotation = Rotation.From( rotationAngles.x, rotationAngles.y, rotationAngles.z );
            }

            if ( args.TryGetValue( "scale", out var scaleValue ) && TryReadVector3( scaleValue, out var scale ) )
            {
                target.LocalScale = scale;
            }

            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["object"] = SerializeGameObject( target )
            };
        }
    }

    private static Dictionary<string, object?> SetObjectParent( GameObject target, GameObject parent )
    {
        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Set Object Parent" ).WithGameObjectChanges( new[] { target, parent }, GameObjectUndoFlags.Properties ).Push() )
        {
            target.SetParent( parent, true );
            SceneEditorSession.Active.Selection.Set( target );
            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["object"] = SerializeGameObject( target )
            };
        }
    }

    private static Dictionary<string, object?> SetObjectActive( GameObject target, bool active )
    {
        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Set Object Active" ).WithGameObjectChanges( target, GameObjectUndoFlags.Properties ).Push() )
        {
            target.Active = active;
            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["object"] = SerializeGameObject( target )
            };
        }
    }

    private static Dictionary<string, object?> SetObjectProperty( GameObject target, string propertyPath, JsonElement rawValue )
    {
        if ( string.IsNullOrWhiteSpace( propertyPath ) )
            throw new InvalidOperationException( "Argument 'property' is required." );

        using var scope = SceneEditorSession.Scope();
        using ( SceneEditorSession.Active.UndoScope( "Set Object Property" ).WithGameObjectChanges( target, GameObjectUndoFlags.All ).Push() )
        {
            var (propertyTarget, property) = ResolveEditableProperty( target, propertyPath );
            property.SetValue( propertyTarget, DeserializeValue( rawValue, property.PropertyType ) );
            SceneEditorSession.Active.HasUnsavedChanges = true;
            return new Dictionary<string, object?>
            {
                ["object"] = SerializeGameObject( target ),
                ["property"] = propertyPath
            };
        }
    }

    private static Dictionary<string, object?> SelectObject( GameObject target )
    {
        SceneEditorSession.Active.Selection.Set( target );
        return new Dictionary<string, object?>
        {
            ["items"] = GetSelectionEntries()
        };
    }

    private static GameObject CreateGameObjectOfType( string requestedType, string desiredName )
    {
        var normalized = requestedType?.Trim().ToLowerInvariant() ?? string.Empty;
        var go = new GameObject( true, desiredName );
        switch ( normalized )
        {
            case "":
            case "empty":
                break;
            case "terrain":
                go.Components.Create<Terrain>();
                break;
            case "camera":
                go.Components.Create<CameraComponent>();
                break;
            case "directional_light":
            case "directionallight":
                go.Components.Create<DirectionalLight>();
                break;
            case "point_light":
            case "pointlight":
                go.Components.Create<PointLight>();
                break;
            default:
                throw new InvalidOperationException( $"Unsupported S&box node_type: {requestedType}" );
        }

        return go;
    }

    private static (object Target, PropertyInfo Property) ResolveEditableProperty( GameObject target, string propertyPath )
    {
        object propertyTarget = target;
        var propertyName = propertyPath.Trim();

        if ( propertyName.Contains( '.' ) )
        {
            var parts = propertyName.Split( '.', 2, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries );
            if ( parts.Length != 2 )
                throw new InvalidOperationException( $"Invalid property path: {propertyPath}" );

            if ( !string.Equals( parts[0], "GameObject", StringComparison.OrdinalIgnoreCase ) )
            {
                propertyTarget = target.Components
                    .GetAll()
                    .FirstOrDefault( component => string.Equals( component.GetType().Name, parts[0], StringComparison.OrdinalIgnoreCase )
                        || string.Equals( component.GetType().FullName, parts[0], StringComparison.OrdinalIgnoreCase ) )
                    ?? throw new InvalidOperationException( $"Unable to find component '{parts[0]}' on {target.Name}." );
            }

            propertyName = parts[1];
        }

        var property = propertyTarget.GetType().GetProperty( propertyName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.IgnoreCase )
            ?? throw new InvalidOperationException( $"Unable to find property '{propertyName}' on {propertyTarget.GetType().Name}." );
        if ( !property.CanWrite )
            throw new InvalidOperationException( $"Property '{propertyName}' is read-only." );
        return (propertyTarget, property);
    }

    private static object? DeserializeValue( JsonElement value, Type targetType )
    {
        if ( targetType == typeof( string ) )
            return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
        if ( targetType == typeof( bool ) )
            return value.ValueKind == JsonValueKind.True || (value.ValueKind == JsonValueKind.False ? false : bool.Parse( value.ToString() ));
        if ( targetType == typeof( Vector3 ) && TryReadVector3( value, out var vector ) )
            return vector;
        if ( targetType == typeof( Angles ) && TryReadVector3( value, out var angles ) )
            return new Angles( angles.x, angles.y, angles.z );
        if ( targetType == typeof( Rotation ) && TryReadVector3( value, out var rotationAngles ) )
            return Rotation.From( rotationAngles.x, rotationAngles.y, rotationAngles.z );
        if ( targetType.IsEnum )
            return Enum.Parse( targetType, value.ValueKind == JsonValueKind.String ? value.GetString() ?? string.Empty : value.ToString(), ignoreCase: true );
        if ( targetType == typeof( int ) )
            return value.GetInt32();
        if ( targetType == typeof( long ) )
            return value.GetInt64();
        if ( targetType == typeof( float ) )
            return (float)value.GetDouble();
        if ( targetType == typeof( double ) )
            return value.GetDouble();
        return JsonSerializer.Deserialize( value.GetRawText(), targetType, JsonOptions );
    }

    private static bool TryReadVector3( JsonElement value, out Vector3 vector )
    {
        vector = default;
        if ( value.ValueKind != JsonValueKind.Array )
            return false;
        var values = value.EnumerateArray().Take( 3 ).Select( static element => (float)element.GetDouble() ).ToArray();
        if ( values.Length != 3 )
            return false;
        vector = new Vector3( values[0], values[1], values[2] );
        return true;
    }

    private static Dictionary<string, object?> SerializeHierarchyNode( GameObject go, int depth )
    {
        var payload = SerializeGameObjectSummary( go );
        payload["children"] = depth <= 1
            ? new List<Dictionary<string, object?>>()
            : go.Children
                .OfType<GameObject>()
                .Where( static child => child.IsValid() )
                .Select( child => SerializeHierarchyNode( child, depth - 1 ) )
                .ToList();
        return payload;
    }

    private static Dictionary<string, object?> SerializeGameObjectSummary( GameObject go )
    {
        return new Dictionary<string, object?>
        {
            ["id"] = go.Id.ToString(),
            ["name"] = go.Name,
            ["type"] = go.GetType().Name,
            ["path"] = BuildObjectPath( go ),
            ["active"] = go.Active,
            ["enabled"] = go.Enabled,
            ["childCount"] = go.Children.Count,
            ["localPosition"] = SerializeVector3( go.LocalPosition ),
            ["localRotation"] = SerializeAngles( go.LocalRotation.Angles() ),
            ["localScale"] = SerializeVector3( go.LocalScale ),
            ["worldPosition"] = SerializeVector3( go.WorldPosition ),
            ["worldRotation"] = SerializeAngles( go.WorldRotation.Angles() ),
            ["worldScale"] = SerializeVector3( go.WorldScale ),
            ["parentId"] = go.Parent?.Id.ToString() ?? string.Empty,
            ["parentPath"] = go.Parent.IsValid() && go.Parent is not Scene ? BuildObjectPath( go.Parent ) : string.Empty
        };
    }

    private static Dictionary<string, object?> SerializeGameObject( GameObject go )
    {
        var payload = SerializeGameObjectSummary( go );
        payload["components"] = go.Components
            .GetAll()
            .Where( static component => component.IsValid() )
            .Select( component => component.GetType().Name )
            .Distinct()
            .OrderBy( static name => name, StringComparer.OrdinalIgnoreCase )
            .ToList();
        return payload;
    }

    private static List<float> SerializeVector3( Vector3 value ) => new() { value.x, value.y, value.z };

    private static List<float> SerializeAngles( Angles value ) => new() { value.pitch, value.yaw, value.roll };

    private static bool MatchesObjectFilter( GameObject go, string filter, string name, string typeName )
    {
        if ( !string.IsNullOrWhiteSpace( name ) && !go.Name.Contains( name.Trim(), StringComparison.OrdinalIgnoreCase ) )
            return false;
        if ( !string.IsNullOrWhiteSpace( typeName ) &&
             !string.Equals( go.GetType().Name, typeName.Trim(), StringComparison.OrdinalIgnoreCase ) &&
             !string.Equals( go.GetType().FullName, typeName.Trim(), StringComparison.OrdinalIgnoreCase ) )
            return false;
        if ( string.IsNullOrWhiteSpace( filter ) )
            return true;
        var token = filter.Trim();
        return BuildObjectPath( go ).Contains( token, StringComparison.OrdinalIgnoreCase )
            || go.Name.Contains( token, StringComparison.OrdinalIgnoreCase )
            || go.GetType().Name.Contains( token, StringComparison.OrdinalIgnoreCase );
    }

    private static string BuildObjectPath( GameObject go )
    {
        var segments = new Stack<string>();
        GameObject current = go;
        while ( current.IsValid() && current is not Scene )
        {
            segments.Push( current.Name );
            current = current.Parent;
        }
        return string.Join( "/", segments );
    }

    private static GameObject ResolveGameObjectFromArgs( Dictionary<string, JsonElement> args )
    {
        var token = GetArgString( args, "path" );
        if ( string.IsNullOrWhiteSpace( token ) )
            token = GetArgString( args, "name" );
        if ( string.IsNullOrWhiteSpace( token ) )
            throw new InvalidOperationException( "Argument 'path' or 'name' is required." );
        return ResolveGameObject( token );
    }

    private static GameObject GetRequiredGameObjectArg( Dictionary<string, JsonElement> args, string key )
    {
        var token = GetArgString( args, key );
        if ( string.IsNullOrWhiteSpace( token ) )
            throw new InvalidOperationException( $"Argument '{key}' is required." );
        return ResolveGameObject( token );
    }

    private static GameObject? GetOptionalGameObjectArg( Dictionary<string, JsonElement> args, string key )
    {
        var token = GetArgString( args, key );
        return string.IsNullOrWhiteSpace( token ) ? null : ResolveGameObject( token );
    }

    private static GameObject ResolveGameObject( string token )
    {
        var scene = RequireActiveScene();
        var normalized = token.Trim();
        Guid parsedId;

        var byId = Guid.TryParse( normalized, out parsedId )
            ? EnumerateGameObjects( scene ).FirstOrDefault( go => go.Id == parsedId )
            : null;
        if ( byId is not null )
            return byId;

        var byPath = EnumerateGameObjects( scene )
            .FirstOrDefault( go => string.Equals( BuildObjectPath( go ), normalized, StringComparison.OrdinalIgnoreCase ) );
        if ( byPath is not null )
            return byPath;

        var byName = EnumerateGameObjects( scene )
            .FirstOrDefault( go => string.Equals( go.Name, normalized, StringComparison.OrdinalIgnoreCase ) );
        if ( byName is not null )
            return byName;

        throw new InvalidOperationException( $"Unable to find S&box object '{token}' in the active scene." );
    }

    private static string NormalizeSceneAssetPath( string relativePath )
    {
        var normalized = relativePath.Replace( '\\', '/' ).Trim();
        if ( string.IsNullOrWhiteSpace( normalized ) )
            throw new InvalidOperationException( "Scene path is required." );
        if ( !normalized.EndsWith( ".scene", StringComparison.OrdinalIgnoreCase ) )
            throw new InvalidOperationException( $"Expected a .scene path: {relativePath}" );
        return normalized;
    }

    private static SceneFile ResolveSceneFile( string relativePath )
    {
        var asset = AssetSystem.FindByPath( relativePath )
            ?? throw new InvalidOperationException( $"Unable to find scene asset '{relativePath}'." );
        var sceneFile = asset.LoadResource<SceneFile>();
        if ( sceneFile is null )
            throw new InvalidOperationException( $"Asset '{relativePath}' is not a scene file." );
        return sceneFile;
    }

    private static List<Dictionary<string, object?>> EnumerateSceneEntries( string filter, int count )
    {
        return EnumerateSceneFiles()
            .Where( path => MatchesFilter( path, filter ) )
            .Take( Math.Max( count, 1 ) )
            .Select( path => DescribePath( path ) )
            .ToList();
    }

    private static List<Dictionary<string, object?>> EnumerateAssetEntries( string filter, int count )
    {
        return EnumerateAssetFiles()
            .Where( path => MatchesFilter( path, filter ) )
            .Take( Math.Max( count, 1 ) )
            .Select( path => DescribePath( path ) )
            .ToList();
    }

    private static IEnumerable<string> EnumerateSceneFiles()
    {
        return EnumerateProjectFiles()
            .Where( path => path.EndsWith( ".scene", StringComparison.OrdinalIgnoreCase ) );
    }

    private static IEnumerable<string> EnumerateAssetFiles()
    {
        foreach ( var root in EnumerateAssetRoots() )
        {
            if ( !Directory.Exists( root ) )
                continue;

            foreach ( var path in Directory.EnumerateFiles( root, "*", SearchOption.AllDirectories ) )
            {
                if ( IsIgnoredPath( path ) )
                    continue;
                yield return path;
            }
        }
    }

    private static IEnumerable<string> EnumerateProjectFiles()
    {
        var projectRoot = RequireProjectRoot();
        foreach ( var path in Directory.EnumerateFiles( projectRoot, "*", SearchOption.AllDirectories ) )
        {
            if ( IsIgnoredPath( path ) )
                continue;
            yield return path;
        }
    }

    private static IEnumerable<string> EnumerateAssetRoots()
    {
        var projectRoot = RequireProjectRoot();
        yield return Path.Combine( projectRoot, "Assets" );
        var libraries = Path.Combine( projectRoot, "Libraries" );
        if ( Directory.Exists( libraries ) )
        {
            foreach ( var libraryDir in Directory.EnumerateDirectories( libraries ) )
            {
                yield return Path.Combine( libraryDir, "Assets" );
            }
        }
    }

    private static bool IsIgnoredPath( string path )
    {
        var lowered = path.Replace( '\\', '/' ).ToLowerInvariant();
        return lowered.Contains( "/.qq/" ) || lowered.Contains( "/bin/" ) || lowered.Contains( "/obj/" ) || lowered.Contains( "/.git/" );
    }

    private static bool MatchesFilter( string path, string filter )
    {
        if ( string.IsNullOrWhiteSpace( filter ) )
            return true;
        return NormalizeProjectRelative( path ).Contains( filter.Trim(), StringComparison.OrdinalIgnoreCase );
    }

    private static Dictionary<string, object?> InspectFile( string relativePath, bool sceneOnly )
    {
        var absolute = ResolveProjectPath( relativePath, requireScene: sceneOnly, requireExisting: true );
        return DescribePath( absolute );
    }

    private static Dictionary<string, object?> CreateDirectory( string relativePath )
    {
        var absolute = ResolveProjectPath( relativePath, requireScene: false, requireExisting: false, allowDirectory: true );
        Directory.CreateDirectory( absolute );
        return new Dictionary<string, object?>
        {
            ["path"] = NormalizeProjectRelative( absolute ),
            ["exists"] = true,
            ["kind"] = "directory"
        };
    }

    private static Dictionary<string, object?> DuplicateFile( string sourcePath, string targetPath, bool sceneOnly )
    {
        var source = ResolveProjectPath( sourcePath, requireScene: sceneOnly, requireExisting: true );
        var target = ResolveProjectPath( targetPath, requireScene: sceneOnly, requireExisting: false );
        EnsureParentDirectory( target );
        File.Copy( source, target, false );
        return new Dictionary<string, object?>
        {
            ["source"] = NormalizeProjectRelative( source ),
            ["target"] = NormalizeProjectRelative( target )
        };
    }

    private static Dictionary<string, object?> RenameFile( string sourcePath, string targetPath, bool sceneOnly )
    {
        var source = ResolveProjectPath( sourcePath, requireScene: sceneOnly, requireExisting: true );
        var target = ResolveProjectPath( targetPath, requireScene: sceneOnly, requireExisting: false );
        EnsureParentDirectory( target );
        File.Move( source, target );
        return new Dictionary<string, object?>
        {
            ["source"] = NormalizeProjectRelative( source ),
            ["target"] = NormalizeProjectRelative( target )
        };
    }

    private static Dictionary<string, object?> DeleteFile( string relativePath, bool sceneOnly )
    {
        var absolute = ResolveProjectPath( relativePath, requireScene: sceneOnly, requireExisting: true );
        File.Delete( absolute );
        return new Dictionary<string, object?>
        {
            ["path"] = NormalizeProjectRelative( absolute ),
            ["deleted"] = true
        };
    }

    private static Dictionary<string, object?> DescribePath( string absolutePath )
    {
        var file = new FileInfo( absolutePath );
        return new Dictionary<string, object?>
        {
            ["path"] = NormalizeProjectRelative( absolutePath ),
            ["name"] = file.Name,
            ["extension"] = file.Extension,
            ["sizeBytes"] = file.Exists ? file.Length : 0,
            ["modifiedAtUtc"] = file.Exists ? file.LastWriteTimeUtc.ToString( "O" ) : "",
            ["kind"] = string.Equals( file.Extension, ".scene", StringComparison.OrdinalIgnoreCase ) ? "scene" : "asset"
        };
    }

    private static string GetRequiredPathArg( Dictionary<string, JsonElement> args, string key )
    {
        var value = GetArgString( args, key );
        if ( string.IsNullOrWhiteSpace( value ) )
            throw new InvalidOperationException( $"Argument '{key}' is required." );
        return value;
    }

    private static string GetArgString( Dictionary<string, JsonElement> args, string key )
    {
        if ( !args.TryGetValue( key, out var value ) )
            return string.Empty;
        return value.ValueKind == JsonValueKind.String ? value.GetString() ?? string.Empty : value.ToString();
    }

    private static int GetArgInt( Dictionary<string, JsonElement> args, string key, int fallback )
    {
        if ( !args.TryGetValue( key, out var value ) )
            return fallback;
        if ( value.ValueKind == JsonValueKind.Number && value.TryGetInt32( out var intValue ) )
            return intValue;
        return int.TryParse( value.ToString(), out var parsed ) ? parsed : fallback;
    }

    private static bool GetArgBool( Dictionary<string, JsonElement> args, string key, bool fallback )
    {
        if ( !args.TryGetValue( key, out var value ) )
            return fallback;
        if ( value.ValueKind == JsonValueKind.True )
            return true;
        if ( value.ValueKind == JsonValueKind.False )
            return false;
        return bool.TryParse( value.ToString(), out var parsed ) ? parsed : fallback;
    }

    private static JsonElement GetRequiredArg( Dictionary<string, JsonElement> args, string key )
    {
        if ( !args.TryGetValue( key, out var value ) )
            throw new InvalidOperationException( $"Argument '{key}' is required." );
        return value;
    }

    private static string ResolveProjectPath(
        string relativePath,
        bool requireScene,
        bool requireExisting,
        bool allowDirectory = false
    )
    {
        var projectRoot = RequireProjectRoot();
        var candidate = relativePath.Replace( '\\', '/' ).Trim();
        if ( string.IsNullOrWhiteSpace( candidate ) )
            throw new InvalidOperationException( "Path is required." );

        var absolute = Path.GetFullPath( Path.Combine( projectRoot, candidate ) );
        var rootWithSeparator = projectRoot.EndsWith( Path.DirectorySeparatorChar ) ? projectRoot : projectRoot + Path.DirectorySeparatorChar;
        if ( !absolute.StartsWith( rootWithSeparator, StringComparison.OrdinalIgnoreCase ) && !string.Equals( absolute, projectRoot, StringComparison.OrdinalIgnoreCase ) )
            throw new InvalidOperationException( $"Path escapes project root: {relativePath}" );

        if ( requireScene && !absolute.EndsWith( ".scene", StringComparison.OrdinalIgnoreCase ) )
            throw new InvalidOperationException( $"Expected a .scene path: {relativePath}" );

        if ( requireExisting )
        {
            if ( allowDirectory )
            {
                if ( !Directory.Exists( absolute ) && !File.Exists( absolute ) )
                    throw new InvalidOperationException( $"Path does not exist: {relativePath}" );
            }
            else if ( !File.Exists( absolute ) )
            {
                throw new InvalidOperationException( $"File does not exist: {relativePath}" );
            }
        }
        else if ( File.Exists( absolute ) || Directory.Exists( absolute ) )
        {
            throw new InvalidOperationException( $"Target already exists: {relativePath}" );
        }

        return absolute;
    }

    private static string NormalizeProjectRelative( string absolutePath )
    {
        var projectRoot = RequireProjectRoot();
        return Path.GetRelativePath( projectRoot, absolutePath ).Replace( '\\', '/' );
    }

    private static void EnsureParentDirectory( string absolutePath )
    {
        var parent = Path.GetDirectoryName( absolutePath );
        if ( string.IsNullOrEmpty( parent ) )
            return;
        Directory.CreateDirectory( parent );
    }

    private static string RequireProjectRoot()
    {
        if ( string.IsNullOrEmpty( ProjectRoot ) )
            throw new InvalidOperationException( "Project root has not been resolved." );
        return ProjectRoot;
    }

    private static string FindProjectFile( string projectRoot )
    {
        var hidden = Path.Combine( projectRoot, ".sbproj" );
        if ( File.Exists( hidden ) )
            return ".sbproj";
        var visible = Directory.EnumerateFiles( projectRoot, "*.sbproj", SearchOption.TopDirectoryOnly ).FirstOrDefault();
        return visible is null ? string.Empty : Path.GetFileName( visible );
    }

    private static void WriteConsole( string eventName, string message, Dictionary<string, object?>? data = null )
    {
        if ( string.IsNullOrEmpty( ConsoleFile ) )
            return;

        var payload = new Dictionary<string, object?>
        {
            ["event"] = eventName,
            ["message"] = message,
            ["time"] = DateTimeOffset.UtcNow.ToString( "O" )
        };

        if ( data is not null )
            payload["data"] = data;

        File.AppendAllText( ConsoleFile, JsonSerializer.Serialize( payload ) + Environment.NewLine );
    }

    private static ResponsePayload Ok( string message, Dictionary<string, object?> data )
    {
        return new ResponsePayload
        {
            Ok = true,
            Message = message,
            Data = data
        };
    }

    private static ResponsePayload Error( string category, string message )
    {
        return new ResponsePayload
        {
            Ok = false,
            Category = category,
            Message = message,
            Data = new Dictionary<string, object?>()
        };
    }

    private static void SafeDelete( string path )
    {
        try
        {
            File.Delete( path );
        }
        catch
        {
        }
    }

    private sealed class RequestPayload
    {
        public string RequestId { get; set; } = string.Empty;
        public string Command { get; set; } = string.Empty;
        public Dictionary<string, JsonElement>? Args { get; set; }
    }

    private sealed class ResponsePayload
    {
        public bool Ok { get; set; }
        public string Message { get; set; } = string.Empty;
        public string? Category { get; set; }
        public Dictionary<string, object?> Data { get; set; } = new();
    }
}
