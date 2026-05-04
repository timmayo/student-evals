using namespace System.Net

param($Request, $TriggerMetadata)

# Retrieve storage account name from environment variable (set in Function App config)
$StorageAccountName = $env:STORAGE_ACCOUNT_NAME

# Get storage account key via Managed Identity → Key Vault
$kvName     = $env:KEY_VAULT_NAME
$secretName = "storage-account-key"

try {
    $token = (Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" `
        -Headers @{ Metadata = "true" }).access_token

    $storageKey = (Invoke-RestMethod `
        -Uri "https://$kvName.vault.azure.net/secrets/$secretName/?api-version=7.3" `
        -Headers @{ Authorization = "Bearer $token" }).value
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to retrieve storage key: $_"
    })
    return
}

# Query Table Storage for all entries, newest first
$tableName    = "studentevals"
$date         = [DateTime]::UtcNow.ToString("R")
$resource     = "/$StorageAccountName/$tableName"
$stringToSign = "GET`n`napplication/json`n$date`n$resource"
$hmac         = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($storageKey))
$sig          = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

try {
    $response = Invoke-RestMethod `
        -Uri "https://$StorageAccountName.table.core.windows.net/${tableName}()" `
        -Method GET `
        -Headers @{
            Authorization  = "SharedKey ${StorageAccountName}:${sig}"
            "x-ms-date"    = $date
            "x-ms-version" = "2019-02-02"
            Accept         = "application/json;odata=nometadata"
        }

    # Sort newest first
    $entries = $response.value | Sort-Object Timestamp -Descending

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers    = @{ "Content-Type" = "application/json" }
        Body       = ($entries | ConvertTo-Json -Depth 5)
    })
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to read entries: $_"
    })
}