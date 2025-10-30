$env:IVY_FIX_USE_CLAUDE_CODE = "0"
ivy-local fix $PWD --no-telemetry --verbose --debug-agent-server http://localhost:5122 --write-disallow "Connections/*"
