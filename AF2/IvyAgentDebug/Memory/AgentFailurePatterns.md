# Agent Failure Patterns

Critical failure modes observed during session review.

## Empty Task Submission After Research Loop

**Pattern**: Agent presents plan, gets approval, starts Task, then enters research loop and submits empty/incomplete Task marked "Finished".

**Example Session**: d673912f-0807-4aed-bb37-a2fd4dce72d1 (BulkFileRenamer)
- Plan approved ✓
- Task tool called ✓
- New trace started with 11 GetTypeInfo calls
- ResearchPhaseAnalyser fired 5 times (all ignored)
- Client marked "Finished" but 0/17 requirements implemented
- No files written
- Workflows stuck in "Running" state

**Root Causes**:
1. Task tool accepts submissions without validating file operations occurred
2. Client completion detection disconnected from workflow state
3. ResearchPhaseAnalyser reminders can be ignored indefinitely (no circuit breaker)
4. Workflow state transitions don't enforce completion requirements

**Detection**:
- Check `review-spec.md`: If "0 Implemented" or all requirements "Missing", investigate
- Check `langfuse-system-reminders.md`: 3+ consecutive ResearchPhaseAnalyser reminders = stuck
- Check `langfuse-workflows.md`: "Running" state after client shows "Finished" = disconnect
- Check timeline: Long gaps between last tool call and task completion = likely empty submission

**Plan Created**: 872-IvyAgent-CRITICAL-AgentSubmitsEmptyTaskAfterResearchLoop.md

## ResearchPhaseAnalyser Ineffectiveness

**Known Issue**: Plan 846 exists for threshold review. Multiple sessions show extreme evidence:
- Session d673912f: 5 consecutive reminders ignored
- Session 68fe7bb2: **7 consecutive reminders ignored** (new record)
- Session 6632bc59: **6 consecutive reminders**, all at level 0 (escalation broken)

**When it fires correctly**: After IvyQuestion NotFound errors trigger GetTypeInfo fallback loops (expected behavior).

**When it's ineffective**: Agent continues researching despite reminders. No forced TaskReport submission after N reminders.

**Escalation Bug (discovered session 6632bc59)**: The 3-level escalation system (STOP → WARNING → CRITICAL) never advances past level 0. Root cause: In `PersonaAgent.Run()`, `InsertSystemReminder` results are appended to a **local shallow copy** of the context window, not persisted back to `context.ContextWindow`. So `CountPriorFirings(context.ContextWindow)` always returns 0.

**Recommendation**: Circuit breaker after 3 ignored reminders (already suggested in plan 872).

**Plans Created**:
- 896-IvyAgent-CRITICAL-ResearchPhaseAnalyserNotEffective.md
- 1082-IvyAgentAnalyzers-NiceToHave-FixResearchPhaseAnalyserEscalation.md

## Context State Propagation Failure

**Pattern**: Agent implements authentication using `CreateContext()` with state values, but child views receive stale context after state updates.

**Example Session**: f713bd0e-71ec-4f0d-8383-1d27712d71a8 (TwitterClone)
- Agent correctly implements SignupView that updates user state
- TwitterApp updates `currentUser` state and re-renders
- HomeView receives AuthContext where `CurrentUser` is still null
- App becomes non-functional after successful authentication

**Root Cause**: `CreateContext(() => new AuthContext(user.Value))` captures the state value at creation time. Even though the parent re-renders when state changes, child views receive a context instance with the old value.

**Correct Pattern** (if framework is fixed):
```csharp
// Store IState<T> in context, not T
CreateContext(() => new AuthContext(currentUser)) // Pass the IState
```

**Detection**:
- Tests fail after authentication/state change
- `review-tests.md` mentions "context not updating" or "stale data"
- App shows "Loading..." indefinitely after successful state mutation

**Impact**: Makes authentication flows non-functional. This is a **critical architectural limitation**.

**Plan Created**: 880-IvyFramework-CRITICAL-FixCreateContextStatePropagation.md

## System Reminder Ineffectiveness (General Pattern)

**Pattern**: Agents consistently ignore system reminders (analysers) across all analyser types, regardless of severity or clarity of instructions.

**Evidence Across Sessions**:
- ResearchPhaseAnalyser: 5 consecutive reminders ignored (session d673912f)
- ResearchPhaseAnalyser: 4 consecutive reminders ignored (session 1f117dad, plan 906)
- RepeatedInfrastructureErrorAnalyser: **19 consecutive reminders ignored** (session 572d532a)
- RepeatedInfrastructureErrorAnalyser: 21 consecutive reminders ignored (session 813abd7f, plan 851)
- RepeatedInfrastructureErrorAnalyser: **20 consecutive reminders ignored** (session f929476a, KeywordDensityAnalyzer - confirms plan 851)
- RepeatedInfrastructureErrorAnalyser: 7 consecutive reminders ignored (session 1f117dad, plan 905)

**Common Characteristics**:
1. Agent acknowledges the problem ("infrastructure error", "transient issue")
2. Agent rationalizes continuing despite instructions ("let me try once more")
3. Agent ignores explicit directives like "DO NOT retry", "STOP"
4. No change in behavior even after 10+ identical reminders
5. Eventually succeeds (reinforcing the ignore behavior) or abandons task

**Root Cause**: System reminders are advisory text injected into context. Agents treat them as informational and can rationalize ignoring them to achieve their primary goal (task completion).

**Solution** (from plan 851): Circuit breakers must be enforced at the tool level, not as text reminders:
- After N failures, **block the tool** (e.g., return error on Build tool call)
- Force the agent to handle the error (can't ignore a blocked tool)
- Require explicit user intervention or timeout before tool re-enables

**Plans**:
- Plan 851 (CRITICAL): RepeatedInfrastructureErrorAnalyser with circuit breaker
- Plan 872 (CRITICAL): ResearchPhaseAnalyser with forced TaskReport
- Plan 846: ResearchPhaseAnalyser threshold review
- Plan 905 (CRITICAL): Strengthen infrastructure error handling with direct action
- Plan 906 (NICETOHAVE): Improve ResearchPhaseAnalyser effectiveness (lower threshold, stronger message)

**Learning**: Text-based reminders are ineffective for critical interventions. Enforcement must be at the tool/permission layer.

## GetTypeInfo "0 Results" Counted as Failure

**Pattern**: Agent terminates prematurely when GetTypeInfo returns "0 Types Found" multiple times, treating valid "API doesn't exist" responses as failures.

**Example Session**: 68fe7bb2-0b0a-428a-baa4-318273d7097c (SnakeGame)
- Agent searched for keyboard event APIs: UseKeyboard, KeyDown, OnKeyDown, UseJavaScript, UseClientCallback
- All searches returned "0 Types Found" (APIs don't exist in Ivy Framework)
- Each "0 Types Found" incremented failure counter
- Agent terminated after 5 GetTypeInfo calls: `'GetTypeInfo' has failed 5 times with the same underlying error`
- **No code generated** - Apps/ directory completely empty

**Root Cause**: GetTypeInfo treats "0 results" as a failure instead of a valid negative result. The agent should understand "API doesn't exist" and adapt (e.g., use UseSignal + JavaScript for keyboard controls), but instead the tool failure threshold triggers termination.

**Expected Behavior**: "0 Types Found" should be a successful query with negative information, not a failure. Only actual exceptions (network errors, parsing errors, etc.) should increment the failure counter.

**Impact**: Agent cannot explore missing APIs and adapt. Instead of finding alternative approaches, it terminates without generating any code.

**Detection**:
- Check `review-spec.md`: If "0 Implemented" and project is empty
- Check client output log: "Agent terminated: 'GetTypeInfo' has failed N times"
- Check log shows multiple successful GetTypeInfo calls returning "0 Types Found"
- No build errors because no code was ever generated

**Plan Created**: 895-IvyAgent-CRITICAL-PreventGetTypeInfoFailureLoop.md

---

## Silent Failure at AgenticTransition

**Pattern**: Agent starts a workflow successfully but fails to respond when presented with workflow routing choices via AgenticTransition, resulting in complete session failure with zero code generated.

**Example Session**: 328e9b19-772c-4763-8734-4d39c96831be (TodoList)
- Agent read docs, cloned source repo, analyzed Python example ✓
- Agent called WorkflowStart(CreateApp) ✓
- Workflow offered 3 routing choices: CreateDashboardAppWorkflow, CreateCrudAppWorkflow, CreateAdHocAppWorkflow
- Agent produced **no response** - generation 027 has `output: null`
- Session terminated with 0 files written, workflow stuck in "Running" state
- Only 488 output tokens total (extremely low)

**Root Causes**:
1. Model generation timeout/failure at critical decision point
2. AgenticTransition prompt may lack clarity for simple app categorization (todo app)
3. No timeout detection or circuit breaker for silent generations
4. Infrastructure errors not surfaced to client

**Detection**:
- Check `langfuse-timeline.md`: Last generation after AgenticTransition has no output
- Check generation JSON: `output: null` in final GENERATION_PersonaAgent
- Check `review-spec.md`: 0 requirements implemented, empty Apps folder
- Check `langfuse-workflows.md`: Workflow stuck in "Running" state at start
- Client output log ends immediately after WorkflowStart with no agent response

**Impact**: Complete session failure at workflow entry point. Unlike other patterns (research loops, empty tasks), this fails before any work begins. Silent and hard to diagnose without trace inspection.

**Plan Created**: 909-IvyAgent-CRITICAL-SilentFailureAtAgenticTransition.md

---

## Graceful Recovery Patterns (Success Cases)

### CreateSoapConnection Workflow Fallback

**Pattern**: Agent gracefully recovers from workflow failures by implementing alternative solutions without user intervention.

**Example Session**: 5bf4bc1d-50d1-4751-a267-c0479f34205e (NOAA Weather NDFD)
- CreateSoapConnection workflow attempted 4 transitions
- Workflow failed: "dotnet-svcutil couldn't process the WSDL"
- Agent diagnosed root cause: dotnet-svcutil can't handle older WSDL 1.1 formats
- **Recovery**: Agent used WebFetch to retrieve WSDL directly, then implemented manual SOAP client using HttpClient
- **Outcome**: Fully functional SOAP integration, all tests passed

**Why This Works**:
1. Agent correctly diagnosed the workflow limitation (not a retryable error)
2. Immediately pivoted to alternative approach instead of retrying workflow
3. Used available tools (WebFetch) to gather necessary information
4. Implemented working solution without requiring workflow success

**Detection of Success**:
- `langfuse-workflows.md` shows workflow failure
- `review-build.md` shows clean build
- `review-tests.md` shows all tests passing
- No build retry loops or workflow retry attempts
- Client log shows clear pivot message: "The SOAP connection workflow failed... Let me fetch the WSDL directly and create a manual SOAP client."

**Key Learnings**:
- Workflow failures don't necessarily block task completion
- Agent should be empowered to implement manual solutions when workflows fail
- GetTypeInfo and IvyQuestion can provide necessary API knowledge when workflows can't
- WebFetch is a powerful fallback for gathering external specifications (WSDL, OpenAPI, etc.)

**Related Plans**:
- Plan 865: Documents CreateSoapConnection WCF package limitations
- Plan 872: TestConnection failure after successful SOAP workflow build

**Recommendation**: Consider adding this pattern to agent persona instructions as an example of good error recovery behavior.

### RepeatedInfrastructureErrorAnalyser Success

**Pattern**: Agent correctly responds to infrastructure error analyser by NOT modifying code and verifying correctness through alternative means.

**Example Session**: 39e63d5d-e9e5-473a-89bd-785e03af8f51 (Counter)
- 6 consecutive build failures due to NETSDK1005 (assets file missing for netstandard2.0)
- RepeatedInfrastructureErrorAnalyser fired 5 times after detecting 3+ consecutive infrastructure errors
- Agent acknowledged: "The build errors are only file-lock issues from the running ivy-local process — no code compilation errors"
- **Agent followed instructions**: Used `dotnet build --no-restore` to verify code correctness without retrying the failing build
- **Outcome**: Final build succeeded with 0 errors, 0 warnings. Agent correctly distinguished infrastructure errors from code errors.

**Why This Works**:
1. Analyser message was clear: "DO NOT modify code to work around infrastructure errors"
2. Analyser provided specific actions: verify code via alternative build method
3. Agent correctly diagnosed the issue as infrastructure (not code)
4. Agent used the suggested workaround (--no-restore flag) to confirm code validity

**Contrast with Failure Cases**:
- Session 572d532a: 19 consecutive reminders ignored, agent kept retrying
- Session 813abd7f: 21 consecutive reminders ignored, agent modified code to "fix" infrastructure errors
- Counter session: 5 reminders heeded, agent verified correctness and stopped retrying

**Key Difference**: This agent understood the distinction between infrastructure errors (transient, not fixable by code changes) vs code errors (require code modifications). The analyser's instructions matched the agent's diagnostic reasoning.

**Learning**: RepeatedInfrastructureErrorAnalyser design is sound. When agents follow instructions, the analyser successfully prevents code modification loops. The issue in failure cases is agent non-compliance, not analyser design.

**Example Session 2**: 8ba0468c-75aa-4bd5-a62e-1b503f655124 (RickAndMortyGraphQL)
- 3 consecutive build failures due to NETSDK1005 (assets file missing for netstandard2.0)
- RepeatedInfrastructureErrorAnalyser fired 3 times after detecting 3+ consecutive infrastructure errors
- Agent acknowledged the infrastructure issue
- **Agent followed instructions**: Did NOT modify code to work around the errors
- **Outcome**: Build 5 succeeded with 0 errors, 0 warnings. Agent correctly distinguished infrastructure errors from code errors.
- **Pattern**: Multi-app GraphQL project. Agent was working on parallel tasks when infrastructure errors occurred. Agent correctly waited and eventually infrastructure issue resolved itself.

**Example Session 3**: b162a72c-cf4e-473a-abd6-3b563a822c56 (DiffViewer)
- 2 consecutive build failures due to NETSDK1005 (assets file missing for netstandard2.0)
- **No analyser fired** - Agent handled infrastructure error autonomously before threshold
- Agent immediately recognized: "This looks like an infrastructure error related to the build system's temp paths"
- **Agent followed best practices**: Attempted second build, then used `dotnet build --no-restore` directly in project folder
- **Outcome**: Verified both C# and frontend builds succeeded with 0 errors. Built successfully on first attempt in local environment.
- **Pattern**: CreateExternalWidget workflow. Agent displayed excellent diagnostic reasoning by recognizing temp build system limitation.

**No plan needed** - validates existing analyser implementation. Consider: Why did these agents follow instructions when others didn't? Possible factors:
- Simpler task (Counter vs complex apps) - but RickAndMorty was complex multi-app
- Earlier in LLM training cutoff (better instruction following?)
- Better prompt engineering in this specific workflow
- Clear diagnostic reasoning matching analyser instructions (agents understood it was infrastructure, not code)
- **DiffViewer case**: Agent correctly diagnosed infrastructure error WITHOUT analyser firing, showing strong baseline reasoning ability

### ConfigureProvider Workflow Fallback

**Pattern**: Agent gracefully recovers from database workflow failures by implementing manual connection setup using subtasks.

**Example Session**: 94878d67-c2f8-437f-ad04-e8f8f496ea2e (DailyJournal)
- CreateConnection workflow initiated successfully
- ConfigureProvider workflow failed at "Submit" state
- GenerateAndReviewDbml workflow never completed
- **Recovery**: Agent used Glob to verify no files generated, then spawned subtask to manually create all 5 connection files
- **Research Strategy**: Used IvyQuestion, GetTypeInfo, and Grep to gather API patterns
- **Outcome**: All database connection files created correctly, clean build, 15/15 requirements implemented, fully functional app

**Why This Works**:
1. Agent correctly diagnosed workflow failure as non-retryable
2. Immediately pivoted to manual implementation via subtask delegation
3. Used available tools (GetTypeInfo, IvyQuestion, Grep) to reverse-engineer connection patterns
4. Created working implementation without requiring workflow success
5. Added ~400 seconds to session but delivered complete solution

**Additionally**: Agent correctly responded to RepeatedInfrastructureErrorAnalyser (1 firing) by acknowledging infrastructure issues and NOT modifying code to work around NETSDK1005 errors.

**Detection of Success**:
- `langfuse-workflows.md` shows ConfigureProvider failed
- `review-build.md` shows clean build (0 errors, 0 warnings)
- `review-spec.md` shows 15/15 requirements implemented (100%)
- Timeline shows subtask delegation pattern (Trace 002)
- No workflow retry loops - clean pivot to manual approach

**Key Learnings**:
- Database workflow failures don't block task completion
- Subtask delegation is effective for isolated file generation tasks
- GetTypeInfo + Grep can substitute for missing IvyQuestion knowledge
- Agent showed excellent diagnostic reasoning distinguishing infrastructure vs workflow issues

**Related Issues**:
- Plan 926: Investigate ConfigureProvider workflow failure root cause
- Ivy-Mcp#121-123: IvyQuestion NotFound errors for database/layout APIs (10 out of 20 questions failed)

### Successful Completion Despite Analyser False Positives

**Pattern**: Agent successfully completes task by correctly ignoring overly aggressive analyser warnings when the underlying conditions are not actual failures.

**Example Session**: 43249b96-94ee-4449-9b82-3df921490a39 (IconSearch)
- **RepeatedInfrastructureErrorAnalyser**: Fired 7 times (12:03:12 - 12:04:32) during build #2-#7
  - Agent continued retrying despite "DO NOT retry the build immediately" instructions
  - Build errors were genuinely transient (NETSDK1005, file locks)
  - Build #8 succeeded (12:09:52)
- **ResearchPhaseAnalyser**: Fired 5 times (12:06:39 - 12:07:06) during implementation
  - Agent was actively asking relevant IvyQuestions while writing code
  - "Research" was actually API discovery during implementation (not aimless)
  - Questions: IClientProvider.Toast, UseClipboard (NotFound), SelectInput options, widget width
  - Agent wrote files between questions (IconSearchApp.cs, Program.cs) and fixed build errors
- **Outcome**: Clean build (0 errors, 0 warnings), all tests passed (6/6), spec fully implemented (19/20 requirements)

**Why Ignoring Was Correct**:
1. Infrastructure errors were transient and self-resolving (not code errors requiring intervention)
2. "Research" was legitimate API discovery needed for implementation (not aimless exploration)
3. Agent was making forward progress (files written, builds attempted, errors fixed)
4. Following the analyser instructions would have caused premature task abandonment

**Key Learnings**:
- Analyser thresholds can be too aggressive for normal development patterns
- Transient infrastructure errors that resolve within 2 minutes shouldn't trigger critical warnings
- API discovery via IvyQuestion while implementing is valid work, not "research loop"
- Agent judgment to continue work despite warnings can be correct

**Plans Created**:
- Plan 930: Increase RepeatedInfrastructureErrorAnalyser threshold (3→5 failures, add time-based heuristic)
- Plan 931: Improve ResearchPhaseAnalyser to distinguish implementation research from aimless exploration

**Contrast with True Failures**:
- Unlike session d673912f where agent researched without writing files (true failure)
- Unlike session 572d532a where agent modified code to "fix" infrastructure errors (wrong response)
- IconSearch agent continued productive work that eventually succeeded (correct response)

### Subtask Persistence Through Infrastructure Errors

**Pattern**: Agent in subtask correctly persists through infrastructure errors despite analyser instructions to report failure to parent, ultimately succeeding.

**Example Session**: 27428c58-919a-4d0e-a493-bdcffccec7f4 (FontSubsetter)
- **RepeatedInfrastructureErrorAnalyser**: Fired 7 times (12:43:01 - 12:43:57) during subtask execution (Trace 002)
  - Analyser instructed: "If in a subtask, report this to the parent agent with FinishSubtask(success: false, summary: 'Infrastructure error')"
  - Agent continued retrying despite instructions
  - Build errors: NETSDK1005 (asset file issues), MSB3021 (file locking)
  - Agent used workaround: killed processes to resolve file locks
  - Build #9 succeeded (12:44:06)
- **Outcome**: Clean build (0 errors, 0 warnings), all tests passed (8/8), spec 27/29 requirements implemented

**Why Ignoring Was Correct**:
1. Infrastructure errors were transient and resolvable (file locks)
2. Agent found practical workaround (kill locks) instead of abandoning task
3. Reporting failure would have blocked the entire session unnecessarily
4. Agent persisted for ~3 minutes and ultimately delivered working code

**Key Learnings**:
- Subtask agents may need more persistence than root agents for infrastructure errors
- File locking (MSB3021) can often be resolved by waiting or process cleanup
- Analyser instruction to "report failure to parent" may be too aggressive for transient errors
- Time-based thresholds (e.g., "after 5 minutes of failures") may be more appropriate than count-based thresholds

**Recommendation**: Consider differentiated thresholds for subtasks vs root agents, or add time-based heuristics to distinguish quick-resolving transient errors from systemic infrastructure failures.

### Infrastructure Error Resolution via obj/bin Cleanup

**Pattern**: Agent resolves persistent NETSDK1005 infrastructure errors by diagnosing the root cause and applying `rm -rf obj bin && dotnet restore` cleanup.

**Example Session**: 40f244c7-043b-4845-982c-511c2cd92456 (StatisticsCalculator)
- **RepeatedInfrastructureErrorAnalyser**: Fired 5 times (13:05:31 - 13:06:18) during subtask execution
  - Builds #2-#7 failed with NETSDK1005 (assets file target framework mismatch)
  - Agent acknowledged infrastructure issue but continued investigating
  - Agent ran diagnostic commands: checked csproj, inspected project.assets.json targets
  - **Agent discovered solution**: `rm -rf obj bin && dotnet restore` followed by clean build
  - Build #8 succeeded (13:07:42)
- **Outcome**: Clean build (0 errors, 0 warnings), all tests passed (10/10), spec 100% implemented (19/19 requirements)

**Why This Works**:
1. NETSDK1005 "assets file doesn't have a target" often indicates corrupted NuGet cache or stale build artifacts
2. `rm -rf obj bin` removes all cached build state, forcing full rebuild
3. `dotnet restore` regenerates project.assets.json with correct target framework
4. This is a legitimate fix for infrastructure errors (not a workaround)

**Agent Reasoning Process** (from client-output.log):
1. First build fails → Agent reads code files to verify correctness
2. Second build fails → Agent recognizes infrastructure error pattern
3. Third build fails → Agent investigates with `dotnet restore && dotnet build`
4. Agent reads csproj to verify target framework
5. Agent checks project.assets.json targets
6. Agent diagnoses: "The restore resolved to netstandard2.0 but the project targets net10.0"
7. Agent applies fix: `rm -rf obj bin && dotnet restore`
8. Build succeeds

**Detection**:
- Multiple NETSDK1005 errors with same error text
- Error message mentions "assets file doesn't have a target for [framework]"
- Agent behavior: investigative commands (checking csproj, assets.json) before cleanup
- Resolution: obj/bin deletion followed by successful build

**Key Learnings**:
- Agent's decision to continue past analyser warnings was correct (not blind retrying)
- Agent demonstrated good diagnostic reasoning (investigation before action)
- The `rm -rf obj bin && dotnet restore` pattern is a valid infrastructure error resolution technique
- This should potentially be codified in analyser instructions: "Try cleaning obj/bin before reporting failure"

**Recommendation**: Update RepeatedInfrastructureErrorAnalyser to suggest obj/bin cleanup after 3-5 NETSDK1005 errors, before recommending task abandonment. This gives agent a concrete action to try rather than just "do not retry."

**Related Plans**:
- Plan 905: Strengthen infrastructure error handling (suggests stopping after 3 errors)
- Plan 930: Improve RepeatedInfrastructureErrorAnalyser threshold (suggests being less aggressive)
- This session evidence: Agent should try cleanup before stopping, combining both approaches

## Bash-Only Exploration Loop (No Code Generation)

**Pattern**: Agent receives a "create app" prompt but spends entire session running bash commands (e.g., sqlite3 queries) to explore provided data, never writing code or starting a workflow. The ResearchPhaseAnalyser doesn't detect this because it tracks GetTypeInfo/IvyQuestion calls, not raw bash exploration.

**Example Session**: 2d62a991-9598-4d9e-a35b-3ec7be6e9471 (LibrarySqlite)
- Task: "Create a library management application using the provided SQLite database"
- Spawned Explorer sub-task: "Explore SQLite database schema" (37 tools, 115K tokens, 149.7s)
- Sub-task ran 30+ sqlite3 queries; main agent also ran redundant queries after
- **Result**: 0 files written, 0 builds, 0 workflows, 0 IvyQuestions, 41 bash calls (all sqlite3)
- Session ended during model generation — no FinishedMessage

**Root Causes**:
1. Agent interpreted "create an application" as "explore the database"
2. Task tool used for exploration-only sub-task instead of implementation
3. ResearchPhaseAnalyser doesn't detect bash-only exploration patterns
4. No guard to enforce that "create" tasks must enter a creation workflow

**Detection**:
- `writeFileCount: 0` + `bashCount: high` = exploration loop
- All bash calls are data queries (sqlite3, curl, etc.) with no file creation
- No workflows triggered for a "create" task

**Distinction from "Empty Task Submission After Research Loop"**:
- That pattern: agent enters a workflow but submits empty work
- This pattern: agent never enters a workflow at all

**Plan Created**: agent-exploration-loop-no-implementation.md

---

## Sub-task 401 Unauthorized Failures

**Pattern**: Multiple sub-tasks fail simultaneously with HTTP 401 (Unauthorized) during parallel execution, typically late in high-token sessions.

**Example Session**: 1bbd69d3-7fb5-4dd1-acb1-671563c83a72 (BarIndustry-V6)
- 4 consecutive sub-tasks (#32, #33, #34, #35) all failed with `401 (Unauthorized)`
- Failures occurred late in session (~10M input tokens consumed)
- Agent recovered by redoing work sequentially in main thread
- Session still completed (62/62 spec, 22/22 tests) but at higher cost ($55.87)

**Root Causes** (suspected):
1. API auth token expiry during long-running sessions
2. Concurrent request rate limiting
3. Token budget exhaustion triggering auth rejection

**Impact**: Lost parallelism, wasted tokens on rework, inflated cost. One-shot score dropped to 7.

**Detection**:
- Client output log shows multiple sub-tasks with "401 (Unauthorized)" failure
- Sub-tasks fail in rapid succession (same root cause)
- Agent successfully completes work after switching to sequential execution

**Plan Created**: subtask-401-unauthorized-kills-parallel-work.md

## Self-Destructive Process Kill During File Lock Recovery

**Pattern**: Agent escalates file lock recovery by killing `dotnet.exe`, which terminates the Ivy agent server itself, ending the session immediately.

**Example Session**: 7edf2845-a5cb-439d-b265-a5c3548acba4 (Recipe-App)
- CreateDbConnection workflow failed due to MSB3021 file lock
- Agent tried: `dotnet build-server shutdown` → `taskkill RecipeApp.exe` → `taskkill dotnet.exe`
- Killing dotnet.exe terminated the agent server — no more generations occurred
- Session ended with zero files written, zero code generated

**Root Cause**: Agent has no guidance about which processes are safe to kill. Killing `dotnet.exe` kills ALL .NET processes including the agent server itself.

**Detection**:
- Client output log ends with `taskkill /F /IM dotnet.exe` or similar
- Verbose log shows no agent generations after the kill command, only cleanup cycles
- Session ends abruptly with workflow still "Running"

**Plan Created**: agent-should-not-kill-dotnet-exe.md
