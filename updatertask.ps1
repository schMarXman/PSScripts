# Registers updater.ps1 as a scheduled task daily at 00:00.

# elevate shell
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument  "$PSScriptRoot\updater.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 0am
$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$taskName = Read-Host -Prompt 'Task name?'
$taskDescription = Read-Host -Prompt 'Task description?'

Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description $taskDescription -Principal $principal