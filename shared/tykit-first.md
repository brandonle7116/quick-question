# Tykit-First Mindset (for agents)

**Default heuristic in a Unity project**: when you need to *understand current runtime state*, **try tykit first, read code second**. Reading source tells you what *could* happen; tykit shows you what *is* happening.

This doc complements [`tykit-reference.md`](./tykit-reference.md) (the command map) — read that for *how*, read this for *when*.

## The decision rule

```
You have a question about Unity state or behavior.
   ↓
Is it about current runtime/scene/component values?
   ├─ YES  → tykit first (find / inspect / get-properties / get-field / get-array)
   │         Code reading is a fallback, not the default.
   │
   └─ NO   → Is it about how code is structured / what to write?
              ├─ YES → read code, write code
              └─ Is it about validating an in-progress hypothesis?
                  └─ tykit first (set-field / call-method / button-click → observe)
```

## Concrete scenarios where tykit beats code-reading

Each row: **what users typically ask** → **what agents typically do** → **what tykit does in 1-2 calls**.

| User question | Lazy/wrong instinct | Tykit-first (10–60 sec) |
|---|---|---|
| "Why is this NPC stuck?" | Read AI controller code → guess at state | `find {name:"NPC_X"}` → `get-field {component:"AIController",field:"_currentState"}` → see actual value |
| "What's the value of property Y on prefab Z?" | Open .prefab YAML in text editor | `find-assets {type:"Prefab",name:"Z"}` → `load-asset` → `get-properties {structured:true}` |
| "Is this UI button wired correctly?" | Trace OnClick listeners in code | `find {type:"Button",name:"X"}` → `button-click` → `console` to see runtime logs |
| "Which factions exist in the current save?" | Search for FactionRegistry usages | `find {type:"FactionRegistry"}` → `get-array {property:"_factions"}` |
| "How many ships are in the harbor right now?" | Read spawn logic + count call sites | `find {type:"Ship",includeInactive:false}` → count results |
| "This component should have value 5 but I see 3" | Re-read every assignment in code | `get-properties` confirms in 1 second; then bisect why |
| "If I change field Y to 10, does the bug go away?" | Edit code → recompile → run | `set-field` → observe → no recompile |
| "What does this AnimationCurve actually look like?" | Inspect the .anim file | `get-properties {structured:true}` returns the curve points |
| "Is method X on this MonoBehaviour even being called?" | Add Debug.Log → recompile → run | `call-method` to invoke directly + observe; or set a field then observe via `get-field` |
| "What's in this Container right now?" | Read inventory code, guess from save data | `get-array {property:"_items"}` |
| "Did the player's faction reputation change?" | Read save file | `find {type:"FactionRegistry"}` → `get-field` |
| "Does this raycast actually hit the wall?" | Mental simulation | `raycast {origin:[...],direction:[...]}` → see actual hit |
| "What's currently selected in the editor?" | (No good code path) | `get-selection` |
| "I edited a serialized field on a prefab, did it propagate?" | Check version control | `find` instances → `get-properties` |

## When NOT to use tykit

Tykit is the wrong tool for:

| Task | Use this instead |
|---|---|
| Adding new features / refactoring | Write code, compile, test |
| Anything that needs to be in version control | Write code (tykit doesn't persist scene changes until `save-scene`) |
| Anything that needs to be in CI/build | Write code, write tests |
| Bulk asset operations (100+ items) | Write a small Editor script + `menu` invoke |
| Operations on private static fields | Use the test framework's reflection helpers, not tykit |
| Anything in a build (non-editor) | tykit only works in the Unity Editor |
| When the code answer is obvious from a 30-line file | Just read the code; don't be dogmatic |

## The "code-reading trap"

When you find yourself doing **any** of these in a Unity project, stop and ask: *"Could tykit answer this in fewer steps?"*

- ❌ Reading a `.prefab` YAML to find a serialized value
- ❌ Tracing UnityEvent listeners across multiple files to verify wiring
- ❌ Mentally simulating Update() behavior to guess what state a component is in
- ❌ Adding `Debug.Log` then recompiling just to see one value
- ❌ Searching for `[SerializeField]` field assignments to find "the real" default
- ❌ Reading a save file to inspect runtime state
- ❌ Guessing whether a coroutine is currently running

In each case, tykit answers the question in 1–3 commands, with the **actual** runtime value, not the value you derived from reading.

## The "state vs structure" distinction

This is the core mental model:

| Want to know about | Best tool |
|---|---|
| **State** (what's the value, what's running, what's selected) | **tykit** |
| **Structure** (how is the code organized, what calls what, what's the type hierarchy) | **read source / Grep / Glob** |
| **Behavior** (what does this method do step by step) | **read source first, then tykit to verify** |
| **History** (who changed this, when, why) | **`git log` / `git blame`** |

When state and structure are tangled (e.g. "what does this state machine do when X happens"), the right move is usually: read source to find the relevant code paths, then use tykit to *test the hypothesis* by setting state and observing.

## Recovery is also tykit

If Unity hangs (modal dialog / domain reload / package resolve), **don't ask the user to click**. Use:

1. `unity_main_thread_health` → diagnose
2. `unity_focus_window` → unstick (Windows; ~90% of stalls)
3. `unity_dismiss_dialog` → close modal

See [`tykit-reference.md`](./tykit-reference.md#recovery-when-unity-hangs) for the full flow.

## Anti-pattern: tykit for everything

Tykit is not the answer to every question. Don't use it when:

- The code is short and the answer is obvious from reading
- You need to commit the change (tykit doesn't auto-persist)
- You need the change to survive Unity restart (tykit doesn't either)
- You'd be running 20+ commands in sequence — write a one-shot Editor script via `menu` instead

The goal is **"prefer tykit when it's faster and gives a more authoritative answer"**, not "tykit must be used for every Unity question".
