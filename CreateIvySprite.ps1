$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Generate random 6-character string (a-z, 0-9)
$chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
$randomString = -join (1..6 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
$sprite_name = "ivy-$randomString"
Write-Host "Creating sprite: $sprite_name"
sprite create $sprite_name -skip-console
sprite -s $sprite_name exec bash -c "sudo apt update && sudo apt install -y dotnet-sdk-10.0"
sprite -s $sprite_name exec bash -c 'cat << \EOF >> ~/.bash_profile
# Add .NET Core SDK tools
export PATH="$PATH:/home/sprite/.dotnet/tools"
EOF'
sprite -s $sprite_name exec bash -c "dotnet tool install -g Ivy.Console"
sprite -s $sprite_name exec bash -c "dotnet dev-certs https --trust"
sprite -s $sprite_name url update --auth public

$stopwatch.Stop()
Write-Host "Total time: $($stopwatch.Elapsed.ToString('mm\:ss'))"
