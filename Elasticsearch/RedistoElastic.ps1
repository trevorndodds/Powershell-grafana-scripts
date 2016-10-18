#Send Redis LLEN to Elasticsearch

Param
    (
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        
        [switch]$Print
    )

$elasticIndex = "trev_test"
$elasticServer = ""
$elasticServerPort = 9200
$interval = 10

[string[]]$redisServers = "",""
$redisKey = "metricbeat"

function SendTo-ElasticSearch ($metrics, $elasticServer, $elasticServerPort, $elasticIndex, $indexDate)
{
    $json = $metrics | ConvertTo-Json
    #Write-Output $json

    Invoke-RestMethod "http://$elasticServer`:$elasticServerPort/$elasticIndex-$indexDate/message" -Method Post -Body $json -ContentType 'application/json'
}

function Get-RedisLLEN ($redisServer, $redisKey)
{
       $indexDate = [DateTime]::UtcNow.ToString("yyyy.MM.dd")
       try
       {
           $result = ./redis-cli.exe -h $redisServer llen $redisKey
           $redisMetricsRedis = @{}
           $redisMetricsRedis.Add("length", [int]$result)
           $redisMetricsRedis.Add("key",$redisKey)
           $redisMetrics.Add("redis",$redisMetricsRedis)
           $redisMetrics.Add("@timestamp",[DateTime]::Now.ToUniversalTime().ToString("o"))

           SendTo-ElasticSearch $redisMetrics $elasticServer $elasticServerPort $elasticIndex $indexDate

       }
       catch [System.Exception]
       {
           Write-Host "Error exception - $_"
       }
}

#StartJob
while ($true)
{
    if ((get-date) -ge $nextRun)
    {
        $nextRun = (get-date).AddSeconds($interval)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            if($Print){                                     }
                else {

                        foreach ($redisServer in $redisServers){
                            $redisMetrics = @{}
                            $redisMetricsHost = @{}
                            $redisMetricsHost.Add("hostname",$redisServer)
                            $redisMetrics.Add("beat",$redisMetricsHost)
                            Get-RedisLLEN $redisServer $redisKey }
                }

		"Total Elapsed Time: $($elapsed.Elapsed.ToString())"
        $TimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextRun
    }

 if ([int]$($TimeDiff.TotalSeconds) -le 0) {}
    else {
        Write-Output "Sleeping $($TimeDiff.TotalSeconds) seconds"
        sleep $($TimeDiff.TotalSeconds)
    }
    $TimeDiff = 0

}
