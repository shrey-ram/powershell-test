# Azure Storage Account Details
$sourceAccountName = "sourceaccountname"
$sourceContainerName = "source-container"
$sourceFolderPath = "path/to/source/folder"  # Don't include leading slash
$sourceSASToken = "?sv=2022-11-02&ss=b&srt=sco&sp=r&se=2024-12-31T23:59:59Z&..."  # Your source SAS token

$destAccountName = "destaccountname"
$destContainerName = "dest-container"
$destFolderPath = "path/to/dest/folder"  # Don't include leading slash
$destSASToken = "?sv=2022-11-02&ss=b&srt=sco&sp=rwdlacup&se=2024-12-31T23:59:59Z&..."  # Your dest SAS token

# Build storage URLs
$sourceBaseUrl = "https://$sourceAccountName.blob.core.windows.net/$sourceContainerName"
$destBaseUrl = "https://$destAccountName.blob.core.windows.net/$destContainerName"

Write-Host "Starting blob copy from $sourceContainerName/$sourceFolderPath to $destContainerName/$destFolderPath" -ForegroundColor Yellow

# List blobs using REST API
$listUrl = "$sourceBaseUrl$sourceSASToken&restype=container&comp=list&prefix=$sourceFolderPath/"

try {
    $response = Invoke-RestMethod -Uri $listUrl -Method GET
    $blobs = $response.EnumerationResults.Blobs.Blob
    
    if (!$blobs) {
        Write-Host "No blobs found in source folder!" -ForegroundColor Red
        exit 1
    }
    
    # Handle single blob case (PowerShell doesn't create array for single item)
    if ($blobs -isnot [array]) {
        $blobs = @($blobs)
    }
    
    Write-Host "Found $($blobs.Count) blobs to copy" -ForegroundColor Green
    
    $successCount = 0
    $failCount = 0
    $failedBlobs = @()
    
    foreach ($blob in $blobs) {
        $blobName = $blob.Name
        
        # Calculate destination blob name (preserving folder structure)
        $relativePath = $blobName.Substring($sourceFolderPath.Length)
        $destBlobName = "$destFolderPath$relativePath"
        
        Write-Host "Copying: $blobName -> $destBlobName" -ForegroundColor Cyan
        
        # Build source and destination URLs
        $sourceBlobUrl = "$sourceBaseUrl/$blobName$sourceSASToken"
        $destBlobUrl = "$destBaseUrl/$destBlobName$destSASToken"
        
        # Use REST API to copy blob (server-side copy)
        $headers = @{
            "x-ms-copy-source" = $sourceBlobUrl
            "x-ms-version" = "2020-10-02"
        }
        
        try {
            $copyResponse = Invoke-WebRequest -Uri $destBlobUrl -Method PUT -Headers $headers -UseBasicParsing
            
            if ($copyResponse.StatusCode -eq 201 -or $copyResponse.StatusCode -eq 202) {
                $successCount++
                Write-Host "✓ Successfully initiated copy for: $blobName" -ForegroundColor Green
                
                # Check copy status if it's async (202)
                if ($copyResponse.StatusCode -eq 202) {
                    $copyStatus = $copyResponse.Headers["x-ms-copy-status"]
                    if ($copyStatus) {
                        Write-Host "  Copy status: $copyStatus" -ForegroundColor Gray
                    }
                }
            }
            else {
                $failCount++
                $failedBlobs += $blobName
                Write-Host "✗ Unexpected status code $($copyResponse.StatusCode) for: $blobName" -ForegroundColor Red
            }
        }
        catch {
            $failCount++
            $failedBlobs += $blobName
            Write-Host "✗ Failed to copy $blobName : $_" -ForegroundColor Red
        }
    }
    
    Write-Host "`n========== Copy Summary ==========" -ForegroundColor Yellow
    Write-Host "Total blobs: $($blobs.Count)" -ForegroundColor White
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
    
    if ($failedBlobs.Count -gt 0) {
        Write-Host "`nFailed blobs:" -ForegroundColor Red
        $failedBlobs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    
    Write-Host "`nAll blobs copied successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error listing or copying blobs: $_" -ForegroundColor Red
    exit 1
}
