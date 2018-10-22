
function Update-DNSZonePermissionsForNetworkController  {
	[cmdletbinding()]
	param (
		[parameter(mandatory=$true)][string]$NetworkControllerComputerName
	)
	
	#Configure the DNS zone to be configurable by the Network Controllers.
	$guidNull = New-Object guid 00000000-0000-0000-0000-000000000000
	$Domain = get-addomain
	if ($domain) { 
		$DNSPartition = "DC=$($Domain.dnsroot),CN=MicrosoftDNS,$($Domain.SubordinateReferences | where {$_ -like "*DomainDns*"})"
		$DNSZoneObject = [ADSI]("LDAP://$($DNSPartition)")
		$NCVM = get-adcomputer $NetworkControllerComputerName
		if ($NCVM) { 
			$SID = [System.Security.Principal.SecurityIdentifier](Get-ADComputer $NetworkControllerComputerName).SID
			$ace = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($SID,"ReadProperty, WriteProperty, Delete, GenericExecute","Allow",$guidNull, "All", $guidNull)
			$DNSZoneObject.psbase.ObjectSecurity.AddAccessRule($ace)
			$DNSZoneObject.psbase.CommitChanges()
		} else {
			throw "$($NetworkControllerComputerName) is an invalid computer account."
		}
	} else {
		throw "Unable to get domain information, are the RSAT tools installed?"
	}
} #end Update-DNSZonePermissionsForNetworkController