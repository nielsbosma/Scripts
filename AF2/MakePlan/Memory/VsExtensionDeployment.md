# VS Code Extension Deployment

The ivy-plans VS Code extension source lives at `D:\Repos\_Personal\Scripts\AF2\.vscode-extensions\ivy-plans\` but is installed at `~/.vscode/extensions/undefined_publisher.ivy-plans-0.1.0/`.

**Key insight**: Editing the source files and committing does NOT update the installed extension. The files must be explicitly copied to the installed directory and VS Code must be reloaded.

When a plan adds or modifies VS Code extension commands, always check whether the installed copy matches the source. If they differ, include reinstallation steps in the plan.
