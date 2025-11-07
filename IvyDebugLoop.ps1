param(
    [string]$BuildCommand = "dotnet build"
)

function ConvertFrom-ClaudeOutput {
    param(
        [string]$JsonLine
    )

    try {
        $obj = $JsonLine | ConvertFrom-Json

        switch ($obj.type) {
            "system" {
                if ($obj.subtype -eq "init") {
                    Write-Host "  [System] Initializing Claude Code session..." -ForegroundColor DarkGray
                    Write-Host "    Model: $($obj.model)" -ForegroundColor DarkGray
                    Write-Host "    Session ID: $($obj.session_id)" -ForegroundColor DarkGray
                }
            }
            "assistant" {
                if ($obj.message.content) {
                    foreach ($content in $obj.message.content) {
                        if ($content.type -eq "text") {
                            Write-Host "  [Claude] $($content.text)" -ForegroundColor White
                        }
                        elseif ($content.type -eq "tool_use") {
                            $toolName = $content.name
                            Write-Host "  [Tool] Using: $toolName" -ForegroundColor Magenta

                            # Show specific details for common tools
                            if ($toolName -eq "TodoWrite") {
                                if ($content.input.todos) {
                                    foreach ($todo in $content.input.todos) {
                                        $statusIcon = switch ($todo.status) {
                                            "completed" { "✓" }
                                            "in_progress" { "→" }
                                            "pending" { "○" }
                                            default { "?" }
                                        }
                                        Write-Host "    $statusIcon $($todo.content)" -ForegroundColor Gray
                                    }
                                }
                            }
                            elseif ($toolName -eq "Bash") {
                                Write-Host "    Command: $($content.input.command)" -ForegroundColor Gray
                            }
                            elseif ($toolName -eq "Edit" -or $toolName -eq "Write" -or $toolName -eq "Read") {
                                Write-Host "    File: $($content.input.file_path)" -ForegroundColor Gray
                            }
                        }
                    }
                }
            }
            "user" {
                # Tool results - usually too verbose, so we'll skip or summarize
                if ($obj.message.content) {
                    foreach ($content in $obj.message.content) {
                        if ($content.type -eq "tool_result" -and $content.is_error) {
                            Write-Host "  [Error] Tool execution failed" -ForegroundColor Red
                        }
                    }
                }
            }
        }
    }
    catch {
        # If we can't parse as JSON, just show the raw line
        if ($JsonLine.Trim()) {
            Write-Host "  $JsonLine" -ForegroundColor DarkGray
        }
    }
}

$currentDir = Get-Location

# 1. Create a folder named .debug in the current directory if it doesn't exist
Write-Host "Step 1: Creating .debug folder..." -ForegroundColor Cyan
$debugFolderPath = Join-Path -Path $currentDir -ChildPath ".debug"
if (-Not (Test-Path -Path $debugFolderPath)) {
    New-Item -ItemType Directory -Path $debugFolderPath | Out-Null
    Write-Host "  .debug folder created" -ForegroundColor Green
} else {
    Write-Host "  .debug folder already exists" -ForegroundColor Yellow
}

# 2. Run build command in $currentDir and save the output to build.log inside the .debug folder
Write-Host "`nStep 2: Running build command ($BuildCommand) and saving output to build.log..." -ForegroundColor Cyan
$buildLogPath = Join-Path -Path $debugFolderPath -ChildPath "build.log"
Invoke-Expression "$BuildCommand *>&1" | Out-File -FilePath $buildLogPath -Encoding utf8
Write-Host "  Build output saved to $buildLogPath" -ForegroundColor Green

# 3. Setup a git repository in $currentDir folder and make an initial commit with all files
Write-Host "`nStep 3: Setting up git repository..." -ForegroundColor Cyan
$gitPath = Join-Path -Path $currentDir -ChildPath ".git"
if (-Not (Test-Path -Path $gitPath)) {
    git init
    git add .
    git commit -m "Initial commit"
    Write-Host "  Git repository initialized with initial commit" -ForegroundColor Green
} else {
    Write-Host "  Git repository already exists" -ForegroundColor Yellow
}

# 4. Run claude code in $currentDir with the following prompt. Make sure to output the continuous results. Use --dangerously-skip-permissions
Write-Host "`nStep 4: Running Claude Code to fix build errors..." -ForegroundColor Cyan

$prompt1 = @"
You are an expert software engineer. You will help me fix build errors in my project.
1. Run '$BuildCommand' and fix the errors. Repeat until there are no build errors.
2. Write down a summary of what you learned during the process in .debug/learnings.md

Do not touch anything in the /Connections folder
"@

claude -p --verbose --dangerously-skip-permissions --output-format stream-json "$prompt1" | ForEach-Object {
    ConvertFrom-ClaudeOutput $_
}
Write-Host "  Claude Code execution completed" -ForegroundColor Green

# 5. Get the changes git diff > .debug/changes.txt
Write-Host "`nStep 5: Saving git diff to changes.txt..." -ForegroundColor Cyan
git diff | Out-File -FilePath (Join-Path -Path $debugFolderPath -ChildPath "changes.txt") -Encoding utf8
Write-Host "  Changes saved to .debug/changes.txt" -ForegroundColor Green

# 6. Run claude code with the following prompt:
Write-Host "`nStep 6: Running Claude Code to improve prompts/templates..." -ForegroundColor Cyan
$prompt2 = @"
[ULTRATHINK]

The project in this directory was originally created using LLM based agents. 

When completed we had the dotnet build errors you can read in:
.debug/build.log

We have run an other LLM to fix all the issue and succeeded. 

We asked the LLM to write down a summary of what was learned:
.debug/learnings.md 

All the changes made during debugging is found in:
.debug/changes.txt

The relative path to the prompt(s) for each original file can be found in:
/.ivy/sources.yaml 

The agent root folder is in:
D:\Repos\_Ivy\Ivy-Agent\ and the paths in sources.yaml are relative to this. 

Your task is to understand the learnings and improve these prompt/template files so that the agent can be improved.

If you make any changes to D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Examples\ make sure this compiles using dotnet build. 

These app are using the Ivy-Framework. The source code can be found here:
D:\Repos\_Ivy\Ivy-Framework\Ivy\

Samples:
D:\Repos\_Ivy\Ivy-Framework\Ivy.Samples.Shared\

"@

claude -p --verbose --dangerously-skip-permissions --output-format stream-json "$prompt2" | ForEach-Object {
    ConvertFrom-ClaudeOutput $_
}
Write-Host "`nStep 6: Claude Code execution completed" -ForegroundColor Green
Write-Host "`nAll steps completed successfully!" -ForegroundColor Cyan