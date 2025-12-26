# ==========================================================
# Remove Kaspersky Security for Windows and Network Agent
# Works with/without WMIC (WMIC -> Registry fallback)
# Network Agent: Cleaner UC -> PC (password removed in KSC policy)
# ==========================================================

# ---------- CONFIG ----------
$KLLogin = "KLAdmin"
$KLPass  = "your-password-here"
$MsiSuccessCodes = @(0, 3010, 1641)

$Cleaner = "C:\ProgramData\KasperskyCleaner\cleaner.exe"

# Max minutes for each cleaner phase (/uc and /pc)
$CleanerMaxMinutesEach = 10
# ----------------------------

Write-Host "WHOAMI: $(whoami)"
Write-Host "START: Kaspersky removal workflow"

function Test-WmicAvailable {
    try {
        $null = cmd.exe /c "wmic /? 1>nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Get-GuidFromText {
    param([string[]]$Lines)
    $m = ($Lines | Select-String -Pattern "\{[0-9A-Fa-f\-]+\}" | Select-Object -First 1)
    if ($m) { return $m.Matches[0].Value }
    return $null
}

function Get-ProductGuid_WMIC {
    param([Parameter(Mandatory)][string]$NameLike) # e.g. %Kaspersky Endpoint Security%
    $cmd = 'wmic product where "Name like ''{0}''" get Name, IdentifyingNumber' -f $NameLike
    $out = cmd.exe /c $cmd 2>$null
    if (-not $out) { return $null }
    return (Get-GuidFromText -Lines $out)
}

function Get-ProductGuid_RegistryByDisplayNameRegex {
    param([Parameter(Mandatory)][string]$DisplayNameRegex)

    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $items = foreach ($r in $roots) {
        Get-ItemProperty $r -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and ($_.DisplayName -match $DisplayNameRegex) }
    }

    # Prefer real MSI product-code keys: {GUID}
    $guidItem = $items | Where-Object { $_.PSChildName -match "^\{[0-9A-Fa-f\-]+\}$" } | Select-Object -First 1
    if ($guidItem) { return $guidItem.PSChildName }

    # Fallback: extract from UninstallString if needed
    $any = $items | Select-Object -First 1
    if ($any) {
        $s = ($any.QuietUninstallString, $any.UninstallString) | Where-Object { $_ } | Select-Object -First 1
        if ($s) {
            $m = [regex]::Match($s, "\{[0-9A-Fa-f\-]+\}")
            if ($m.Success) { return $m.Value }
        }
    }
    return $null
}

function Uninstall-MSI_WithLogic {
    param([Parameter(Mandatory)][string]$Guid, [Parameter(Mandatory)][string]$Name)

    Write-Host "Uninstall MSI: $Name ($Guid)"

    Write-Host "Attempt 1: msiexec /x without password"
    $p1 = Start-Process "msiexec.exe" -ArgumentList "/x $Guid /qn /norestart" -Wait -PassThru
    if ($MsiSuccessCodes -contains $p1.ExitCode) {
        Write-Host "SUCCESS: $Name removed. ExitCode=$($p1.ExitCode)"
        return $true
    }

    Write-Host "Attempt 2: msiexec /x with KLLOGIN/KLPASSWD"
    $args = "/x $Guid KLLOGIN=$KLLogin KLPASSWD=$KLPass /qn /norestart"
    $p2 = Start-Process "msiexec.exe" -ArgumentList $args -Wait -PassThru

    if ($MsiSuccessCodes -contains $p2.ExitCode) {
        Write-Host "SUCCESS: $Name removed with password. ExitCode=$($p2.ExitCode)"
        return $true
    }

    Write-Host "FAILED: $Name uninstall failed. ExitCode=$($p2.ExitCode)"
    return $false
}

function Start-ProcessWithTimeout {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][int]$MaxMinutes
    )

    Write-Host "Run: `"$FilePath`" $Arguments (timeout ${MaxMinutes}m)"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
    $done = $p.WaitForExit($MaxMinutes * 60 * 1000)

    if (-not $done) {
        Write-Host "ERROR: Timed out. PID=$($p.Id)"
        return [pscustomobject]@{ Ok=$false; ExitCode=$null; TimedOut=$true }
    }

    return [pscustomobject]@{ Ok=$true; ExitCode=$p.ExitCode; TimedOut=$false }
}

# ----------------------------------------------------------
# PHASE 1: Kaspersky Endpoint Security for Windows (KES)
# ----------------------------------------------------------
Write-Host "--- Phase 1: Kaspersky Endpoint Security for Windows ---"

$wmicOk = Test-WmicAvailable
Write-Host "WMIC available: $wmicOk"

# Try multiple name patterns (sürüm/dil farkları için)
$kesGuid = $null
$kesName = "Kaspersky Endpoint Security for Windows"

if ($wmicOk) {
    foreach ($like in @("%Kaspersky Endpoint Security%","%Kaspersky Endpoint Security for Windows%")) {
        $kesGuid = Get-ProductGuid_WMIC -NameLike $like
        if ($kesGuid) { break }
    }
}

if (-not $kesGuid) {
    # Registry fallback: farklı isim varyantları
    $kesGuid = Get-ProductGuid_RegistryByDisplayNameRegex -DisplayNameRegex "Kaspersky\s+Endpoint\s+Security"
}

if ($kesGuid) {
    [void](Uninstall-MSI_WithLogic -Guid $kesGuid -Name $kesName)
} else {
    Write-Host "KES not found (WMIC/Registry)."
}

# ----------------------------------------------------------
# PHASE 2: Kaspersky Security Center Network Agent (Cleaner)
# ----------------------------------------------------------
Write-Host "--- Phase 2: KSC Network Agent (Cleaner UC -> PC) ---"

if (-not (Test-Path $Cleaner)) {
    Write-Host "ERROR: cleaner.exe not found at: $Cleaner"
    exit 1
}

$agentGuid = $null

if ($wmicOk) {
    $agentGuid = Get-ProductGuid_WMIC -NameLike "%Kaspersky Security Center Network Agent%"
}

if (-not $agentGuid) {
    $agentGuid = Get-ProductGuid_RegistryByDisplayNameRegex -DisplayNameRegex "^Kaspersky Security Center Network Agent$"
}

if (-not $agentGuid) {
    Write-Host "Network Agent not found (WMIC/Registry). Nothing to do."
    exit 0
}

Write-Host "Detected Network Agent GUID: $agentGuid"

# UC step
$uc = Start-ProcessWithTimeout -FilePath $Cleaner -Arguments "/uc `"$agentGuid`"" -MaxMinutes $CleanerMaxMinutesEach
if (-not $uc.Ok) { Write-Host "ERROR: /uc step failed or timed out."; exit 1 }
Write-Host "/uc completed. ExitCode=$($uc.ExitCode)"

# PC step
$pc = Start-ProcessWithTimeout -FilePath $Cleaner -Arguments "/pc `"$agentGuid`"" -MaxMinutes $CleanerMaxMinutesEach
if (-not $pc.Ok) { Write-Host "ERROR: /pc step failed or timed out."; exit 1 }
Write-Host "/pc completed. ExitCode=$($pc.ExitCode)"

# ----------------------------------------------------------
# VERIFICATION
# ----------------------------------------------------------
Write-Host "--- Verification ---"
Start-Sleep -Seconds 3

# Verify Network Agent gone (Registry check is most stable)
$agentGuidAfter = Get-ProductGuid_RegistryByDisplayNameRegex -DisplayNameRegex "^Kaspersky Security Center Network Agent$"
if ($agentGuidAfter) {
    Write-Host "VERIFY FAILED: Network Agent still present."
    exit 1
}
Write-Host "VERIFY SUCCESS: Network Agent removed."

Write-Host "DONE: Kaspersky cleanup process completed."
exit 0

Write-Host "DONE: Kaspersky cleanup process completed."
exit 0
