using namespace System.Net

param($Request, $TriggerMetadata)

$StorageAccountName = $env:STORAGE_ACCOUNT_NAME
$kvName             = $env:KEY_VAULT_NAME
$tokenSecretName    = "student-evals-token"
$storageSecretName  = "storage-account-key"

# ── Parse body ──────────────────────────────────────────────────────────────
$rawBody = $Request.Body
if ($rawBody -is [string]) {
    $body = $rawBody | ConvertFrom-Json
} else {
    $body = $rawBody
}

Write-Host "Body type: $($rawBody.GetType().Name)"
Write-Host "Token: $($body.token)"
Write-Host "Course: $($body.course)"
Write-Host "Rating: $($body.rating)"
Write-Host "Comment: $($body.comment)"

$submittedToken = $body.token
$submittedToken = $body.token
$name           = $body.name
$course         = $body.course
$rating         = [int]$body.rating
$comment        = $body.comment

if (-not $submittedToken -or -not $course -or -not $rating -or -not $comment) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = "Missing required fields."
    })
    return
}

# ── Retrieve secrets from Key Vault via Managed Identity ────────────────────
try {
    $miToken = (Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" `
        -Headers @{ Metadata = "true" }).access_token

    $validToken = (Invoke-RestMethod `
        -Uri "https://$kvName.vault.azure.net/secrets/$tokenSecretName/?api-version=7.3" `
        -Headers @{ Authorization = "Bearer $miToken" }).value

    $storageKey = (Invoke-RestMethod `
        -Uri "https://$kvName.vault.azure.net/secrets/$storageSecretName/?api-version=7.3" `
        -Headers @{ Authorization = "Bearer $miToken" }).value
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to retrieve secrets: $_"
    })
    return
}

# ── Validate token ───────────────────────────────────────────────────────────
if ($submittedToken -ne $validToken) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body       = "Invalid access code."
    })
    return
}

# ── Write entry to Table Storage ─────────────────────────────────────────────
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

$date         = [DateTime]::UtcNow.ToString("R")
$resource     = "/$StorageAccountName/$tableName"
$stringToSign = "POST`n`napplication/json`n$date`n$resource"
$hmac         = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($storageKey))
$sig          = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

try {
    Invoke-RestMethod `
        -Uri "https://$StorageAccountName.table.core.windows.net/$tableName" `
        -Method POST `
        -Headers @{
            Authorization  = "SharedKey ${StorageAccountName}:${sig}"
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