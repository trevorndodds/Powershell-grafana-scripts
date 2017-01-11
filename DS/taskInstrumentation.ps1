#ElasticSearch Cluster to Send Metrics
$elasticIndex = "ds_task_instrumentation"
$elasticCluster = "http://server2:9200"
$indexDate = [DateTime]::UtcNow.ToString("yyyy.MM")

function SendTo-Elasticsearch ($json, $elasticCluster, $elasticIndex, $indexDate)
{
    try
    {
       Invoke-RestMethod "$elasticCluster/$elasticIndex-$indexDate/message" -Method Post -Body $json -ContentType 'application/json'
    }
       catch [System.Exception]
       {
           Write-Host "SendTo-Elasticsearch exception - $_"
       } 
}

$files = ls *.html
foreach ($file in $files)
{
	$a = gc $file.FullName
	$b = $a | select-string tablevalue
	$sessionID = ($a | select-string "Service:").toString().split(";")[1]
	$timestamp = ([DateTime]::Now.ToUniversalTime().ToString("o"))

	foreach ($line in $b)
	{
		$taskID = $line.tostring().split("<").split(">")[4]
		$PhaseName = $line.tostring().split("<").split(">")[8].replace(" ","_")
		$result = $line.tostring().split("<").split(">")[12]
		if ($result){
			$tdHash = @{}
			$tdHash.Add("@timestamp", $timestamp)
			$tdHash.Add("SessionID", [long]$sessionID)
			$tdHash.Add("Task", [int]$taskID)
			$tdHash.Add($PhaseName, [int]$result)
			$json = ConvertTo-json $tdHash
			Write-Output $json
			SendTo-Elasticsearch $json $elasticCluster $elasticIndex $indexDate
			}
	
	}
}
