function Update-SDNExpressMuxRoutes {
    <#
    Example
    $uri = "https://NCCluster.sdnlab.local"
    $Credential = Get-Credential "sdnlab\administrator"
    $computername = "muxvm001.sdnlab.local"
    $FrontEndRouter = "10.10.8.1"
    Update-SDNExpressMuxRoutes -ConnectionUri $uri -Credential $Credential -ComputerName $computername -FrontEndRouter $FrontEndRouter -Verbose
    #>
        [cmdletbinding()]
        param(
            [String]$ConnectionUri,
            [PSCredential]$Credential,
            [String]$ComputerName,
            [String]$FrontEndRouter
        )
    
        $session = New-PSSession -ComputerName $ComputerName -Credential $Credential
        if (-not ($session)) { throw "Unable to establish a PSSession to $ComputerName" }
        
        #Find all the HNVPA subnets
        $logicalNetworks = Get-NetworkControllerLogicalNetwork -ConnectionUri $uri -Credential $Credential
        $hnvpaSubnets = $logicalNetworks | where-object {$_.Properties.NetworkVirtualizationEnabled -eq "True"} | Select-Object -ExpandProperty Properties | Select-Object -ExpandProperty Subnets
        $PASubnets = @()
        foreach ($hvnpaSubnet in $hnvpaSubnets) { $PASubnets += $hvnpaSubnet.properties }
        
        #Identify this Mux to get BGP Router and FrontEnd Adapter information
        $MuxVirtualMachines = Get-NetworkControllerVirtualServer -ConnectionUri $uri -Credential $Credential
        $thisMuxVirtualResourceID = ($MuxVirtualMachines | where {$_.properties.Connections.managementAddresses -eq $computername}).ResourceID
        $Muxes = Get-NetworkControllerLoadBalancerMux -ConnectionUri $uri -Credential $Credential
        $thisMux = $muxes | where {$_.properties.virtualserver.resourceref -like "*$thisMuxVirtualResourceID"}
        
        #Find the BGP Router List 
        $routers = $thisMux.Properties.RouterConfiguration.PeerRouterConfigurations
        $routerIPs = @()
        foreach ($router in $routers) { $routerIPs += $router.RouterIPAddress }
        
        #Get the FrontEnd Adapter IP
        $FrontEndIP = $router.LocalIPAddress
    
        Invoke-Command -Session $session -ArgumentList ($FrontEndIP,$FrontEndRouter,$routerIPs,$PASubnets) -ScriptBlock { 
            param(
            [string]$FrontEndIP,
            [string]$FrontEndRouter,
            [string[]]$RouterIPs,
            [object[]]$PASubnets
            )
            #Find our current BackendNetwork
            $PARoute = get-netroute | where {$_.DestinationPrefix -in ($PASubnets).AddressPrefix}
            $ThisPASubnet = $PASubnets | where {$_.AddressPrefix -eq $PARoute.DestinationPrefix }
    
            #Determine which PA Networks are remote
            $RemotePASubnets = $PASubnets | where {$_.AddressPrefix -ne $PARoute.DestinationPrefix }
        
            #Determine which adapter is the back end adapter
            $PAAdapter = get-netadapter -InterfaceIndex $PARoute.InterfaceIndex
        
            #Determine which adater is the front end adapter (could be the same as the backend adapter), it will have the IP address specified as the front end ip from the NetworkControllerLoadBalancerMux object.
            $FrontEndAdapter = Get-NetAdapter -InterfaceIndex $( (Get-NetIPAddress | Where-Object {$_.ipaddress -eq $FrontEndIP}).InterfaceIndex )
        
    
            #We need a route to all the remote HNVPA networks through the HNVPA adapter
            foreach ($RemotePASubnet in $RemotePASubnets) {
              #If the route already exists this will generate an error 
              new-netroute -DestinationPrefix $RemotePASubnet.AddressPrefix -InterfaceIndex $PAAdapter.InterfaceIndex -AddressFamily IPv4 -NextHop $ThisPASubnet.DefaultGateways -RouteMetric 1
            }
    
            #We need a route to all BGP routers through the front end adapter, could be the same as the back end adapter
            foreach ($routerIP in $routerIPs) {
              new-netroute -DestinationPrefix "$routerIP/32" -InterfaceIndex $FrontEndAdapter.InterfaceIndex -AddressFamily IPv4 -NextHop $FrontEndRouter -RouteMetric 1
            }
    
        } #end invoke-command
    } #end Update-SDNExpressMuxRoutes
    
