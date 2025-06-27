<#
.SYNOPSIS
    Runs an Intune remediation script on one or more Windows devices.

.CHANGES
    Version 1.2 (2025-06-16):
    - Added parameter -entraIdGroupName to target devices from an Entra ID group
    Version 1.1 (2025-06-10):
    - added switch for -allDevices
    Version 1.0 (2025-06-10):
    - Initial release
    - Basic functionality to run remediation on a specific device
    - CSV file support
    - Select target remediation script from Out-Grid

.DESCRIPTION
    This script allows you to trigger an Intune remediation (Proactive Remediation) on:
    - A single device (prompted by name)
    - All Windows devices in Intune
    - A list of devices provided via a CSV file
    - All devices that are members of a specified Entra ID group

    The script connects to Microsoft Graph, lists available remediation scripts for selection, and then triggers the selected remediation on the target device(s).

.PARAMETER csvPath
    Path to a CSV file containing device names. The CSV must have a header "DeviceName" and one device name per row.
    Example:
        DeviceName
        Device1
        Device2

.PARAMETER allDevices
    If specified, the script will run the remediation on all Windows devices in Intune. This overrides the csvPath or entraIdGroupName parameter.

.PARAMETER entraIdGroupName
    If specified, the script will run the remediation on all devices that are members of the given Entra ID (Azure AD) group.
    The group should contain device objects. This overrides the csvPath parameter if both are provided.

.NOTES
    Requirements:
    - Microsoft.Graph PowerShell module must be installed.
    - The following Graph API permissions are required:
        - DeviceManagementConfiguration.ReadWrite.All
        - DeviceManagementScripts.Read.All
        - DeviceManagementManagedDevices.PrivilegedOperations.All
        - DeviceManagementManagedDevices.ReadWrite.All

    Author: Cedric Ulrich
    Version: 1.2
    Creation Date: 2025-06-10
    Last Modified: 2025-06-16

.EXAMPLE
    PS .\RemediationRunner.ps1 -csvPath .\devices.csv
    Runs the selected remediation on all devices listed in devices.csv.

.EXAMPLE
    PS .\RemediationRunner.ps1
    Prompts for a device name and runs the selected remediation on that device.

.EXAMPLE
    PS .\RemediationRunner.ps1 -allDevices
    Runs the selected remediation on all Windows devices in Intune.

.EXAMPLE
    PS .\RemediationRunner.ps1 -entraIdGroupName "My Device Group"
    Runs the selected remediation on all devices in the specified Entra ID group.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $csvPath,
    [switch]
    $allDevices,
    [string]
    $entraIdGroupName
)

Connect-MgGraph -NoWelcome
if ($allDevices){
    #get all deviceNames
    $deviceNames = Get-MgDeviceManagementManagedDevice -All -Filter "operatingSystem eq 'Windows'" | Select-Object -ExpandProperty DeviceName
}
elseif ($entraIdGroupName) {
    $deviceNames = @()
    $groupMembers = Get-MgGroupMember -GroupId (Get-MgGroup -Filter "displayName eq '$entraIdGroupName'").Id -All
    foreach ($groupMember in $groupMembers) {
        $deviceName = Get-MgDevice -DeviceId $($groupMember.Id) | Select-Object -ExpandProperty DisplayName
        if ($deviceName -eq $null) {
            Write-Host "$($groupMember.Id) is not a device." -ForegroundColor Red
        }
        else {
            $deviceNames += $deviceName
        }
    }
    Write-Host $deviceNames.Count 
}
elseif($csvPath) {
    #Validate CSV path
    if(-not(Test-Path $csvPath))
    {
        Write-Host "Error: The specified CSV file was not found." -ForegroundColor Red
        exit 1
    }

    # Validate CSV header
    $csvHeader = Get-Content -Path $csvPath -TotalCount 1
    if ($csvHeader -ne "DeviceName") {
        Write-Host "Error: The CSV file must have 'DeviceName' as the header in the first row." -ForegroundColor Red
        Write-Host "Current header is: $csvHeader" -ForegroundColor Yellow
        Write-Host "The CSV file should have the following format:"
        Write-Host "DeviceName"
        Write-Host "Device1"
        Write-Host "Device2"
        Write-Host "..."

    }
    #read CSV
    $deviceNames = Import-Csv -Path $csvPath
}
else {
    #promt for deviceName
    $deviceNames = Read-Host "Enter the Devicename"
}


$response  = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Method GET
$remediationScripts = $response.value | Select-Object @{Name="DisplayName";Expression={$_.displayName}},
                                                @{Name="ID";Expression={$_.id}}, 
                                                @{Name="Description";Expression={$_.description}}, 
                                                @{Name="Created Date";Expression={$_.createdDateTime}}

$selectedScripts = $remediationScripts | Out-GridView -Title "Select a Remediation Script" -OutputMode Single #-PassThru
foreach ($selectedScript in $selectedScripts)
{
    foreach ($deviceName in $deviceNames)
    {
        $deviceID = (Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$deviceName'").Id
        Write-Host "Running: $($selectedScript.DisplayName) on $deviceName" -ForegroundColor Yellow
        $RemediationScript_URL = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$deviceID')/initiateOnDemandProactiveRemediation"                              
        $RemediationScript_Body = @{
        "ScriptPolicyId"="$($selectedScripts.ID)"
        }
        Invoke-MgGraphRequest -Uri $RemediationScript_URL -Method POST -Body $RemediationScript_Body
    }  
}
