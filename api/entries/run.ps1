using namespace System.Net

param($Request, $TriggerMetadata)

# ── Read from Table Storage ───────────────────────────────────────────────────
$connString  = $env:STORAGE_CONNECTION_STRING
$tableName   = "studentevals"

# Parse connection string
$connParts = @{}
$connString.Split(';') | ForEach-Object {
    $kv = $_ -split '=', 2
    if ($kv.Count -eq 2) { $connParts[$kv[0]] = $kv[1] }
}
$accountName = $connParts['AccountName']
$accountKey  = $connParts['AccountKey']
Write-Host "Account key length: $($accountKey.Length)"

Write-Host "Storage account: '$accountName'"

$date         = [DateTime]::UtcNow.ToString("R")
$resource     = "/$accountName/$tableName"
$stringToSign = "GET`n`napplication/json`n$date`n$resource"
$hmac         = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($accountKey))
$sig          = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

try {
    $response = Invoke-RestMethod `
        -Uri "https://$accountName.table.core.windows.net/${tableName}()" `
        -Method GET `
        -Headers @{
            Authorization  = "SharedKey ${accountName}:${sig}"
            "x-ms-date"    = $date
            "x-ms-version" = "2019-02-02"
            Accept         = "application/json;odata=nometadata"
        }

    $entries = $response.value | Sort-Object Timestamp -Descending

    Write-Host "Entries retrieved: $($entries.Count)"

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers    = @{ "Content-Type" = "application/json" }
        Body       = ($entries | ConvertTo-Json -Depth 5)
    })
} catch {
    Write-Host "Table Storage read failed: $_"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to read entries: $_"
    })
}