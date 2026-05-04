using namespace System.Net

param($Request, $TriggerMetadata)

# ── Parse body ───────────────────────────────────────────────────────────────
$rawBody = $Request.Body
if ($rawBody -is [string]) {
    $body = $rawBody | ConvertFrom-Json
} else {
    $body = $rawBody
}

$submittedToken = [string]$body.token
$name           = [string]$body.name
$course         = [string]$body.course
$rating         = [string]$body.rating
$comment        = [string]$body.comment

# ── Validate token ───────────────────────────────────────────────────────────
$validToken = $env:STUDENT_EVALS_TOKEN
if ($submittedToken.Trim() -ne $validToken.Trim()) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body       = "Invalid access code."
    })
    return
}

# ── Validate required fields ──────────────────────────────────────────────────
if (-not $course -or -not $rating -or -not $comment) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = "Missing required fields."
    })
    return
}

# ── Write to Table Storage ────────────────────────────────────────────────────
$connString   = $env:STORAGE_CONNECTION_STRING
$tableName    = "studentevals"
$partitionKey = "eval"
$rowKey       = [Guid]::NewGuid().ToString()
$timestamp    = [DateTime]::UtcNow.ToString("o")

$entity = @{
    PartitionKey = $partitionKey
    RowKey       = $rowKey
    Name         = if ($name) { $name } else { "Anonymous" }
    Course       = $course
    Rating       = $rating
    Comment      = $comment
    Timestamp    = $timestamp
} | ConvertTo-Json

# Parse connection string
$connParts = @{}
$connString.Split(';') | ForEach-Object {
    $kv = $_ -split '=', 2
    if ($kv.Count -eq 2) { $connParts[$kv[0]] = $kv[1] }
}
$accountName = $connParts['AccountName']
$accountKey  = $connParts['AccountKey']

$date         = [DateTime]::UtcNow.ToString("R")
$resource     = "/$accountName/$tableName"
$stringToSign = "POST`n`napplication/json`n$date`n$resource"
$hmac         = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($accountKey))
$sig          = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

try {
    Invoke-RestMethod `
        -Uri "https://$accountName.table.core.windows.net/$tableName" `
        -Method POST `
        -Headers @{
            Authorization  = "SharedKey ${accountName}:${sig}"
            "x-ms-date"    = $date
            "x-ms-version" = "2019-02-02"
            "Content-Type" = "application/json"
            Accept         = "application/json;odata=nometadata"
        } `
        -Body $entity | Out-Null

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Created
        Body       = "Eval submitted."
    })
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to save entry: $_"
    })
}