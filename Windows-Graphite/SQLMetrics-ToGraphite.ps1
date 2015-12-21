<#

You can find extra metrics from the below command and append to $selectedMetrics
Get-Counter -ListSet "*"

#>

Param
    (
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [switch]$Print
    )


#Update HERE
$base = "database"
$selectedMetrics = "SQLServer:General Statistics","SQLServer:Memory Manager","SQLServer:Transactions","SQLServer:Buffer Manager","SQLServer:SQL Statistics"
$carbonServer = "192.168.1.54"
$carbonServerPort = 2003
$interval = 20

#No need to edit below	
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

function Get-WindowsSQLMetrics {
    Param
    (
        [Parameter(Mandatory=$false)]
        [Switch]$Print
    )
	$metrics = Get-Counter -Counter ((Get-Counter -ListSet $selectedMetrics).paths) -SampleInterval 1
	$mDate = $metrics.Timestamp
	$date = [int][double]::Parse((Get-Date (Get-Date $mDate).ToUniversalTime() -UFormat %s))
	$hostMetrics = New-Object System.Collections.ArrayList
	foreach ($metric in $metrics.CounterSamples)
		{
			 $mName = $metric.Path.split("\")[3].Split("(")[0].Replace(" ","_").split(":")
			 $mSubName = $metric.Path.split("\")[4].Replace(" ","_").Replace("%","percent").Replace(".","").Replace("/","_").Replace("(","").Replace(")","").Replace("[","_").Replace("]","_")
			 $mValue = $metric.CookedValue
			 if ($metric.InstanceName -ne $null) {
				$mInstance = $metric.InstanceName.Replace("_","").Replace(" ","_").Replace(":","").Replace(",","_").Replace("(","").Replace(")","").Replace("[","_").Replace("]","_").Split(".{")[0]
				$result = "$base.$(($env:computername).toLower()).$($mName[0]).$($mName[1]).$mInstance $mValue $date" 
			 }
 			 $result = "$base.$(($env:computername).toLower()).$($mName[0]).$($mName[1]).$mSubName $mValue $date" 
			 $hostMetrics.Add($result) | out-null
				 if($Print){
					Write-Output $result
				}
		 }
		 Send-ToGraphite -carbonServer $carbonServer -carbonServerPort $carbonServerPort -metric $hostMetrics
}

while ($true)
{
    if ((get-date) -ge $nextRun)
    {
        $nextRun = (get-date).AddSeconds($interval)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            if($Print){
                Get-WindowsSQLMetrics -Print}
                else {Get-WindowsSQLMetrics}

		"Total Elapsed Time ESXi Hosts: $($elapsed.Elapsed.ToString())"
        $TimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextRun
    }

 if ([int]$($TimeDiff.TotalSeconds) -le 0) {}
    else {
        Write-Output "Sleeping $($TimeDiff.TotalSeconds) seconds"
        sleep $($TimeDiff.TotalSeconds)
    }
    $TimeDiff = 0

}
