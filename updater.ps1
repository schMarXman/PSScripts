# Super simple universal updater script
# Self updateable, just put a new version in the update.zip.
# Launch parameters: -forceInstall -> Ignore version and perform complete new install (defined in: $forceInstallParam)
#                    -forceUpdate -> Ignore version and perform update (defined in: $forceUpdateParam)

# manifest.txt - Provides the latest version number on the server, as well as the url to the archive.
# Located on the server.
# format:
# <version number>
# <url to update zip>

# version.txt - Provides the currently installed version number.
# optional
# Located in the directory of the current installation.
# Will be created after first update, if not existing.
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

# exceptions.txt - Provides which files should not be replaced if an update is occuring. (Update: Current version == 0)
# optional
# Located in the update.zip
# same format as delete.txt

# preupdate.ps1 - Script to execute actions before updating. E.g. Killing all processes of the app.
# optional
# Located in the directory of the current installation.

# postupdate.ps1 - Script to execute actions after the update/update dependent actions.
# optional
# Located in the update.zip

function Get-TimeStamp {
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

# Returns true if $otherVersion is greater than $thisVersion.
# Can compare subversions like 1.1 > 1
function Test-VersionGreater {
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

function Remove-FileList {
    param (
        [string]$rootDir,
        [string[]]$fileList
    )
    foreach ($remove in $fileList) {
        Remove-Item "$rootDir\$remove" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$force = $args[0]

$forceUpdateParam = '-forceUpdate'
$forceInstallParam = '-forceInstall'

$manifestUrl = 'https://www.w3.org/TR/PNG/iso_8859-1.txt'
$manifestFile = 'manifest.txt'
$versionFile = 'version.txt'
$deleteFile = 'delete.txt'
$proxyFile = 'proxy.txt'
$exceptionsFile = 'exceptions.txt'
$updateFolder = 'tempupdate'
$updateFile = 'update.zip'
$preUpdateScript = 'preupdate.ps1'
$postUpdateScript = 'postupdate.ps1'

$updateLogFile = "updatelog.txt"
$updateLogMaxSize = 10MB

# delete updatelog if larger than 10 mb
if ((Test-Path -Path "$PSScriptRoot\$updateLogFile") -and ((Get-Item -Path "$PSScriptRoot\$updateLogFile").length -gt $updateLogMaxSize)) {
    Remove-Item -Path "$PSScriptRoot\$updateLogFile" -force
}

Start-Transcript -Path "$PSScriptRoot\$updateLogFile" -Append

Write-Output "$(Get-TimeStamp) Updater launched" 

# check for custom proxy
if (Test-Path -Path "$PSScriptRoot\$proxyFile") {
    Write-Output "$(Get-TimeStamp) Custom proxy found. Applying." 
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
Write-Output "$(Get-TimeStamp) Getting manifest ..." 
if ($null -ne $defaultProxy) {
    Invoke-WebRequest -Uri $manifestUrl -OutFile "$PSScriptRoot\$manifestFile" -Proxy $defaultProxy.Address -UseDefaultCredentials #-Credential $creds#$proxy.Credentials
    
    # Write-Output "$(Get-TimeStamp) ... with default proxy"
    # $webClient = New-Object net.webclient
    # $webClient.Proxy = $defaultProxy
    # $webClient.DownloadFile($manifestUrl, "$PSScriptRoot\$manifestFile")
}
else {
    Write-Output "$(Get-TimeStamp) ... with custom proxy"
    Invoke-WebRequest -Uri $manifestUrl -OutFile "$PSScriptRoot\$manifestFile"
}
Write-Output "$(Get-TimeStamp) Done" 

# if (!($force -like '-force') -and !(Test-Path -Path "$PSScriptRoot\$versionFile")) {
#     Write-Output "$(Get-TimeStamp) Cannot identify version. Version file missing. Exiting ..." 
#     exit
# }

# compare installed version and manifest version
if ((Test-Path -Path "$PSScriptRoot\$versionFile") -and !($force -like $forceInstallParam)) {
    $versionText = Get-Content -Path "$PSScriptRoot\$versionFile"
}
else {
    $versionText = 0
}
$currentVersion = $versionText

$manifestText = Get-Content -Path "$PSScriptRoot\$manifestFile"
$newVersion = $manifestText[0]

if (!($force -like $forceUpdateParam) -and !(Test-VersionGreater -thisVersion $currentVersion -otherVersion $newVersion)) {
    Write-Output "$(Get-TimeStamp) Current version is equal or higher. Exiting ..." 
    exit
} 

Write-Output "$(Get-TimeStamp) There's a newer version ($newVersion > $currentVersion)" 

# Execute preupdate script
if (Test-Path -Path "$PSScriptRoot\$preUpdateScript") {
    Write-Output "$(Get-TimeStamp) Executing pre update script" 
    & "$PSScriptRoot\$preUpdateScript"
}
else {
    Write-Output "$(Get-TimeStamp) No pre update script to execute" 
}

# download update
Write-Output "$(Get-TimeStamp) Downloading update ..."
if ($null -ne $defaultProxy) {
    Write-Output "$(Get-TimeStamp) ... with default proxy" 
    Invoke-WebRequest -Uri $manifestText[1] -OutFile "$PSScriptRoot\$updateFile" -Proxy $defaultProxy.Address -UseDefaultCredentials
    #$webClient.DownloadFile($manifestText[1], "$PSScriptRoot\$updateFile")
}
else {
    Write-Output "$(Get-TimeStamp) ... with custom proxy" 
    Invoke-WebRequest -Uri $manifestText[1] -OutFile "$PSScriptRoot\$updateFile"
}
# debug
# Copy-Item -Path "$PSScriptRoot\update_orig.zip" -Destination "$PSScriptRoot\$updateFile" -Force
Write-Output "$(Get-TimeStamp) Done" 

Write-Output "$(Get-TimeStamp) Unpacking files" 
Expand-Archive -LiteralPath "$PSScriptRoot\$updateFile" -DestinationPath "$PSScriptRoot\$updateFolder" -Force
Write-Output "$(Get-TimeStamp) Done" 

# If exceptions.txt exists and this is an update not a new installation
if ((Test-Path -Path "$PSScriptRoot\$updateFolder\$exceptionsFile") -and ($currentVersion -ne 0)) {
    Write-Output "$(Get-TimeStamp) Deleting files not needed for the update"
    $exceptionsFiles = Get-Content -Path "$PSScriptRoot\$updateFolder\$exceptionsFile"
    Remove-FileList -rootDir "$PSScriptRoot\$updateFolder" -fileList $exceptionsFiles
    Write-Output "$(Get-TimeStamp) Done"
}

# Copy update folder
Write-Output "$(Get-TimeStamp) Applying update" 
Copy-Item -Path "$PSScriptRoot\$updateFolder\*" -Destination $PSScriptRoot -Recurse -Force
Write-Output "$(Get-TimeStamp) Done"

# Check for list of files to delete and delete them
if (Test-Path -Path "$PSScriptRoot\$deleteFile") {
    Write-Output "$(Get-TimeStamp) Deleting old files" 
    $deleteFiles = Get-Content -Path "$PSScriptRoot\$deleteFile"
    Remove-FileList -rootDir $PSScriptRoot -fileList $deleteFiles
    Write-Output "$(Get-TimeStamp) Done" 
}
else {
    Write-Output "$(Get-TimeStamp) No old files to delete" 
}

# Check for postupdate script then execute
if (Test-Path -Path "$PSScriptRoot\$postUpdateScript") {
    Write-Output "$(Get-TimeStamp) Executing post update script" 
    & "$PSScriptRoot\$postUpdateScript"
}
else {
    Write-Output "$(Get-TimeStamp) No post update script to execute" 
}

# Update version
Out-File -FilePath "$PSScriptRoot\$versionFile" -InputObject $newVersion -Force

# Clean up
Write-Output "$(Get-TimeStamp) Cleaning up" 
Remove-Item "$PSScriptRoot\$manifestFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$deleteFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$updateFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$exceptionsFile" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$postUpdateScript" -Force -ErrorAction SilentlyContinue
Remove-Item "$PSScriptRoot\$updateFolder" -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "$(Get-TimeStamp) All done. Program updated to version $newVersion." 

Stop-Transcript