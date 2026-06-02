<#
  Setup-Tapo-Emulator.ps1  --  one-shot installer for dad's Windows PC.

  What it does (no input needed):
    1. Elevates itself to Administrator.
    2. Downloads a Java runtime (Adoptium Temurin 17) -- portable, no install.
    3. Downloads Google's official Android command-line tools + emulator +
       platform-tools + an Android 14 (Google Play) x86_64 system image.
    4. Installs Google's official emulator accelerator (AEHD).
    5. Creates a phone virtual device called "Tapo".
    6. Installs the Tapo app IF you put its .apkm next to this script.
    7. Puts a "Tapo" shortcut on the Desktop. Double-click = Tapo on screen.

  HOW TO RUN: right-click this file -> "Run with PowerShell".
  (If Windows blocks it: open PowerShell and run
     powershell -ExecutionPolicy Bypass -File .\Setup-Tapo-Emulator.ps1 )

  Everything installs under:  %LOCALAPPDATA%\TapoEmulator
  Nothing else on the PC is touched. To uninstall: delete that folder + the
  Desktop shortcut (and optionally AEHD via "Apps").
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- elevate to admin (AEHD needs it) ----
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
# Elevate on a real PC; skip in CI (GitHub runners are already privileged + headless).
if (($env:GITHUB_ACTIONS -ne 'true') -and (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) {
  Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
  Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  return
}

# ---- config ----
$ScriptDir = Split-Path -Parent $PSCommandPath
$Root    = "$env:LOCALAPPDATA\TapoEmulator"
$SdkRoot = "$Root\sdk"
$CmdTools= "$SdkRoot\cmdline-tools\latest"
$JdkDir  = "$Root\jdk"
$AvdHome = "$Root\avd"
$AppDir  = "$Root\app"
$AvdName = "Tapo"
$Image   = "system-images;android-34;google_apis_playstore;x86_64"
$Device  = "pixel_6"
# Google's command-line tools (forward-compatible; bump if Google retires it):
$CmdUrl  = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$JdkUrl  = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"

New-Item -ItemType Directory -Force -Path $Root,$SdkRoot,$JdkDir,$AvdHome,$AppDir | Out-Null

function Get-File($url, $out) {
  Write-Host "  downloading: $url"
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

# ---- 1) Java (portable) ----
Write-Host "[1/7] Java runtime..." -ForegroundColor Cyan
if (-not (Get-ChildItem $JdkDir -Directory -ErrorAction SilentlyContinue)) {
  $jz = "$env:TEMP\tapo-jdk.zip"; Get-File $JdkUrl $jz
  Expand-Archive -Path $jz -DestinationPath $JdkDir -Force; Remove-Item $jz -Force
}
$Java = (Get-ChildItem $JdkDir -Directory | Select-Object -First 1).FullName
$env:JAVA_HOME = $Java
$env:PATH = "$Java\bin;$env:PATH"

# ---- 2) Android command-line tools ----
Write-Host "[2/7] Android command-line tools..." -ForegroundColor Cyan
if (-not (Test-Path "$CmdTools\bin\sdkmanager.bat")) {
  $cz = "$env:TEMP\tapo-cmdtools.zip"; Get-File $CmdUrl $cz
  $tmp = "$env:TEMP\tapo-cmdtools"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -Path $cz -DestinationPath $tmp -Force; Remove-Item $cz -Force
  New-Item -ItemType Directory -Force -Path $CmdTools | Out-Null
  Copy-Item "$tmp\cmdline-tools\*" $CmdTools -Recurse -Force
}
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME      = $SdkRoot
$env:ANDROID_AVD_HOME  = $AvdHome
$sdkmanager = "$CmdTools\bin\sdkmanager.bat"
$avdmanager = "$CmdTools\bin\avdmanager.bat"

# ---- 3) SDK packages (emulator, platform-tools, system image) ----
Write-Host "[3/7] Accepting licenses + downloading SDK (~1.5 GB, be patient)..." -ForegroundColor Cyan
$yes = ("y`r`n" * 60)
$yes | & $sdkmanager --sdk_root="$SdkRoot" --licenses | Out-Null
$yes | & $sdkmanager --sdk_root="$SdkRoot" "platform-tools" "emulator" "platforms;android-34" "$Image" "extras;google;Android_Emulator_Hypervisor_Driver"

# ---- 4) accelerator (AEHD) ----
Write-Host "[4/7] Installing emulator accelerator (AEHD)..." -ForegroundColor Cyan
$aehd = "$SdkRoot\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat"
if (Test-Path $aehd) {
  Push-Location (Split-Path $aehd)
  & cmd /c "`"$aehd`""
  Pop-Location
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "AEHD install returned $LASTEXITCODE. If the emulator is slow, enable CPU virtualization (VT-x / SVM) in the PC's BIOS, then re-run this script."
  }
} else {
  Write-Warning "AEHD installer not found; emulator may be slow without acceleration."
}

# ---- 5) virtual device ----
Write-Host "[5/7] Creating the 'Tapo' virtual device..." -ForegroundColor Cyan
$avds = & "$SdkRoot\emulator\emulator.exe" -list-avds
if (-not ($avds | Select-String "^$AvdName$")) {
  $createOut = ("no`r`n" | & $avdmanager create avd -n $AvdName -k "$Image" -d $Device 2>&1)
  $createOut | ForEach-Object { Write-Host "      $_" }
  $avds = & "$SdkRoot\emulator\emulator.exe" -list-avds
  if (-not ($avds | Select-String "^$AvdName$")) {
    throw "AVD '$AvdName' was not created (avdmanager output above). Devices: $(& $avdmanager list device 2>&1 | Select-String 'id:')"
  }
}
Write-Host "      virtual device ready: $AvdName"

# ---- 6) stage the Tapo app bundle ----
Write-Host "[6/7] Tapo app bundle..." -ForegroundColor Cyan
$apkm = Get-ChildItem "$ScriptDir\*.apkm" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($apkm) {
  Copy-Item $apkm.FullName $AppDir -Force
  Write-Host "      staged: $($apkm.Name)"
} else {
  Write-Warning "No .apkm found next to this script. Put the Tapo .apkm here and re-run, OR install Tapo from the Play Store inside the emulator after first launch."
}

# ---- 7) launcher + Desktop shortcut ----
Write-Host "[7/7] Creating launcher + Desktop shortcut..." -ForegroundColor Cyan
$Launcher = "$Root\Launch-Tapo.ps1"
$launcherBody = @'
# Launch-Tapo.ps1  (auto-generated) -- boots the emulator, ensures Tapo is
# installed, and opens it. Safe to run repeatedly; install only happens once.
$ErrorActionPreference = 'SilentlyContinue'
$Root    = "$env:LOCALAPPDATA\TapoEmulator"
$SdkRoot = "$Root\sdk"
$Java    = (Get-ChildItem "$Root\jdk" -Directory | Select-Object -First 1).FullName
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME      = $SdkRoot
$env:ANDROID_AVD_HOME  = "$Root\avd"
$env:JAVA_HOME = $Java
$adb = "$SdkRoot\platform-tools\adb.exe"
$emu = "$SdkRoot\emulator\emulator.exe"
$pkg = "com.tplink.iot"

# start the emulator if it is not already running (quick-boots from snapshot)
$running = & $adb devices 2>$null | Select-String 'emulator-\d+\s+device'
if (-not $running) {
  Start-Process -FilePath $emu -ArgumentList @('-avd','Tapo','-no-boot-anim','-netdelay','none','-netspeed','full','-gpu','auto')
}

# wait for full boot
& $adb wait-for-device 2>$null
for ($i = 0; $i -lt 150; $i++) {
  if ((& $adb shell getprop sys.boot_completed 2>$null).Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}

# install Tapo once (from the staged .apkm) if it is not present
$have = & $adb shell pm path $pkg 2>$null
if (-not $have) {
  $bundle = Get-ChildItem "$Root\app\*.apkm" | Select-Object -First 1
  if ($bundle) {
    $tmp = "$env:TEMP\tapo_apkm"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($bundle.FullName, $tmp)
    # split bundle has no x86; install the arm64 split (runs via the emulator's
    # built-in ARM->x86 translation). pixel_6 is xxhdpi (420dpi).
    $files = @("$tmp\base.apk")
    foreach ($n in @('split_config.arm64_v8a.apk','split_config.xxhdpi.apk','split_config.en.apk')) {
      if (Test-Path "$tmp\$n") { $files += "$tmp\$n" }
    }
    Get-ChildItem "$tmp\split_asset_pack*.apk" -ErrorAction SilentlyContinue | ForEach-Object { $files += $_.FullName }
    & $adb install-multiple -r -g $files
  }
}

# bring Tapo to the foreground
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
'@
Set-Content -Path $Launcher -Value $launcherBody -Encoding UTF8

$desktop = [Environment]::GetFolderPath('Desktop')
$ws  = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut("$desktop\Tapo.lnk")
$lnk.TargetPath       = "powershell.exe"
$lnk.Arguments        = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Launcher`""
$lnk.IconLocation     = "$SdkRoot\emulator\emulator.exe,0"
$lnk.WorkingDirectory = $Root
$lnk.Save()

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " DONE.  A 'Tapo' shortcut is on the Desktop." -ForegroundColor Green
Write-Host " Double-click it. First launch boots + installs Tapo (a few min);" -ForegroundColor Green
Write-Host " after that it quick-boots in seconds." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
if (($env:GITHUB_ACTIONS -ne 'true') -and ($env:TAPO_PACKAGED -ne '1')) { Read-Host "Press Enter to close" }
