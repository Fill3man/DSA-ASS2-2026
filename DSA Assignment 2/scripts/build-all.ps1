# Builds every Ballerina service jar so `docker compose up --build` can package them.
#   .\scripts\build-all.ps1                 # all services
#   .\scripts\build-all.ps1 order-service   # just one
#   .\scripts\build-all.ps1 -Offline        # use only the local package cache
param(
    [string[]] $Services = @(),
    [switch] $Offline
)
# Not "Stop": bal prints warnings on stderr, which Windows PowerShell would
# treat as fatal. Failures are detected through $LASTEXITCODE instead.
$root = Split-Path $PSScriptRoot -Parent

# bal defaults to a 2 GB heap; cap it so builds work on 4-8 GB machines.
if (-not $env:JAVA_OPTS) { $env:JAVA_OPTS = "-Xmx768m -XX:+UseSerialGC" }

if ($Services.Count -eq 0) {
    $Services = Get-ChildItem (Join-Path $root "services") -Directory | ForEach-Object Name
}

$failed = @()
foreach ($svc in $Services) {
    Write-Host "==> $svc" -ForegroundColor Cyan
    Push-Location (Join-Path $root "services\$svc")
    try {
        $buildArgs = @("build")
        if ($Offline) { $buildArgs += "--offline" }
        # bal.bat doesn't always pass the exit code through, so judge success
        # by whether the jar is newer than every source file.
        & bal @buildArgs
        $jar = Get-ChildItem "target\bin\*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
        $newestSource = Get-ChildItem -Recurse -File -Include *.bal, Ballerina.toml |
            Where-Object { $_.FullName -notmatch '\\target\\' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $jar -or $jar.LastWriteTime -lt $newestSource.LastWriteTime) {
            $failed += $svc
            if ($jar -and $LASTEXITCODE -eq 0) {
                Write-Host "  (jar is older than the source - is the service still running from 'bal run'?)" -ForegroundColor Yellow
            }
        }
    } finally {
        Pop-Location
    }
}

if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "All services built. Next: docker compose up -d --build" -ForegroundColor Green
