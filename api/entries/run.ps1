using namespace System.Net

param($Request, $TriggerMetadata)

$connString = $env:STORAGE_CONNECTION_STRING
$tableName  = "studentevals"

try {
    $ctx     = New-AzStorageContext -ConnectionString $connString
    $table   = (Get-AzStorageTable -Name $tableName -Context $ctx).CloudTable
    $query   = New-Object Microsoft.Azure.Cosmos.Table.TableQuery
    $entries = $table.ExecuteQuery($query) | Sort-Object Timestamp -Descending

    $result = @($entries | ForEach-Object {
        @{
            Name      = $_.Properties['Name'].StringValue
            Course    = $_.Properties['Course'].StringValue
            Rating    = $_.Properties['Rating'].StringValue
            Comment   = $_.Properties['Comment'].StringValue
            Timestamp = $_.Properties['Timestamp'].StringValue
        }
    })

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers    = @{ "Content-Type" = "application/json" }
        Body       = ($result | ConvertTo-Json -Depth 5 -AsArray)
    })
} catch {
    Write-Host "Error: $_"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = "Failed to read entries: $_"
    })
}