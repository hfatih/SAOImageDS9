param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
$program = Join-Path $package 'ds9.exe'
$script = (Join-Path $PSScriptRoot '208-platform-smoke.tcl').Replace('\', '/')
$env:DS9_SMOKE_RESULT = Join-Path $env:RUNNER_TEMP 'ds9-artifact-smoke-result.txt'
if (Test-Path -LiteralPath $env:DS9_SMOKE_RESULT) { throw 'Smoke result must be fresh' }

# DS9 parses -source as Tcl text, so pass a portable Tcl filename.
$process = Start-Process -FilePath $program -WorkingDirectory $package `
    -ArgumentList @('-prefs', 'no', '-source', ('"' + $script + '"')) `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput windows-artifact-smoke-stdout.log `
    -RedirectStandardError windows-artifact-smoke-stderr.log
try {
    if (-not $process.WaitForExit(120000)) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Ds9Windows {
    public delegate bool Callback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, Callback callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
}
'@
        $windowText = [Ds9Windows+Callback] {
            param($window, $parameter)
            $text = New-Object System.Text.StringBuilder 4096
            [void][Ds9Windows]::GetWindowText($window, $text, $text.Capacity)
            if ($text.Length) { Write-Host "DS9 window: $text" }
            return $true
        }
        $targetProcessId = $process.Id
        $topWindows = [Ds9Windows+Callback] {
            param($window, $parameter)
            [uint32]$owner = 0
            [void][Ds9Windows]::GetWindowThreadProcessId($window, [ref]$owner)
            if ($owner -eq $targetProcessId) {
                [void]$windowText.Invoke($window, [IntPtr]::Zero)
                [void][Ds9Windows]::EnumChildWindows($window, $windowText, [IntPtr]::Zero)
            }
            return $true
        }
        [void][Ds9Windows]::EnumWindows($topWindows, [IntPtr]::Zero)
        throw 'DS9 did not finish its smoke test within 120 seconds'
    }
    if ($process.ExitCode -ne 0) { throw "DS9 exit code: $($process.ExitCode)" }
    $result = Get-Content -LiteralPath $env:DS9_SMOKE_RESULT -Raw
    Write-Output $result
    if (-not $result.StartsWith('PASS ')) { throw 'DS9 smoke test failed' }
} finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
}
