# Azure Storage Account Details - Replicating azcopy recursive copy
$sourceAccountName = "sourceaccountname"
$sourceContainerName = "source-container"
$sourceFolderPath = "templates"  # The folder to copy from
$sourceSASToken = "?sv=2022-11-02&ss=b&srt=sco&sp=r&se=2024-12-31T23:59:59Z&..."  # Your source SAS token

$destAccountName = "destaccountname"
$destContainerName = "dest-container"
# For azcopy-like behavior, we copy the entire folder structure as-is
$destSASToken = "?sv=2022-11-02&ss=b&srt=sco&sp=rwdlacup&se=2024-12-31T23:59:59Z&..."  # Your dest SAS token

# Build storage URLs
$sourceBaseUrl = "https://$sourceAccountName.blob.core.windows.net/$sourceContainerName"
$destBaseUrl = "https://$destAccountName.blob.core.windows.net/$destContainerName"

Write-Host "Starting recursive copy from $sourceContainerName/$sourceFolderPath to $destContainerName (preserving folder structure)" -ForegroundColor Yellow

# List blobs using REST API - recursive copy like azcopy
# First try with trailing slash (most common), then without
$listUrl = "$sourceBaseUrl$sourceSASToken&restype=container&comp=list&prefix=$sourceFolderPath/"

Write-Host "Listing all blobs in '$sourceFolderPath' folder recursively..." -ForegroundColor Gray
Write-Host "URL pattern: $sourceBaseUrl/[SAS]&restype=container&comp=list&prefix=$sourceFolderPath/" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod -Uri $listUrl -Method GET
    $blobs = $response.EnumerationResults.Blobs.Blob
    
    # If no blobs found with trailing slash, try without (handles edge cases)
    if (!$blobs) {
        Write-Host "No blobs found with trailing slash, trying without..." -ForegroundColor Yellow
        $listUrl = "$sourceBaseUrl$sourceSASToken&restype=container&comp=list&prefix=$sourceFolderPath"
        $response = Invoke-RestMethod -Uri $listUrl -Method GET
        $blobs = $response.EnumerationResults.Blobs.Blob
    }
    
    # Also try listing everything if still no results (debug mode)
    if (!$blobs) {
        Write-Host "Still no results, trying to list all blobs to debug..." -ForegroundColor Yellow
        $debugUrl = "$sourceBaseUrl$sourceSASToken&restype=container&comp=list"
        $debugResponse = Invoke-RestMethod -Uri $debugUrl -Method GET
        $allBlobs = $debugResponse.EnumerationResults.Blobs.Blob
        if ($allBlobs) {
            Write-Host "Found $($allBlobs.Count) total blobs in container. First few:" -ForegroundColor Yellow
            $allBlobs | Select-Object -First 5 | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
        }
    }
    
    if (!$blobs) {
        Write-Host "No blobs found in source folder '$sourceFolderPath'!" -ForegroundColor Red
        Write-Host "Please verify:" -ForegroundColor Yellow
        Write-Host "  1. The folder name is correct (case-sensitive)" -ForegroundColor Yellow
        Write-Host "  2. The SAS token has List permission" -ForegroundColor Yellow
        Write-Host "  3. There are actually files in the folder" -ForegroundColor Yellow
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
        
        # For azcopy-like behavior, preserve the full path including the templates folder
        # This replicates: azcopy copy "source/templates" "dest" --recursive
        $destBlobName = $blobName  # Keep the full path as-is
        
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
