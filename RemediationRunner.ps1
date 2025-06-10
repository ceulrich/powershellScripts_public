<#
.SYNOPSIS
    This script runs an intune remediation on a single device or to a list of devices provided as CSV file.

.CHANGES
    Version 1.0 (2025-06-10):
    - Initial release
    - Basic functionality to run remediation on a specific device
    - CSV file support
    - Select target remediation script from Out-Grid

.DESCRIPTION
    The scipt prompts the user for an devicename if no csv file is specified with the parameter -csvPath.
    If the parameter -csvPath is used the script will check if the path is valid and if the CSV Header is "DeviceName".
    After that the script connects to the GraphAPI and lists all remediation scripts in an Out-GridView.
    There you have to select the remediation you like to run on the target device(s).

.NOTES
    - Ensure that you have the Microsoft.Graph module installed before running this script.
    - The following GraphAPI rights are necessary:
        - DeviceManagementConfiguration.ReadWrite.All
        - DeviceManagementScripts.Read.All
        - DeviceManagementManagedDevices.PrivilegedOperations.All
        - DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR

    Original script by Cedric Ulrich https://github.com/ceulrich
    Version        : 1.0
    Creation Date  : 2025-06-10
    Last Modified  : 2025-06-10

.EXAMPLE
    For CSV input use:
    PS .\RemediationRunner.ps1 -csvPath .\devices.csv

    For single device use:
    PS .\RemediationRunner.ps1
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $csvPath
)

if ($csvPath) {
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
    $deviceNames = Import-Csv -Path $csvPath
}
else {
    $deviceNames = Read-Host "Enter the Devicename"
}

Connect-MgGraph -NoWelcome
$response  = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Method GET
$remediationScripts = $response.value | Select-Object @{Name="DisplayName";Expression={$_.displayName}},
                                                @{Name="ID";Expression={$_.id}}, 
                                                @{Name="Description";Expression={$_.description}}, 
                                                @{Name="Created Date";Expression={$_.createdDateTime}}

$selectedScripts = $remediationScripts | Out-GridView -Title "Select a Remediation Script" -OutputMode Single #-PassThru -OutputMode Single
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