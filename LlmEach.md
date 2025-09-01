Create a powershell script named LlmEach.ps1.

It should take the following parameters

<fileGlob> 
-Prompt string
or
-PromptFile string

If first calculates the files matching the fileGlob.

The script presents the top 5 matched files with an additional + X more and a confirmation do you want to proceed.

Each matched file is a "job"

We can run max 5 jobs in parallell. 

For each job produce a prompt. Either from -Prompt or -PromptFile. Replace the string {{File}} with the full path of the matched file.

Using claude code CLI run the prompt in yolo mode. 

SHow a nice progressbar. 


