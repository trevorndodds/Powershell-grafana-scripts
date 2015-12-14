Param
    (
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [switch]$Print,
        [switch]$Serial,
        [switch]$Parallel,
        [switch]$Batch
    )

$carbonServer = "192.168.1.54"
$carbonServerPort = 2003
$Credfile = ".\Windowscreds.xml"
$base = "vmware"

function Connect-TovCenter {
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

}

Connect-TovCenter

    #function Get-VMGuestStats {
# $a = Get-VM | ? {$_.PowerState -eq "PoweredON"} 
# $a| % { Write-Host $_ ; Get-Stat -Entity $_ -Realtime -MaxSamples 1 -stat * | Sort-Object -Property metricID | ft -AutoSize
# Get-VMGuestStats -vmserver $a -vcenter ($global:DefaultVIServer).Name -session ($global:DefaultVIServer).SessionSecret
Workflow Get-VMGuestStats {
    param(
        [string]$vcenter,
        [string[]]$vmserver,
        [string]$session,
        [Switch]$Print
    )
    foreach -parallel -ThrottleLimit 4 ($name in $vmserver){
      $vm = InlineScript  {
            if (-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {Add-PSSnapin VMware.VimAutomation.Core}

            $carbonServer = "192.168.1.54"
            $carbonServerPort = 2003

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

            $WarningPreference = "SilentlyContinue";
            (Connect-VIServer -Server $Using:vcenter -Session $Using:session) 2>&1 | out-null
            $WarningPreference = "Continue"; 
            $vmStats = Get-Stat -Entity $Using:name -IntervalSecs 1 -MaxSamples 3 -stat "*"
            $countvmMetrics = 0
            [string[]]$vmMetrics = @()
            foreach($stat in $vmStats){
                    $time = $stat.Timestamp
                    $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
                    $metric = ($stat.MetricId).Replace(".latest","").split(".")
                    $value = $stat.Value
                    $unit = ($stat.Unit).Replace("%","Percent")
                    $instance = ($stat.instance).Split(".,/,_,:")[-1]
                    $vmName = $($Using:name).Replace(" ","-").Replace(".","-").Replace(")","").Replace("(","").ToLower()
                    if($instance -and $metric[0] -ne "sys"){
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$instance.$($metric[2])$unit $value $date"}
                    elseif($metric[0] -eq "sys" -and $instance){
                     $result = "vmware.vm.$($vmName).$($metric[0]).$($metric[1])_$($instance).$unit $value $date"}
                    else {
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$($metric[2])$unit $value $date"}
                     if($Using:Print){
                     Write-Output $result}
                     $vmMetrics += $result
                     $countvmMetrics = $countvmMetrics + 1
                   }
                  # Write-Output $vmMetrics
                 # Write-Output $vmMetrics.count
            Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $vmMetrics
           # Write-Output "-- VM Metrics      : $countvmMetrics"
             }
        $vm
        }
       $carbonServer = "192.168.1.54"
       $carbonServerPort = 2003
       $result = "vmware.perf.PoweredOn $($vmserver.count) $([int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s)))"
       Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $result
   }

#}

#### Test SerialTime to Collect VMs



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
            $newMetric = $metric.TrimEnd()
        #    write-host $newMetric
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


function Get-VMGuestStatsSerial {
  param(
        [Switch]$Print
    )
    $VMs = Get-VM | ? {$_.PowerState -eq "PoweredON"}
    $result = "vmware.perf.PoweredOn $($VMs.count) $([int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s)))"
    Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $result
        foreach ($vm in $VMs){
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            $vmStats = Get-Stat -Entity $vm -IntervalSecs 1 -MaxSamples 4 -stat "*"
            "Total Elapsed Time getting vmStats: $($elapsed.Elapsed.ToString())"
            $countvmMetrics = 0
            [string[]]$vmMetrics = @()
            foreach($stat in $vmStats){
                    $time = $stat.Timestamp
                    $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
                    $metric = ($stat.MetricId).Replace(".latest","").split(".")
                    $value = $stat.Value
                    $unit = ($stat.Unit).Replace("%","Percent")
                    $instance = ($stat.instance).Split(".,/,_,:")[-1]
                    $vmName = $($vm.Name).Replace(" ","-").Replace(".","-").Replace(")","").Replace("(","").ToLower()
                    if($instance -and $metric[0] -ne "sys"){
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$instance.$($metric[2])$unit $value $date"}
                    elseif($metric[0] -eq "sys" -and $instance){
                     $result = "vmware.vm.$($vmName).$($metric[0]).$($metric[1])_$($instance).$unit $value $date"}
                    else {
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$($metric[2])$unit $value $date"}
                     if($Print){
                     Write-Output $result}
                     $vmMetrics += $result
                     $countvmMetrics = $countvmMetrics + 1
                   }
                "Total Elapsed Time converting metrics: $($elapsed.Elapsed.ToString())"
                Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $vmMetrics
                "Total Elapsed Time all: $($elapsed.Elapsed.ToString())"
                Write-Output "-- VM Metrics      : $countvmMetrics"
    }

}


function Get-VMGuestStatsBatch {
  param(
        [Switch]$Print
    )
    $VMs = Get-VM | ? {$_.PowerState -eq "PoweredON"}
    $result = "vmware.perf.PoweredOn $($VMs.count) $([int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s)))"
    Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $result

            $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            $vmStats = Get-Stat -Entity $VMs -IntervalSecs 1 -MaxSamples 3 -stat "*"
            "Total Elapsed Time getting vmStats: $($elapsed.Elapsed.ToString())"
            $vmMetrics = New-Object System.Collections.ArrayList
            foreach($stat in $vmStats){
                    $time = $stat.Timestamp
                    $date = [int][double]::Parse((Get-Date (Get-Date $time).ToUniversalTime() -UFormat %s))
                    $metric = ($stat.MetricId).Replace(".latest","").split(".")
                    $value = $stat.Value
                    $unit = ($stat.Unit).Replace("%","Percent")
                    $instance = ($stat.instance).Split(".,/,_,:")[-1]
                    $vmName = ($stat.Entity).toString().Replace(" ","-").Replace(".","-").Replace(")","").Replace("(","").ToLower()
                    if($instance -and $metric[0] -ne "sys"){
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$instance.$($metric[2])$unit $value $date"}
                    elseif($metric[0] -eq "sys" -and $instance){
                     $result = "vmware.vm.$($vmName).$($metric[0]).$($metric[1])_$($instance).$unit $value $date"}
                    else {
                     $result = "vmware.vm.$($vmName).$($metric[0])_$($metric[1]).$($metric[2])$unit $value $date"}
                     if($Print){
                     Write-Output $result}
                     $vmMetrics.Add($result) | out-null
                   #  "Total Elapsed Time adding to result metrics: $($elapsed.Elapsed.ToString())"
                   }
                "Total Elapsed Time converting metrics: $($elapsed.Elapsed.ToString())"
                Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $vmMetrics
              #  $vmMetrics | Out-File .\data.out
                "Total Elapsed Time all: $($elapsed.Elapsed.ToString())"
                Write-Output "-- VM Metrics      : $($vmMetrics.Count)"

}





#######
#Start Jobs
while ($true)
{

if(!($Serial -or $Parallel))
    {$Batch = $true}


if($Batch){
    if ((get-date) -ge $nextVMRun){
        $nextVMRun = (get-date -second 00).AddMinutes(1)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            if($Print){
                        Get-VMGuestStatsBatch -Print
                    }
                else {Get-VMGuestStatsBatch}
        "Total Elapsed Time VM Guests: $($elapsed.Elapsed.ToString())"
        $VMHostTimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextVMRun
        }

}


if($Serial){
    #Run Serial fetch
    if ((get-date) -ge $nextVMRun){
        $nextVMRun = (get-date -second 00).AddMinutes(1)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            if($Print){
                        Get-VMGuestStatsSerial -Print
                    }
                else {Get-VMGuestStatsSerial}
        "Total Elapsed Time VM Guests: $($elapsed.Elapsed.ToString())"
        $VMHostTimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextVMRun
        }
    }
    
if($Parallel) {
    #VM Metrics (20 seconds apart)
    #get VMs
    if ((get-date) -ge $nextVMRun)
    {
        $nextVMRun = (get-date -second 00).AddMinutes(1)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $VMs = Get-VM | ? {$_.PowerState -eq "PoweredON"} 
            if($Print){
                        Get-VMGuestStats -vmserver $VMs -vcenter ($global:DefaultVIServer).Name -session ($global:DefaultVIServer).SessionSecret -Print
                    }
                else {Get-VMGuestStats -vmserver $VMs -vcenter ($global:DefaultVIServer).Name -session ($global:DefaultVIServer).SessionSecret}

        #"Total Elapsed Time VM Guests: $($elapsed.ElapsedMilliseconds)"
        "Total Elapsed Time VM Guests: $($elapsed.Elapsed.ToString())"
        $VMHostTimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextVMRun
     #   Write-Output "Metric receive at: $global:VMHostMetricTime -- $nextVMHostRun -- $VMHostTimeDiff -- Next collection in $($VMHostTimeDiff.TotalSeconds) seconds"
    }
}
    if ([int]$($VMHostTimeDiff.TotalSeconds) -le 0) {}
    else {
        Write-Output "Sleeping $($VMHostTimeDiff.TotalSeconds) seconds"
        sleep $($VMHostTimeDiff.TotalSeconds)
    }
    $VMHostTimeDiff = 0
}
