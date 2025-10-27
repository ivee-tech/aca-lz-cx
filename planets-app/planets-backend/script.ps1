# run the API project
$env:PlanetRepository__Provider = "Sql"
$env:PlanetRepository__UseManagedIdentity = "true"
$env:ConnectionStrings__PlanetDb = "Server=localhost;Database=Planets;Trusted_Connection=True;Encrypt=False;"
dotnet run

# test rockets
<#
# bash
curl http://localhost:5279/api/rockets/stream
curl -X POST http://localhost:5279/api/rockets/publish \
    -H "Content-Type: application/json" \
    -d '{"source":"Earth","destination":"Venus","rocketId":"demo-1"}'
#>

# test rockets (PowerShell)
# Start SSE stream in background job (shows each JSON event line as it arrives)
$sseJob = Start-Job -ScriptBlock {
    $uri = 'http://localhost:5279/api/rockets/stream'
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $stream = $client.GetStreamAsync($uri).GetAwaiter().GetResult()
    $reader = New-Object System.IO.StreamReader($stream)
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { Start-Sleep -Milliseconds 100; continue }
        if ($line -like 'data:*') {
            $json = $line.Substring(5).TrimStart(':').Trim() -replace '^data:\s*',''
            # Clean leading 'data:' if any and output
            if ($json) { Write-Output $json }
        }
    }
}
Write-Host "Started rocket SSE stream in job Id=$($sseJob.Id). Use 'Receive-Job -Id $($sseJob.Id)' to view buffered output or 'Stop-Job' to end."

# Publish a test rocket message
$body = @{ source = 'Earth'; destination = 'Mars'; rocketId = 'demo-1' } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri 'http://localhost:5279/api/rockets/publish' -Method Post -ContentType 'application/json' -Body $body | Format-List

# To stop the stream later:
# Stop-Job -Id $sseJob.Id; Remove-Job -Id $sseJob.Id
