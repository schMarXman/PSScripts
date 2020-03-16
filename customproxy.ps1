# Saves proxy settings to a text file

Write-Host 'Proxy Settings' -ForegroundColor Yellow
$proxyFile = 'proxy.txt'

$proxy = [System.Net.WebProxy]::GetDefaultProxy().Address.AbsoluteUri

$answer = ''
while ( !($answer -like 'y') -and !($answer -like 'n')) {
    $answer = Read-Host -Prompt "Is `'$proxy`' your proxy address? (y/n)"
}

if ($answer -like 'n') {
    $proxy = Read-Host -Prompt 'Enter your proxy address (schema: http://proxy:port)'
}

$username = Read-Host -Prompt 'Enter username'
$securePW = Read-Host -Prompt 'Enter password' -AsSecureString
if ($securePW.Length -gt 0) {
    $password = ConvertFrom-SecureString $securePW -ErrorAction SilentlyContinue
}
else {
    $password = ''
}

$content = "$proxy`r`n$username`r`n$password"
Out-File -FilePath "$PSScriptRoot\$proxyFile" -InputObject $content -Force

Read-Host -Prompt "Proxy settings saved. Press enter to exit"