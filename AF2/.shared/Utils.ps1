function CollectArgs {
    param([string[]]$Arguments)

    $Arguments = $Arguments | Where-Object { $_.Trim() -ne "" }

    if ($Arguments.Count -eq 0) {
        $tempFile = [System.IO.Path]::GetTempFileName()
        Write-Host "No arguments provided. Opening Notepad — save the file and close it to continue."
        Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait
        $Arguments = Get-Content $tempFile | Where-Object { $_.Trim() -ne "" }
        Remove-Item $tempFile
    }

    if ($Arguments.Count -eq 0) {
        Write-Host "No arguments provided. Exiting."
        exit
    }

    return $Arguments
}
