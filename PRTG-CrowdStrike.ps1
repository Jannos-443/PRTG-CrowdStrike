param(
    [string]$CloudUrl = "https://api.eu-1.crowdstrike.com",
    [string]$ClientId = '',
    [string]$ClientSecret = '',
    [string]$IgnorePattern = ''
)

#Catch all unhandled Errors
trap {
    $Output = "line:$($_.InvocationInfo.ScriptLineNumber.ToString()) char:$($_.InvocationInfo.OffsetInLine.ToString()) --- message: $($_.Exception.Message.ToString()) --- line: $($_.InvocationInfo.Line.ToString()) "
    $Output = $Output.Replace("<","")
    $Output = $Output.Replace(">","")
    $Output = $Output.Replace("#","")
    Write-Output "<prtg>"
    Write-Output "<error>1</error>"
    Write-Output "<text>$Output</text>"
    Write-Output "</prtg>"
    Exit
}

# Error if there's anything going on
$ErrorActionPreference = "Stop"

# Import Crowdstrike Powershell module
try {
    Import-Module -Name PSFalcon -ErrorAction Stop
}
catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Error Loading PSFalcon Powershell Module ($($_.Exception.Message))</text>"
    Write-Output "</prtg>"
    Exit
}

if ($ClientId -eq "") {
    Write-Error -Message "-ClientId is empty or not specified"
}

if ($ClientSecret -eq "") {
    Write-Error -Message "-ClientSecret is empty or not specified"
}

if ($CloudUrl -eq "") {
    Write-Error -Message "-Hostname is empty or not specified"
}

$OutputText = ""
$xmlOutput = '<prtg>'

# Authenticate with Crowdstrike API
Request-FalconToken -ClientId $ClientId -ClientSecret $ClientSecret -Hostname $CloudUrl


#Test Falcon Token
if (-not ((Test-FalconToken).Token)) {
    Write-Error -Message "Token not Valid"
}

#Start Region CrowdScore
#CrowdScore Latest

$Scores = Get-FalconScore -Sort timestamp.desc -Limit 6
$CrowdScore = $Scores | Select-Object -First 1 -ExpandProperty Score
$xmlOutput += "<result>
        <channel>CrowdScore</channel>
        <value>$($CrowdScore)</value>
        <unit>Count</unit>
        </result>"


#Crowdstore adjusted last hour
$Crowdscore_Changed = ($Scores | Measure-Object -Property adjusted_score -Sum).Sum
$xmlOutput += "<result>
        <channel>CrowdScore changed last hour</channel>
        <value>$($Crowdscore_Changed)</value>
        <unit>Count</unit>
        </result>"
#End Region CrowdScore


#Start Region Detections
#The name used in the UI to determine the severity of the detection. Values include Critical, High, Medium, and Low
$DetectionsLow = Get-FalconDetection -Filter "status:'new' + max_severity_displayname: 'Low'" -Total
$DetectionsMedium = Get-FalconDetection -Filter "status:'new' + max_severity_displayname: 'Medium'" -Total
$DetectionsHigh = Get-FalconDetection -Filter "status:'new' + max_severity_displayname: 'High'" -Total
$DetectionsCritical = Get-FalconDetection -Filter "status:'new' + max_severity_displayname: 'Critical'" -Total

#All but "Low" =  $DetectionsCritical = Get-FalconDetection -Filter "status:'new' + max_severity_displayname: ! 'Low'" -Total

$xmlOutput += "<result>
        <channel>Detections new Low</channel>
        <value>$($DetectionsLow)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>yy
        <LimitMaxWarning>0</LimitMaxWarning>
        </result>
        <result>
        <channel>Detections new Medium</channel>
        <value>$($DetectionsMedium)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>
        <result>
        <channel>Detections new High</channel>
        <value>$($DetectionsHigh)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>
        <result>
        <channel>Detections new Critical</channel>
        <value>$($DetectionsCritical)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>
        "
#End Region Detections


#Start Region Incidents
$Incidents = Get-FalconIncident -Filter "state: 'open'" -Total

$xmlOutput += "<result>
        <channel>Incidents open</channel>
        <value>$($Incidents)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>"
#End Region Incidents

#Start Region Quarantine
$QuarantineFiles = Get-FalconQuarantine -All -Detailed | Where-Object { $_.state -ne "deleted" }
$QuarantineFilesCount = ($QuarantineFiles | Measure-Object).Count
$xmlOutput += "<result>
        <channel>Quarantine Files</channel>
        <value>$($QuarantineFilesCount)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>"
#End Region Quarantine


#Start Region Clients
$Hosts_Total = Get-FalconHost -Total
$Date_LastSeen = ((Get-Date).AddDays(-30)).ToString("yyyy-MM-dd")
$Date_FirstSeen = ((Get-Date).AddDays(-2)).ToString("yyyy-MM-dd")
$Host_LastSeen = Get-FalconHost -Filter "last_seen:<=`'$($Date_LastSeen)`'" -Total
$Host_FirstSeen = Get-FalconHost -Filter "first_seen:>`'$($Date_FirstSeen)`'" -Total

$xmlOutput += "<result>
        <channel>Hosts Total</channel>
        <value>$($Hosts_Total)</value>
        <unit>Count</unit>
        </result>
        <result>
        <channel>Hosts lastseen older 30 Days</channel>
        <value>$($Host_LastSeen)</value>
        <unit>Count</unit>
        </result>
        <result>
        <channel>Hosts firstseen newer 2 Days</channel>
        <value>$($Host_FirstSeen)</value>
        <unit>Count</unit>
        </result>"

#End Region Clients

# Start Region Duplicates
$HostsDuplicates = Find-FalconDuplicate
$HostsDuplicatesHostnames = $HostsDuplicates.hostname | Select-Object -Unique
$HostsDuplicatesCount = ($HostsDuplicatesHostnames | Measure-Object).Count

if ($HostsDuplicatesCount -gt 0) {
    $HostsDuplicatesText = "Duplicate Hosts: "
    foreach ($HostsDuplicatesHostname in $HostsDuplicatesHostnames) {
        $HostsDuplicatesText += "$($HostsDuplicatesHostname); "
    }
    $OutputText += $HostsDuplicatesText
}

$xmlOutput += "<result>
    <channel>Hosts Duplicates</channel>
    <value>$($HostsDuplicatesCount)</value>
    <unit>Count</unit>
    <limitmode>1</limitmode>
    <LimitMaxError>0</LimitMaxError>
    </result>"
#End Region Duplicates

if ($OutputText -ne "") {
    $OutputText = $OutputText.Replace("<","")
    $OutputText = $OutputText.Replace(">","")
    $OutputText = $OutputText.Replace("#","")
    $xmlOutput += "<text>$($OutputText)</text>"
}

$xmlOutput += "</prtg>"

$xmlOutput