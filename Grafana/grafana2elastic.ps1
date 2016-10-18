     [string[]]$grafanaServers = "localhost"
     $grafanaServerPort = 3000
     $interval = 60
     $elasticIndex = "grafana"
     $elasticServer = "server1"
     $elasticServerPort = 9200

     function SendTo-Elasticsearch ($json, $elasticServer, $elasticServerPort, $elasticIndex, $indexDate)
     {
         try
         {
            Invoke-RestMethod "http://$elasticServer`:$elasticServerPort/$elasticIndex-$indexDate/message" -Method Post -Body $json -ContentType 'application/json'
         }
            catch [System.Exception]
            {
                Write-Host "SendTo-Elasticsearch exception - $_"
            } 
     }

     function Get-GrafanaMetrics ($grafanaServer)
     {
        $indexDate = [DateTime]::UtcNow.ToString("yyyy.MM.dd")

         try
         {
             $a = Invoke-RestMethod -Uri "http://$grafanaServer`:$grafanaServerPort/api/metrics"
             $b = $a | ConvertTo-Json | % { $_ -replace '\.(?=[a-z])',"_" }
             $c = ConvertFrom-Json -InputObject $b
             $c | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
             $c | add-member -Name "server" -Value $grafanaServer -MemberType NoteProperty
             $json = $c | convertTo-json

        SendTo-Elasticsearch $json $elasticServer $elasticServerPort $elasticIndex $indexDate
    }
       catch [System.Exception]
       {
           Write-Host "Get-GrafanaMetrics exception - $_"
       } 
     }

     while ($true)
     {
         if ((get-date) -ge $nextRun)
         {
        $nextRun = (get-date).AddSeconds($interval)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                    foreach ($grafanaServer in $grafanaServers){
                        Get-GrafanaMetrics $grafanaServer
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
