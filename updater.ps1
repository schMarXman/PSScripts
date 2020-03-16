# Super simple universal updater script

# manifest.txt - Provides the latest version number on the server, as well as the link to the version.
# Located on the server.
# format:
# <version number>
# <link to update zip>

# version.txt - Provides the currently installed version number.
# Located in the directory of the current installation.
# format:
# <version number>

# delete.txt - Provides which files of the current installation will be deleted with the update.
# optional
# Located in the update.zip
# format:
# <relative file path to file or folder>
# <relative file path to file within folder>
# ...
# Example:
# file-or-folder-in-root-directory-to-delete.txt
# folder-in-root-directory/sub-file-to-delete.png

# postupdate.ps1 - Script to execute actions after the update/update dependent actions.
# optional
# Located in the update.zip

function Get-TimeStamp {
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function VersionIsGreater {
    param (
        [string]$thisVersion,
        [string]$otherVersion
    )
    $thisVersionSplitted = [Collections.Generic.List[String]]$thisVersion.Split('.')
    $otherVersionSplitted = [Collections.Generic.List[String]]$otherVersion.Split('.')

    if ($thisVersionSplitted.Count -gt $otherVersionSplitted.Count) {
        while ($otherVersionSplitted.Count -lt $thisVersionSplitted.Count) {
            $otherVersionSplitted.Add('0')
        }
    }
    elseif ($otherVersionSplitted.Count -gt $thisVersionSplitted.Count) {
        while ($thisVersionSplitted.Count -lt $otherVersionSplitted.Count) {
            $thisVersionSplitted.Add('0')
        }
    }

    for ($i = 0; $i -lt $thisVersionSplitted.Count; $i++) {
        if ($otherVersionSplitted[$i] -gt $thisVersionSplitted[$i]) {
            return $true
        }
    }

    return $false
}

function Set-Proxy {
    param (
        [string]$proxy,
        [string]$username,
        [securestring]$password
    )
    if ($null -eq $password) {
        $pw = ''
    }
    else {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        $pw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }

    $ProxyAddress = $proxy
    [system.net.webrequest]::defaultwebproxy = New-Object system.net.webproxy($ProxyAddress)
    $CredCache = [System.Net.CredentialCache]::new()
    $NetCreds = [System.Net.NetworkCredential]::new($username, $pw, "")
    $CredCache.Add($ProxyAddress, "Basic", $NetCreds)
    [system.net.webrequest]::defaultwebproxy.credentials = $CredCache
    [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
}

$ErrorActionPreference = "Stop"

$forceUpdate = $args[0]

$manifestUrl = 'https://www.w3.org/TR/PNG/iso_8859-1.txt'
$manifestFile = 'manifest.txt'
$versionFile = 'version.txt'
$deleteFile = 'delete.txt'
$proxyFile = 'proxy.txt'
$updateFile = 'update.zip'
$postUpdateScript = 'postupdate.ps1'

$updateLogFile = "updatelog.txt"
$updateLogMaxSize = 10MB

# delete updatelog if larger than 10 mb
if ((Test-Path -Path "$PSScriptRoot\$updateLogFile") -and ((Get-Item -Path "$PSScriptRoot\$updateLogFile").length -gt $updateLogMaxSize)) {
    Remove-Item -Path "$PSScriptRoot\$updateLogFile" -force
}

Start-Transcript -Path "$PSScriptRoot\$updateLogFile" -Append

Write-Output "$(Get-TimeStamp) Updater launched" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append

# check for custom proxy
if (Test-Path -Path "$PSScriptRoot\$proxyFile") {
    Write-Output "$(Get-TimeStamp) Custom proxy found. Applying." # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    $proxyContent = Get-Content -Path "$PSScriptRoot\$proxyFile"
    if ($proxyContent[2].Length -gt 0) {
        $secPW = ConvertTo-SecureString $proxyContent[2]
    }
    else {
        $secPW = $null
    }
    Set-Proxy -proxy $proxyContent[0] -username $proxyContent[1] -password $secPW
}
else {
    $defaultProxy = [System.Net.WebProxy]::GetDefaultProxy()
}

# Get manifest
Write-Output "$(Get-TimeStamp) Getting manifest ..." # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
if ($null -ne $defaultProxy) {
    Invoke-WebRequest -Uri $manifestUrl -OutFile "$PSScriptRoot\$manifestFile" -Proxy $defaultProxy.Address -UseDefaultCredentials #-Credential $creds#$proxy.Credentials
}
else {
    Invoke-WebRequest -Uri $manifestUrl -OutFile "$PSScriptRoot\$manifestFile"
}
Write-Output "$(Get-TimeStamp) Done" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append

# if (!($forceUpdate -like '-force') -and !(Test-Path -Path "$PSScriptRoot\$versionFile")) {
#     Write-Output "$(Get-TimeStamp) Cannot identify version. Version file missing. Exiting ..." # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
#     exit
# }

# compare installed version and manifest version
if (Test-Path -Path "$PSScriptRoot\$versionFile") {
    $versionText = Get-Content -Path "$PSScriptRoot\$versionFile"
}
else {
    $versionText = 0
}
$currentVersion = $versionText

$manifestText = Get-Content -Path "$PSScriptRoot\$manifestFile"
$newVersion = $manifestText[0]

if (!($forceUpdate -like '-force') -and !(VersionIsGreater -thisVersion $currentVersion -otherVersion $newVersion)) {
    Write-Output "$(Get-TimeStamp) Current version is equal or higher. Exiting ..." # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    exit
} 

# pre update script? kill all processes of app?

# download update
Write-Output "$(Get-TimeStamp) There's a newer version ($newVersion > $currentVersion)" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
if ($null -ne $defaultProxy) {
    Write-Output "$(Get-TimeStamp) Attempting download with default proxy" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    Invoke-WebRequest -Uri $manifestText[1] -OutFile "$PSScriptRoot\$updateFile" -Proxy $defaultProxy.Address -UseDefaultCredentials
}
else {
    Write-Output "$(Get-TimeStamp) Downloading" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    Invoke-WebRequest -Uri $manifestText[1] -OutFile "$PSScriptRoot\$updateFile"
}
# debug
# Copy-Item -Path "$PSScriptRoot\update_orig.zip" -Destination "$PSScriptRoot\$updateFile" -Force
Write-Output "$(Get-TimeStamp) Done" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append

Write-Output "$(Get-TimeStamp) Unpacking files" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
Expand-Archive -LiteralPath "$PSScriptRoot\$updateFile" -DestinationPath $PSScriptRoot -Force
Write-Output "$(Get-TimeStamp) Done" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append

# Check for list of files to delete and delete them
if (Test-Path -Path "$PSScriptRoot\$deleteFile") {
    Write-Output "$(Get-TimeStamp) Deleting old files" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    $deleteFiles = Get-Content -Path "$PSScriptRoot\$deleteFile"
    foreach ($delete in $deleteFiles) {
        Remove-Item "$PSScriptRoot\$delete" -Force -Recurse -ErrorAction SilentlyContinue
    }
    Write-Output "$(Get-TimeStamp) Done" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
}
else {
    Write-Output "$(Get-TimeStamp) No old files to delete" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
}

# Check for postupdate script then execute
if (Test-Path -Path "$PSScriptRoot\$postUpdateScript") {
    Write-Output "$(Get-TimeStamp) Executing post update script" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
    & "$PSScriptRoot\$postUpdateScript"
}
else {
    Write-Output "$(Get-TimeStamp) No post update script to execute" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
}

# Update version
Out-File -FilePath "$PSScriptRoot\$versionFile" -InputObject $newVersion -Force

# Clean up
Write-Output "$(Get-TimeStamp) Cleaning up" # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append
Remove-Item "$PSScriptRoot\$manifestFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$deleteFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$updateFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$postUpdateScript" -Force -ErrorAction SilentlyContinue

Write-Output "$(Get-TimeStamp) All done. Program updated to version $newVersion." # | Tee-Object "$PSScriptRoot\$updateLogFile" -Append

Stop-Transcript