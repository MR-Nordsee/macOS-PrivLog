# Enable advanced parameter binding and define a customizable API endpoint
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][String]$Script:APIURL = "https://webhook/privileges"
)

# Assign a default log name used in the script
$Script:LogName = "API-Test"

# Writes log messages to both console and log file, with timestamp formatting
function Write-log {
    param (
        [Parameter(Mandatory = $true)][String]$Message
    )

    # Establish the script root path for log storage
    if ($PSScriptRoot -eq "") {
        $PSScriptRoot = $using:PSScriptRoot
    }

    # Ensure a unique log name exists if not defined
    if (-Not $LogName) {
        $Script:LogName = New-Guid
    }

    # Construct full log file path, either from custom root or default script folder
    if ($LogRootPath) {
        $LogPath = "$($LogRootPath)\$($LogName).log"
    }
    else {
        $LogPath = "$($PSScriptRoot)\$($LogName).log"
    }

    # Generate timestamp for log entries
    $Now = (Get-Date).ToString("dd-M-yyy HH:mm:ss")

    # Write log to console and append to log file
    Write-host $Message
    "[$($Now)] $($Message)" | Out-File -Encoding utf8 -Append -FilePath $LogPath
}

# Returns a preconfigured payload template for API requests
function Get-PayloadTemplate {
    $payloadTemplate = New-Object -TypeName psobject

    # Add necessary fields for privilege granting API
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "admin" -Value $true
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "custom_data" -Value @{"serial" = "API-Test" }
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "delayed" -Value $false
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "event" -Value "corp.sap.privileges.granted"
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "expires" -Value (Get-Date).AddMinutes(10)
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "machine" -Value (New-Guid).guid
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "reason" -Value "API-Test"
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "timestamp" -Value (Get-Date)
    $payloadTemplate | Add-Member -MemberType NoteProperty -Name "user" -Value "API-Guy"

    return $payloadTemplate
}

# Sends a web request to the API and returns result with error handling
function Send-ApiRequest {
    param (
        [Parameter(Mandatory = $false)][String]$RawPayload,
        [Parameter(Mandatory = $false)][String]$APIURL = $Script:APIURL,
        [Parameter(Mandatory = $false)][String][ValidateSet("GET", "POST", "DELETE", "PATCH" , "PUT")]$Method = "POST"
    )

    # Define headers for JSON communication
    $headers = @{ "Content-Type" = "application/json;charset=utf-8" }

    # Send request with payload if provided
    if ($RawPayload) {
        try {
            $webReturn = Invoke-WebRequest -Method $Method -Uri $APIURL -Body $RawPayload -Headers $headers
        }
        catch {
            # Attempt to parse error message as JSON
            try {
                $webReturn = ($Error[0].ErrorDetails.Message | ConvertFrom-Json)
            }
            catch {
                $webReturn = @{detail = $Error[1].ErrorDetails.Message }
            }

            # Add HTTP status code for easier debugging
            $webReturn | Add-Member -MemberType NoteProperty -Name "StatusCode" -Value $_.Exception.StatusCode
        }
    }
    else {
        # Send request without payload
        try {
            $webReturn = Invoke-WebRequest -Method $Method -Uri $APIURL -Headers $headers
        }
        catch {
            try {
                $webReturn = ($Error[0].ErrorDetails.Message | ConvertFrom-Json)
            }
            catch {
                $webReturn = @{detail = $Error[1].ErrorDetails.Message }
            }

            $webReturn | Add-Member -MemberType NoteProperty -Name "StatusCode" -Value $_.Exception.StatusCode
        }
    }
    return $webReturn
}

# -------------- API Testing Section --------------

# ✅ Test: Valid POST request
$webReturn = Send-ApiRequest -RawPayload (Get-PayloadTemplate | ConvertTo-Json)
if ($webReturn.StatusCode -eq 200) {
    Write-log "Test-API Good Request: OK ✅"
} else {
    Write-log "Test-API Good Request: Failed ❌ $($webReturn.StatusCode)"
    Write-Verbose $webReturn
}

# 🔁 Loop through invalid HTTP methods and verify API rejects them properly
foreach ($method in @("GET", "DELETE", "PATCH", "PUT")) {
    $webReturn = Send-ApiRequest -RawPayload (Get-PayloadTemplate | ConvertTo-Json) -Method $method
    if ($webReturn.StatusCode -eq "MethodNotAllowed") {
        Write-log "Test-API Block $($method): OK ✅"
    } else {
        Write-log "Test-API Block $($method): Failed ❌ $($webReturn.StatusCode)"
        Write-Verbose $webReturn
    }
}

# 🚫 Test: API request with no payload
$webReturn = Send-ApiRequest
if ($webReturn.StatusCode -eq "UnprocessableEntity") {
    Write-log "Test-API no Payload: OK ✅"
} else {
    Write-log "Test-API no Payload: Failed ❌ $($webReturn.StatusCode)"
    Write-Verbose $webReturn
}

# 🛠️ Test: Various incorrect payload formats
$tests = @("admin","reason","custom_data")

foreach ($t in $tests) {
    $payloadTemplate = Get-PayloadTemplate
    #$null = $t.modify.Invoke($payloadTemplate) #Needs Fix
    $payloadTemplate.$t = 123
    $webReturn = Send-ApiRequest -RawPayload ($payloadTemplate | ConvertTo-Json)
    if ($webReturn.StatusCode -eq "UnprocessableEntity") {
        Write-log "Test-API wrong format in $($t): OK ✅"
    } else {
        Write-log "Test-API wrong format in $($t): Failed ❌ $($webReturn.StatusCode)"
        Write-Verbose $webReturn
    }
}

# 📉 Test: Missing required field ("admin")
$payloadTemplate = Get-PayloadTemplate
$payloadTemplate.psobject.Properties.Remove("admin")
$webReturn = Send-ApiRequest -RawPayload ($payloadTemplate | ConvertTo-Json)
if ($webReturn.StatusCode -eq "UnprocessableEntity") {
    Write-log "Test-API Missing Field: OK ✅"
} else {
    Write-log "Test-API Missing Field: Failed ❌ $($webReturn.StatusCode)"
    Write-Verbose $webReturn
}

# ➕ Test: Payload with extra non-required field
$payloadTemplate = Get-PayloadTemplate
$payloadTemplate | Add-Member -MemberType NoteProperty -Name "choco" -Value "Nice"
$webReturn = Send-ApiRequest -RawPayload ($payloadTemplate | ConvertTo-Json)
if ($webReturn.StatusCode -eq 200) {
    Write-log "Test-API More Fields: OK ✅"
} else {
    Write-log "Test-API More Fields: Failed ❌ $($webReturn.StatusCode)"
    Write-Verbose $webReturn
}

# 🧪 Optional: Enable extended tests for malformed or unreachable URLs
$DoLongTests = $false
Write-log "Start URL Tests. This may take a while"

# 🔧 Test: Appending a fake endpoint to simulate a broken URL
$webReturn = Send-ApiRequest -RawPayload (Get-PayloadTemplate | ConvertTo-Json) -APIURL ($Script:APIURL + "/ABC")
if ($webReturn.StatusCode -ne "Success") {
    Write-log "Test-API wrong URL 1: OK ✅"
} else {
    Write-log "Test-API wrong URL 1: Failed ❌ $($webReturn.StatusCode)"
    Write-Verbose $webReturn
}

# ⏳ Perform additional, longer URL tests if enabled
if ($DoLongTests) {
    $urls = @(
        @{ Name = "wrong URL 2"; Uri = $Script:APIURL.Replace("/privileges", ":8080/privileges") },
        @{ Name = "wrong URL 3"; Uri = $Script:APIURL.Replace("https://", "http://") },
        @{ Name = "wrong URL 4"; Uri = $Script:APIURL.Replace("/privileges", "/privilege") }
    )

    foreach ($test in $urls) {
        $webReturn = Send-ApiRequest -RawPayload (Get-PayloadTemplate | ConvertTo-Json) -APIURL $test.Uri
        if ($webReturn.Values -ne "Success") {
            Write-log "Test-API $($test.Name): OK ✅"
        } else {
            Write-log "Test-API $($test.Name): Failed ❌ $($webReturn.StatusCode)"
            Write-Verbose $webReturn
        }
    }
}

# 📊 Final test: Send mass requests to validate load handling and stability
$payloadTemplate = Get-PayloadTemplate
$payloadTemplate.reason = "(COUNT)"  # Placeholder to track each request number
$Template = ($payloadTemplate | ConvertTo-Json -Depth 100)
$headers = @{ "Content-Type" = "application/json;charset=utf-8" }
$MassStatus = $true

# 🚀 Launch 2,500 parallel POST requests with modified payloads
1..2500 | Foreach-Object -ThrottleLimit 100 -Parallel {
    $Template = $using:Template
    $APIURL = $using:APIURL
    $headers = $using:headers
    $MassStatus = $using:MassStatus

    try {
        $Return = Invoke-WebRequest -Method POST -Uri $APIURL -Body $Template.Replace("(COUNT)", "$($_)") -Headers $headers
        Write-host "$($_): $($Return.StatusCode)"
    }
    catch {
        $MassStatus = $false
    }
}

# 🧾 Log mass request outcome
if ($MassStatus) {
    Write-log "Test-API MassRequest: OK ✅"
} else {
    Write-log "Test-API MassRequest: Failed ❌"
}
