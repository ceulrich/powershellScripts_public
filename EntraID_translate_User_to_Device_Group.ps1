<#	
	.NOTES
		Version:	1.0

		Changelog:
		v1.0	| CU |	initial version

		Requirements:
		This script requires an EntraID app registration with the following permissions:
			DeviceManagementManagedDevices.Read.All 
			GroupMember.ReadWrite.All 
			Group.ReadWrite.All 

	.DESCRIPTION
		This scipt translates a EntraID usergroup to an devicegroup. Source and targetgroups must be specified in input.csv
		CSV Header:
		UserGroup,DeviceGroup

	.EXAMPLE
		".\EntraID_translate_User_to_Device_Group.ps1"
#>

#parameter
$TenantId = "<TenantId>"
$ClientId = "<ClientId>"
$ClientSecret = "<ClientSecret>"

#script
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Write-Host "get acess token"
$body = @{
	Grant_Type    = "client_credentials"
	Scope		  = "https://graph.microsoft.com/.default"
	Client_Id	  = $ClientId
	Client_Secret = $ClientSecret
}

$connection = Invoke-RestMethod `
								-Uri https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token `
								-Method POST `
								-Body $body
$accessToken = $connection.access_token
$token = ConvertTo-SecureString -String "$($connection.access_token)" -AsPlainText -Force


Write-Host "Connect MgGraph"
Connect-MgGraph -AccessToken $token -NoWelcome

function main {
	$inputItems = Import-Csv -Path .\input.csv
	
	
	foreach ($inputItem in $inputItems) {
		Write-Host "UserGroup: $($inputItem.UserGroup), DeviceGroup: $($inputItem.DeviceGroup)"
		$userGroupName = $inputItem.DeviceGroup
		Translate-UserToDeviceGroup -userGroupName $inputItem.UserGroup -deviceGroupName $inputItem.DeviceGroup
	}
}

function Translate-UserToDeviceGroup
{
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$userGroupName,
		[Parameter(Mandatory = $true)]
		[string]$deviceGroupName
	)
	
	Write-Host "sync from $userGroupName to $deviceGroupName started"
	
	#prepare device group
	$deviceGroup = Get-MgGroup -Filter "DisplayName eq '$deviceGroupName'"
	if ($deviceGroup)
	{
		Write-Host "Group $deviceGroupName already exists. Cleaning up..."
		#clean group
		$oldDevices = Get-MgGroupMember -GroupId $deviceGroup.Id -All
		foreach ($oldDevice in $oldDevices)
		{
			Remove-MgGroupMemberByRef -GroupId $deviceGroup.Id -DirectoryObjectId $oldDevice.Id
		}
		Write-Host "wait 10 seconds for graph to resync"
		Start-Sleep 10
	}
	else
	{
		Write-Host "Group not exists. Create $deviceGroupName..."
		#create group
		$deviceGroup = New-MgGroup -DisplayName $deviceGroupName -MailEnabled:$False -MailNickName 'SPIRIT' -SecurityEnabled
	}
	
	
	#check user group
	$userGroup = Get-MgGroup -Filter "DisplayName eq '$userGroupName'"
	if ($userGroup)
	{
		$users = Get-MgGroupMember -GroupId $userGroup.Id -All
		Write-Host $users.Count
		foreach ($user in $users)
		{
			Write-Host "next user"
			Write-Host "user: $($user.id)"
			$devices = Get-MgUserOwnedDevice -UserId $user.id
			foreach ($device in $devices)
			{
				$deviceInformations = Get-MgDevice -DeviceId $device.id
				if (($deviceInformations.operatingSystem -eq "Windows") -and ($deviceInformations.deviceOwnership -eq "Company") -and ($deviceInformations.isManaged -eq "true"))
				{
					Write-Host "adding $($device.id) to $deviceGroupName"
					New-MgGroupMember -GroupId $deviceGroup.id -DirectoryObjectId $device.id
				}
				
			}
		}
		Write-Host "sync from $userGroupName to $deviceGroupName completed"
	}
	else
	{
		Write-Host "User group $userGroupName does not exist!"
	}
}

main
