# Optional active diagnostic. Supply only an RFC1918 /24 prefix you are
# authorized to probe, e.g. -SubnetPrefix 192.168.10 -FirstHost 1 -LastHost 10.
# Not invoked by reports or the test runner. No reverse DNS (unbounded lookup).
[CmdletBinding()]
param(
    [ValidatePattern('^(?:10|172|192)\.(?:0|[1-9][0-9]{0,2})\.(?:0|[1-9][0-9]{0,2})$')]
    [string]$SubnetPrefix,
    [ValidateRange(1, 254)][int]$FirstHost = 1,
    [ValidateRange(1, 254)][int]$LastHost = 254,
    [ValidateRange(1, 5000)][int]$TimeoutMs = 500,
    [ValidateCount(1, 16)][ValidateRange(1, 65535)][int[]]$Ports = @(3389, 445)
)

# Fail before creating network objects, including when dot-sourced accidentally.
if (-not $PSBoundParameters.ContainsKey('SubnetPrefix') -or [string]::IsNullOrWhiteSpace($SubnetPrefix)) {
    throw 'Supply -SubnetPrefix explicitly, and only for a subnet you are authorized to scan.'
}
$octets = @($SubnetPrefix.Split('.') | ForEach-Object { [int]$_ })
$isPrivate = $octets[0] -eq 10 -or
    ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
    ($octets[0] -eq 192 -and $octets[1] -eq 168)
if (-not $isPrivate -or $octets[1] -gt 255 -or $octets[2] -gt 255) {
    throw 'SubnetPrefix must be three IPv4 octets in an RFC1918 private subnet (without a host or CIDR suffix).'
}
if ($LastHost -lt $FirstHost) { throw 'LastHost must be greater than or equal to FirstHost.' }

function Test-LanPing {
    [CmdletBinding()]
    param([string]$Address, [int]$Timeout)

    $ping = $null
    try {
        $ping = New-Object -TypeName System.Net.NetworkInformation.Ping
        $reply = $ping.Send($Address, $Timeout)
        $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
    } catch {
        $false
    } finally {
        if ($null -ne $ping) { $ping.Dispose() }
    }
}

function Test-LanTcpPort {
    [CmdletBinding()]
    param([string]$Address, [int]$Port, [int]$Timeout)

    $client = $null
    $waitHandle = $null
    try {
        $client = New-Object -TypeName System.Net.Sockets.TcpClient
        $pending = $client.BeginConnect($Address, $Port, $null, $null)
        $waitHandle = $pending.AsyncWaitHandle
        if (-not $waitHandle.WaitOne($Timeout)) { return $false }
        $client.EndConnect($pending)
        return $client.Connected
    } catch {
        return $false
    } finally {
        # The wait handle and socket are separate disposable resources.
        try {
            if ($null -ne $waitHandle) { $waitHandle.Dispose() }
        } finally {
            if ($null -ne $client) { $client.Dispose() }
        }
    }
}

foreach ($hostNumber in $FirstHost..$LastHost) {
    $address = "$SubnetPrefix.$hostNumber"
    if (Test-LanPing -Address $address -Timeout $TimeoutMs) {
        $openPorts = @(
            foreach ($port in ($Ports | Select-Object -Unique)) {
                if (Test-LanTcpPort -Address $address -Port $port -Timeout $TimeoutMs) { $port }
            }
        )
        [pscustomobject]@{ Address = $address; OpenPorts = $openPorts }
    }
}
