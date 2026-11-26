# Forks the researched Ivy-Tendril-V2 session into a fresh one, in the repo.
#
# --fork-session is what makes this safe to run several times at once: each
# invocation resumes the same base session but gets its OWN new session id, so
# parallel tasks never write over each other's history.
#
# The base session holds the V1->V2 port survey and knows D:\Repos\_Ivy\.plan\PORT.md.

$repo = 'D:\Repos\_Ivy\Ivy-Tendril-V2'
$session = 'c16c2d93-0b87-45cb-bb89-e5a7e51aed5d'

Push-Location $repo
try {
    claude --dangerously-skip-permissions --resume $session --fork-session $args
}
finally {
    Pop-Location
}
