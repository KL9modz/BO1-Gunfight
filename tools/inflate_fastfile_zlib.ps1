param(
    [Parameter(Mandatory=$true)][string]$FastFile,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$Offset = 12
)

$ErrorActionPreference = "Stop"

$inputStream = [System.IO.File]::Open($FastFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    [void]$inputStream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
    $zlibType = [System.Type]::GetType("System.IO.Compression.ZLibStream")
    if ($null -ne $zlibType) {
        $deflate = [System.IO.Compression.ZLibStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    } else {
        [void]$inputStream.Seek($Offset + 2, [System.IO.SeekOrigin]::Begin)
        $deflate = [System.IO.Compression.DeflateStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    }
    try {
        $outputStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $deflate.CopyTo($outputStream)
        } finally {
            $outputStream.Dispose()
        }
    } finally {
        $deflate.Dispose()
    }
} finally {
    $inputStream.Dispose()
}

$out = Get-Item -LiteralPath $OutFile
Write-Host "Inflated $($out.Length) bytes to $OutFile"
