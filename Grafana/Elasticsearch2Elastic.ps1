#Requires -version 3.0
#ElasticSearch Cluster to Monitor
$elasticServer = "prod_cluster"
$elasticServerPort = 9200
$interval = 60

#ElasticSearch Cluster to Send Metrics
$elasticIndex = "elasticsearch_prod_metrics"
$elasticMonitoringCluster = "marvel_cluster"
$elasticMonitoringClusterPort = 9200

function SendTo-Elasticsearch ($json, $elasticMonitoringCluster, $elasticMonitoringClusterPort, $elasticIndex, $indexDate)
{
    try
    {
       Invoke-RestMethod "http://$elasticMonitoringCluster`:$elasticMonitoringClusterPort/$elasticIndex-$indexDate/message" -Method Post -Body $json -ContentType 'application/json'
    }
       catch [System.Exception]
       {
           Write-Host "SendTo-Elasticsearch exception - $_"
       } 
}

function Get-ElasticsearchClusterStats ($elasticServer)
{
    $indexDate = [DateTime]::UtcNow.ToString("yyyy.MM.dd")

    try
    {
        #Cluster Health
        $a = Invoke-RestMethod -Uri "http://$elasticServer`:$elasticServerPort/_cluster/health"
	$ClusterName = $a.cluster_name
        $a | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        $json = $a | convertTo-json
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticMonitoringClusterPort $elasticIndex $indexDate

        #Cluster Stats
        $a = Invoke-RestMethod -Uri "http://$elasticServer`:$elasticServerPort/_cluster/stats"
        $a | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        $json = $a | ConvertTo-Json -Depth 7
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticMonitoringClusterPort $elasticIndex $indexDate

        #Index Stats
        $a = Invoke-RestMethod -Uri "http://$elasticServer`:$elasticServerPort/_stats"
        $a._all | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        $a._all | add-member -Name "@timestamp" -Value $ClusterName -MemberType NoteProperty
        $json = $a.all | ConvertTo-Json -Depth 7
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticMonitoringClusterPort $elasticIndex $indexDate
	
        #Get Nodes
        $nodesraw = Invoke-RestMethod -Uri "http://$elasticServer`:$elasticServerPort/_cat/nodes?v&h=n"
        $nodes = $nodesraw -split '[\n]' | select -skip 1 | ? { $_ -ne "" } | % { $_.Replace(" ","") }

        #Node Stats
        foreach ($node in $nodes)
            {
            $a = Invoke-RestMethod -Uri "http://$elasticServer`:$elasticServerPort/_nodes/$node/stats"
            $nodeID = ($a.nodes | gm)[-1].Name
            $a.nodes.$nodeID | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
            $json = $a.nodes.$nodeID | ConvertTo-Json -Depth 7
            SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticMonitoringClusterPort $elasticIndex $indexDate
            }

    }
       catch [System.Exception]
       {
           Write-Host "Get-ElasticsearchClusterStats exception - $_"
       } 
}


while ($true)
{
    if ((get-date) -ge $nextRun)
    {
        $nextRun = (get-date).AddSeconds($interval)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        Get-ElasticsearchClusterStats $elasticServer
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
