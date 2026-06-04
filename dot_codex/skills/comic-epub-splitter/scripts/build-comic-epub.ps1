param(
  [Parameter(Mandatory = $true)] [string]$SourceDir,
  [Parameter(Mandatory = $true)] [string]$OutputEpub,
  [string]$Title,
  [int]$MaxImageBytes = 1000000,
  [int]$MaxImageWidth = 1800
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = Resolve-Path -LiteralPath $SourceDir
$outParent = Split-Path -Parent $OutputEpub
if (-not $outParent) { $outParent = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $outParent)) { throw "Output directory does not exist: $outParent" }
$out = Join-Path (Resolve-Path -LiteralPath $outParent) (Split-Path -Leaf $OutputEpub)
if (-not $Title) { $Title = [System.IO.Path]::GetFileNameWithoutExtension($out) }

$tmpName = '.epub_build_' + ([System.IO.Path]::GetFileNameWithoutExtension($out) -replace '[^A-Za-z0-9._-]', '_')
$tmp = Join-Path $outParent $tmpName
$resolvedParent = (Resolve-Path -LiteralPath $outParent).Path
if (Test-Path -LiteralPath $tmp) {
  $resolvedTmp = (Resolve-Path -LiteralPath $tmp).Path
  if (-not $resolvedTmp.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unexpected temp path: $resolvedTmp" }
  Remove-Item -LiteralPath $resolvedTmp -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $tmp 'META-INF') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmp 'EPUB\images') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmp 'EPUB\xhtml') | Out-Null

function XmlEscape([string]$s) { [System.Security.SecurityElement]::Escape($s) }
function Write-Utf8([string]$Path, [string[]]$Lines) { Set-Content -LiteralPath $Path -Encoding utf8 -Value ($Lines -join "`n") }
function Resize-BitmapToMaxWidth([System.Drawing.Bitmap]$Bitmap, [int]$MaxWidth) {
  if ($Bitmap.Width -le $MaxWidth) { return $Bitmap.Clone() }
  $scale = $MaxWidth / $Bitmap.Width
  $newHeight = [int][Math]::Round($Bitmap.Height * $scale)
  $resized = New-Object System.Drawing.Bitmap($MaxWidth, $newHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [System.Drawing.Graphics]::FromImage($resized)
  try {
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.DrawImage($Bitmap, 0, 0, $MaxWidth, $newHeight)
  } finally { $graphics.Dispose() }
  return $resized
}
function Encode-JpegBytes([System.Drawing.Bitmap]$Bitmap, [int]$Quality) {
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
  $params = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$Quality)
  $ms = New-Object System.IO.MemoryStream
  try { $Bitmap.Save($ms, $codec, $params); return $ms.ToArray() } finally { $params.Dispose(); $ms.Dispose() }
}
function Save-JpegTarget([System.Drawing.Bitmap]$Bitmap, [string]$Path, [int]$MaxBytes, [int]$MaxWidth) {
  $working = Resize-BitmapToMaxWidth -Bitmap $Bitmap -MaxWidth $MaxWidth
  $scaleRounds = 0
  try {
    while ($true) {
      foreach ($q in @(82,76,70,64,58,52,46,40)) {
        $bytes = Encode-JpegBytes -Bitmap $working -Quality $q
        if ($bytes.Length -lt $MaxBytes) {
          [System.IO.File]::WriteAllBytes($Path, $bytes)
          return [pscustomobject]@{ Bytes=$bytes.Length; Quality=$q; Width=$working.Width; Height=$working.Height; ScaleRounds=$scaleRounds }
        }
      }
      $nextWidth = [int][Math]::Round($working.Width * 0.85)
      if ($nextWidth -lt 500) { throw "Unable to compress under $MaxBytes bytes: $Path" }
      $old = $working
      $working = Resize-BitmapToMaxWidth -Bitmap $old -MaxWidth $nextWidth
      $old.Dispose()
      $scaleRounds++
    }
  } finally { $working.Dispose() }
}
function New-BitmapFromImage([System.Drawing.Image]$Image) {
  $bitmap = New-Object System.Drawing.Bitmap($Image.Width, $Image.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try { $graphics.Clear([System.Drawing.Color]::White); $graphics.DrawImage($Image, 0, 0, $Image.Width, $Image.Height) } finally { $graphics.Dispose() }
  return $bitmap
}

Set-Content -LiteralPath (Join-Path $tmp 'mimetype') -Value 'application/epub+zip' -NoNewline -Encoding ascii
Write-Utf8 (Join-Path $tmp 'META-INF\container.xml') @(
  '<?xml version="1.0" encoding="UTF-8"?>'.Replace('\"','"'),
  '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'.Replace('\"','"'),
  '  <rootfiles>',
  '    <rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>'.Replace('\"','"'),
  '  </rootfiles>',
  '</container>'
)

$sourceImages = Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' } | Sort-Object Name
if ($sourceImages.Count -eq 0) { throw 'No jpg/jpeg files found.' }

$pageRecords = New-Object System.Collections.Generic.List[object]
$splitCount = 0
$singleCount = 0
$pageNo = 0
$largestOutput = 0
$overLimitOutputs = 0
foreach ($file in $sourceImages) {
  $img = [System.Drawing.Image]::FromFile($file.FullName)
  try {
    if ($img.Width -gt $img.Height) {
      $splitCount++
      $leftWidth = [int][Math]::Floor($img.Width / 2)
      $rightX = $leftWidth
      $rightWidth = $img.Width - $leftWidth
      foreach ($part in @(@{ Suffix = 'right'; X = $rightX; Width = $rightWidth }, @{ Suffix = 'left'; X = 0; Width = $leftWidth })) {
        $pageNo++
        $imgName = ('page{0:D4}.jpg' -f $pageNo)
        $dest = Join-Path $tmp "EPUB\images\$imgName"
        $bitmap = New-Object System.Drawing.Bitmap($part.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
          $graphics.Clear([System.Drawing.Color]::White)
          $graphics.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $part.Width, $img.Height)), (New-Object System.Drawing.Rectangle($part.X, 0, $part.Width, $img.Height)), [System.Drawing.GraphicsUnit]::Pixel)
          $result = Save-JpegTarget -Bitmap $bitmap -Path $dest -MaxBytes $MaxImageBytes -MaxWidth $MaxImageWidth
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
        if ($result.Bytes -gt $largestOutput) { $largestOutput = $result.Bytes }
        if ($result.Bytes -ge $MaxImageBytes) { $overLimitOutputs++ }
        $pageRecords.Add([pscustomobject]@{ Image=$imgName; Label=('{0} {1}' -f $file.BaseName, $part.Suffix); Source=$file.Name; Split=$true; Bytes=$result.Bytes; Width=$result.Width; Height=$result.Height; Quality=$result.Quality })
      }
    } else {
      $singleCount++
      $pageNo++
      $imgName = ('page{0:D4}.jpg' -f $pageNo)
      $dest = Join-Path $tmp "EPUB\images\$imgName"
      $bitmap = New-BitmapFromImage -Image $img
      try { $result = Save-JpegTarget -Bitmap $bitmap -Path $dest -MaxBytes $MaxImageBytes -MaxWidth $MaxImageWidth } finally { $bitmap.Dispose() }
      if ($result.Bytes -gt $largestOutput) { $largestOutput = $result.Bytes }
      if ($result.Bytes -ge $MaxImageBytes) { $overLimitOutputs++ }
      $pageRecords.Add([pscustomobject]@{ Image=$imgName; Label=$file.BaseName; Source=$file.Name; Split=$false; Bytes=$result.Bytes; Width=$result.Width; Height=$result.Height; Quality=$result.Quality })
    }
  } finally { $img.Dispose() }
}

$manifestItems = New-Object System.Collections.Generic.List[string]
$spineItems = New-Object System.Collections.Generic.List[string]
$navItems = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $pageRecords.Count; $i++) {
  $pageIndex = $i + 1
  $record = $pageRecords[$i]
  $pageName = ('page{0:D4}.xhtml' -f $pageIndex)
  $pageId = ('page{0:D4}' -f $pageIndex)
  $imageId = ('img{0:D4}' -f $pageIndex)
  $label = XmlEscape($record.Label)
  $manifestItems.Add(('    <item id="{0}" href="images/{1}" media-type="image/jpeg"/>' -f $imageId, $record.Image).Replace('\"','"'))
  $manifestItems.Add(('    <item id="{0}" href="xhtml/{1}" media-type="application/xhtml+xml"/>' -f $pageId, $pageName).Replace('\"','"'))
  $spineItems.Add(('    <itemref idref="{0}"/>' -f $pageId).Replace('\"','"'))
  $navItems.Add(('      <li><a href="xhtml/{0}">{1}</a></li>' -f $pageName, $label).Replace('\"','"'))
  Write-Utf8 (Join-Path $tmp "EPUB\xhtml\$pageName") @(
    '<?xml version="1.0" encoding="UTF-8"?>'.Replace('\"','"'),
    '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-Hant" lang="zh-Hant">'.Replace('\"','"'),
    '<head>',
    "  <title>$label</title>",
    '  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>'.Replace('\"','"'),
    '  <style>html,body{margin:0;padding:0;background:#000;}body{display:flex;align-items:center;justify-content:center;min-height:100vh;}img{display:block;max-width:100%;height:auto;}</style>',
    '</head>',
    '<body>',
    ('  <img src="../images/{0}" alt="{1}"/>' -f $record.Image, $label).Replace('\"','"'),
    '</body>',
    '</html>'
  )
}

$titleEsc = XmlEscape($Title)
$identifier = 'urn:uuid:' + [guid]::NewGuid().ToString()
$modified = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Utf8 (Join-Path $tmp 'EPUB\nav.xhtml') @(
  '<?xml version="1.0" encoding="UTF-8"?>'.Replace('\"','"'),
  '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-Hant" lang="zh-Hant">'.Replace('\"','"'),
  "<head><title>$titleEsc</title></head>",
  '<body>',
  '  <nav epub:type="toc" id="toc">'.Replace('\"','"'),
  "    <h1>$titleEsc</h1>",
  '    <ol>',
  ($navItems -join "`n"),
  '    </ol>',
  '  </nav>',
  '</body>',
  '</html>'
)
Write-Utf8 (Join-Path $tmp 'EPUB\package.opf') @(
  '<?xml version="1.0" encoding="UTF-8"?>'.Replace('\"','"'),
  '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-Hant">'.Replace('\"','"'),
  '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'.Replace('\"','"'),
  "    <dc:identifier id=`"bookid`">$identifier</dc:identifier>",
  "    <dc:title>$titleEsc</dc:title>",
  '    <dc:language>zh-Hant</dc:language>',
  "    <meta property=`"dcterms:modified`">$modified</meta>",
  '  </metadata>',
  '  <manifest>',
  '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'.Replace('\"','"'),
  ($manifestItems -join "`n"),
  '  </manifest>',
  '  <spine>',
  ($spineItems -join "`n"),
  '  </spine>',
  '</package>'
)

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $entry = $zip.CreateEntry('mimetype', [System.IO.Compression.CompressionLevel]::NoCompression)
  $stream = $entry.Open()
  $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
  try { $writer.Write('application/epub+zip') } finally { $writer.Dispose(); $stream.Dispose() }
  $files = Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.Name -ne 'mimetype' } | Sort-Object FullName
  foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($tmp, $file.FullName).Replace('\','/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally { $zip.Dispose() }

$resolvedTmp2 = (Resolve-Path -LiteralPath $tmp).Path
if ($resolvedTmp2.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedTmp2 -Recurse -Force }

$zip = [System.IO.Compression.ZipFile]::OpenRead($out)
try {
  $entries = @($zip.Entries)
  $mimetypeEntry = $zip.GetEntry('mimetype')
  $reader = New-Object System.IO.StreamReader($mimetypeEntry.Open(), [System.Text.Encoding]::ASCII)
  try { $mimetype = $reader.ReadToEnd() } finally { $reader.Dispose() }
  foreach ($name in @('META-INF/container.xml','EPUB/package.opf','EPUB/nav.xhtml', 'EPUB/xhtml/page0001.xhtml', ('EPUB/xhtml/page{0:D4}.xhtml' -f $pageRecords.Count))) {
    $e = $zip.GetEntry($name)
    if ($null -eq $e) { throw "Missing $name" }
    $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
    try { [xml]$xml = $sr.ReadToEnd() } finally { $sr.Dispose() }
  }
  $imageEntries = @($entries | Where-Object { $_.FullName -like 'EPUB/images/*.jpg' -or $_.FullName -like 'EPUB/images/*.jpeg' })
  $pageEntries = @($entries | Where-Object { $_.FullName -like 'EPUB/xhtml/page*.xhtml' })
  $wideCount = 0
  foreach ($e in $imageEntries) {
    $stream = $e.Open()
    $img = [System.Drawing.Image]::FromStream($stream)
    try { if ($img.Width -gt $img.Height) { $wideCount++ } } finally { $img.Dispose(); $stream.Dispose() }
  }
  $overLimitEntries = @($imageEntries | Where-Object { $_.Length -ge $MaxImageBytes })
  $largestEntry = $imageEntries | Sort-Object Length -Descending | Select-Object -First 1
  [pscustomobject]@{
    File = $out
    SizeBytes = (Get-Item -LiteralPath $out).Length
    SourceJpg = $sourceImages.Count
    SplitSource = $splitCount
    SingleSource = $singleCount
    EpubPages = $pageRecords.Count
    FirstEntry = $entries[0].FullName
    Mimetype = $mimetype
    ImageEntries = $imageEntries.Count
    PageEntries = $pageEntries.Count
    WideImages = $wideCount
    OverLimitImages = $overLimitEntries.Count
    LargestImageBytes = $largestEntry.Length
    TotalEntries = $entries.Count
  }
} finally { $zip.Dispose() }
