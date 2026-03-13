We have the following repositories on this machine:

Read ../.shared/Repos.md

**Check Args:** If Args contains `-NoBuild`, skip all build steps (steps marked with [BUILD]) below.

For each repository run the following steps as a subtask:

- Check if there's any local changes that hasn't been committed. If yes then make logical commits.
- Pull from origin
- If there are any merge conflicts then fix them
- [BUILD] Build only the core slnx projects listed below - make sure there are no build errors or warnings - If we do then fix them.

Core solutions to build:
  - `D:\Repos\_Ivy\Ivy-Framework\src\Ivy-Framework.slnx`
  - `D:\Repos\_Ivy\Ivy-Agent\Ivy-Agent.slnx`
  - After building Ivy-Agent.slnx, also build `D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Test.Manager\Ivy.Agent.Test.Manager.csproj` (not included in solution)
  - `D:\Repos\_Ivy\Ivy\Ivy.Console\Ivy.Console.slnx`
  - `D:\Repos\_Ivy\Ivy-Mcp\Ivy.Mcp.slnx`
- Commit the changes
- Push to origin
