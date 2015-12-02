# http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2107096
#reate encrypted credential file if you do not have SSO working.
# New-VICredentialStoreItem -Host '192.168.1.10' -User 'admin' -Password 'password' -File ".\Windowscreds.xml"
<#
[vmware_dc]
pattern = ^vmware\.dc\.*
retentions = 60s:30d, 5m:365d

[vmware_vms]
pattern = ^vmware\.vm\.*
retentions = 20s:14d, 60s:60d, 5m:365d

[vmware_hosts]
pattern = ^vmware\.hosts\.*
retentions = 20s:14d, 60s:60d, 5m:365d

[vmware_perf]
pattern = ^vmware\.perf\.*
retentions = 60s:30d, 5m:365d
#>

Param
    (
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [switch]$Print
    )


$Credfile = ".\Windowscreds.xml"
$base = "vmware"

$carbonServer = "192.168.1.54"
$carbonServerPort = 2003

$ESXiMetricCounters = "cpu.*","mem.*","net.*","disk.*","datastore.*","storage*"

try
    {
    Add-PSSnapin VMware.VimAutomation.Core

    Get-VICredentialStoreItem -File $Credfile | %{
    $VIConnection = Connect-VIServer -Server $_.host -User $_.User -Password $_.Password}
    }
catch
    {
    Write-Error $_
    }

function Send-ToGraphite {
    param(
        [string]$carbonServer,
        [string]$carbonServerPort,
        [string[]]$metrics
    )
      try
        {
        $socket = New-Object System.Net.Sockets.TCPClient 
        $socket.connect($carbonServer, $carbonServerPort) 
        $stream = $socket.GetStream() 
        $writer = new-object System.IO.StreamWriter($stream)
        foreach ($metric in $metrics){
          #  Write-Host $metric
            $newMetric = $metric.TrimEnd()
           $writer.WriteLine($newMetric) 
            }
        $writer.Flush()
        $writer.Close() 
        $stream.Close()
        }
        catch
        {
            Write-Error $_
        }
}

#function Get-VMGuestStats {
# $a = Get-VM | ? {$_.PowerState -eq "PoweredON"} 
# $a| % { Write-Host $_ ; Get-Stat -Entity $_ -Realtime -MaxSamples 1 -stat * | Sort-Object -Property metricID | ft -AutoSize
# Test-WF -vmserver $a -vcenter ($global:DefaultVIServer).Name -session ($global:DefaultVIServer).SessionSecret
Workflow Get-VMGuestStats {
    param(
        [string]$vcenter,
        [string[]]$vmserver,
        [string]$session,
        [Switch]$Print
    )
    foreach -parallel ($name in $vmserver){
      $vm = InlineScript{
            Add-PSSnapin VMware.VimAutomation.Core
            $WarningPreference = "SilentlyContinue";
            (Connect-VIServer -Server $Using:vcenter -Session $Using:session) 2>&1 | out-null
            $WarningPreference = "Continue"; 
            #$vmStats = Get-Stat -Entity $Using:name -Realtime -MaxSamples 1 -stat "*"
            $vmStats = Get-Stat -Entity $Using:name -IntervalSecs 1 -MaxSamples 3 -stat "*"
            $countvmMetrics = 0
            foreach($stat in $vmStats){
                $time = $stat.Timestamp
                $date = [int][double]::Parse((Get-Date -Date $time -UFormat %s))
                $metric = ($stat.MetricId).Replace(".latest","").split(".")
                $value = $stat.Value
                $unit = ($stat.Unit).Replace("%","Percent")
                $instance = ($stat.instance).Split(".,/,_,:")[-1]
                $vmName = $($Using:name).Replace(" ","-").Replace(".","-").Replace(")","").Replace("(","").ToLower()
                if($instance -and $metric[0] -ne "sys"){
                 $result = "1 vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$instance.$($metric[2])$unit $value $date"}
                elseif($metric[0] -eq "sys" -and $instance){
                 $result = "2 vmware.vm.$($vmName).$($metric[0]).$($metric[1])_$($instance).$unit $value $date"}
                else {
                 $result = "3 vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$($metric[2])$unit $value $date"}
                 if($Using:Print){
                 Write-Output $result}
                 $vmMetrics += $result
                 $countvmMetrics = $countvmMetrics + 1
               }
                 Write-Output "-- VM Metrics      : $countvmMetrics"
             }
        $vm
        }

   }

#}

function Get-VMHostStats {
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [string]$cluster,

        [Parameter(Mandatory=$false)]
        [Switch]$Print
    )
    $countESXiMetrics = 0
    # Collect get-stat for VMHosts #Changes every 300s
    $vmhosts = (Get-VMHost -Location $cluster) | sort
    foreach ($VMhost in $vmhosts){
        [string[]]$hostMetrics = @()
        $datacenter = (Get-Datacenter -VMHost $VMhost).Name.ToLower()
        $vmhStats = Get-Stat -Entity (Get-VMHost "$VMhost") -IntervalSecs 1 -MaxSamples 3 -stat $ESXiMetricCounters
        Write-Output $VMhost.Name
        foreach($stat in $vmhStats)
           {
            $time = $stat.Timestamp
       #     $date = [int][double]::Parse((Get-Date -Date $time -UFormat %s))
            $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
            $metric = ($stat.MetricId).Replace(".latest","").split(".")
            $value = $stat.Value
            $unit = ($stat.Unit).Replace("%","Percent")
            $VMhostS = ($VMhost.Name).Split(".")[0]
            $clusterS = ($cluster).toString().Replace(" ","").ToLower()
            $instance = ($stat.instance).Split(".,/,_,:")[-1]
            if($instance -and $metric[0] -ne "sys") {
                    $result = "$base.hosts.$datacenter.$clusterS.$VMhostS.$($metric[0])_$($metric[1]).$instance.$($metric[2])$unit $value $date"
                    }
            elseif($metric[0] -eq "sys" -and $instance){
                    $result = "$base.hosts.$datacenter.$clusterS.$VMhostS.$($metric[0]).$($metric[1])_$($instance).$unit $value $date"
                    }
            else {
                    $result = "$base.hosts.$datacenter.$clusterS.$VMhostS.$($metric[0])_$($metric[1]).$($metric[2])$unit $value $date"
                    }
             if($Print){
                Write-Output $result
            }
            $hostMetrics += $result
            $countESXiMetrics = $countESXiMetrics + 1
     #       $global:VMHostMetricTime = $time
           }
     #      Write-Host $hostMetrics.Count
           Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $hostMetrics
    }
        Write-Output "-- ESXi Metrics      : $countESXiMetrics"
}

function Get-ClusterStats {
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [string]$datacenter,

        [Parameter(Mandatory=$false)]
        [Switch]$Print
    )
    #Collect get-stat for Clusters #Changes every 300s
    $clusters = (Get-Cluster -Location $datacenter) | sort
    foreach ($cluster in $clusters){
        $countClusterMetrics = 0
        [string[]]$clusterMetrics = @()
        $clsStats = Get-Stat -Entity (Get-Cluster "$cluster") -Realtime -MaxSamples 2 -stat "cpu.*","mem.*" | Sort-Object Timestamp
        Write-Output $cluster.Name
        foreach($stat in $clsStats)
           {
            $time = $stat.Timestamp
            #$date = [int][double]::Parse((Get-Date -Date $time -UFormat %s))
            $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
            $metric = (($stat.MetricId).Replace(".latest","")).Replace("vmop.","").split(".")
            $value = $stat.Value
            $clusterS = ($cluster).toString().Replace(" ","").ToLower()

            if ($metric.Count -gt 2)
            {
                $result = "$base.dc.$datacenter.$clusterS.$($metric[0])_$($metric[1]).$($metric[2]) $value $date"
            }
            else
            {
                $result = "$base.dc.$datacenter.$clusterS.$($metric[0]) $value $date"
            }
            $clusterMetrics += $result
            
            if($Print){
                Write-Output "$result"}
            $countClusterMetrics = $countClusterMetrics + 1

           }
        Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $clusterMetrics 
        Write-Output "-- Cluster Metrics   : $countClusterMetrics"
        $global:clusterMetricTime = $time
    
    #    We will call ESX Host from the main loop as we need to collect 20s stats.
    #    if($Print){
    #    Get-VMHostStats $cluster -Print}
    #    else {Get-VMHostStats $cluster}
    }

}
function Get-DataCenterStats {
    Param
    (
        [Parameter(Mandatory=$false)]
        [Switch]$Print
    )
    $countDataCenterMetrics = 0
    #Collect get-stat for DataCenter #Changes every 300s
    $datacenters = (Get-Datacenter) | sort
    foreach ($datacenter in $datacenters){
        [string[]]$dcMetrics = @()
        $dcStats = Get-Stat -Entity (Get-DataCenter $datacenter) -Realtime -MaxSamples 1  -stat "*"
        Write-Output $datacenter.Name
        $dcName = ($datacenter.Name).tolower()
        foreach($stat in $dcStats)
           {
            $time = $stat.Timestamp
           # $date = [int][double]::Parse((Get-Date -Date $time -UFormat %s))
            $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
            $metric = (($stat.MetricId).Replace(".latest","")).Replace("vmop.","")
            $value = $stat.Value
            $result = "$base.dc.$dcName.$metric $value $date"
            $dcMetrics += $result
            if($Print){
                Write-Output "$result"}
            $countDataCenterMetrics = $countDataCenterMetrics + 1
           }
           Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $dcMetrics
           Write-Output "-- DataCenter Metrics: $countDataCenterMetrics"
           if($Print){
               Get-ClusterStats $dcName -Print}
               else {Get-ClusterStats $dcName}
    }
}

#######
#Start Jobs
while ($true)
{
    #DataCenter+Cluster Metrics (300 seconds apart)
#     Write-Output "Collecting @: $(get-date)"
    if ((get-date) -ge $nextClusterRun)
    {
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        if($Print){
            Get-DataCenterStats -Print}
            else {Get-DataCenterStats}
        "Total Elapsed Time Cluster: $($elapsed.Elapsed.ToString())"
        #calculate difference 
        $nextClusterRun = ($global:clusterMetricTime).AddSeconds(340)
     #   $nextClusterRun = (get-date).AddSeconds(300)
        $ClustertimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextClusterRun
        Write-Output "Metric receive at: $global:clusterMetricTime -NextRun- $nextClusterRun -TimeDiff- $ClustertimeDiff -- Next collection in $($ClustertimeDiff.TotalSeconds) seconds"
    }
    
    #ESXi Metrics (20 seconds apart)
    #get clusters incase of multiple
    if ((get-date) -ge $nextVMHostRun)
    {
        $nextVMHostRun = (get-date -second 00).AddMinutes(1)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $VMHostClusters = (Get-VMHost).Parent.Name | sort -Unique
        foreach ($cluster in $VMHostClusters){
            if($Print){
                Get-VMHostStats $cluster -Print}
                else {Get-VMHostStats $cluster}
                } 
        "Total Elapsed Time ESXi Hosts: $($elapsed.Elapsed.ToString())"
        $VMHostTimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextVMHostRun
     #   Write-Output "Metric receive at: $global:VMHostMetricTime -- $nextVMHostRun -- $VMHostTimeDiff -- Next collection in $($VMHostTimeDiff.TotalSeconds) seconds"
    }
   
    if ([int]$($VMHostTimeDiff.TotalSeconds) -le 0) {}
    else {
        Write-Output "Sleeping $($VMHostTimeDiff.TotalSeconds) seconds"
        sleep $($VMHostTimeDiff.TotalSeconds)
    }
    $VMHostTimeDiff = 0
}
