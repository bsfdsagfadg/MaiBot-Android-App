param (
    [string]$sourceFile = "scripts/Icon.png"
)

$targetPath = "android/app/src/main/res"
$sizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}

Add-Type -AssemblyName System.Drawing

foreach ($folder in $sizes.Keys) {
    $size = $sizes[$folder]
    $destFolder = Join-Path $targetPath $folder
    if (-not (Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder | Out-Null
    }
    
    $destFile = Join-Path $destFolder "ic_launcher.png"
    Write-Host "Generating $destFile ($size x $size)..."
    
    $bmp = [System.Drawing.Image]::FromFile((Resolve-Path $sourceFile))
    $newBmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($newBmp)
    
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    
    $g.DrawImage($bmp, 0, 0, $size, $size)
    
    $newBmp.Save($destFile, [System.Drawing.Imaging.ImageFormat]::Png)

    if ($folder -eq "mipmap-hdpi") {
        $notifFile = Join-Path $targetPath "drawable/ic_notification.png"
        Write-Host "Generating $notifFile (72 x 72)..."
        $newBmp.Save($notifFile, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    
    $g.Dispose()
    $newBmp.Dispose()
    $bmp.Dispose()
}

Write-Host "Done!"
