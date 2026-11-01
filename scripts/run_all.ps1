# run_all.ps1 - compile and run every testbench with Icarus Verilog (Windows)
# Author: B. Srishanth Reddy
# Usage: powershell -File scripts\run_all.ps1 [-Seeds 1,2,3]
param([int[]]$Seeds = @(1, 2, 3))
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$iv = "C:\iverilog\bin"
New-Item -ItemType Directory -Force build, logs, waves | Out-Null
$src = "tb\i2c_monitor.v", "rtl\i2c_master.v", "rtl\i2c_slave.v", "rtl\i2c_apb.v"
$tbs = "tb_i2c_core", "tb_i2c_arb", "tb_i2c_apb", "tb_i2c_timing", "tb_i2c_robust", "tb_i2c_rand"
$fail = 0; $logs = @()
foreach ($t in $tbs) {
    $c = & "$iv\iverilog.exe" -g2012 -Wall -o "build\$t.vvp" "tb\$t.v" @src 2>&1
    $c | Set-Content -Encoding utf8 "logs\$t.compile.log"
    if ($LASTEXITCODE -ne 0) { $c; Write-Host "COMPILE FAILED: $t"; $fail++; continue }
    $runs = if ($t -eq "tb_i2c_rand") { $Seeds | ForEach-Object { @{ log = "tb_i2c_rand_seed$_"; args = @("+seed=$_", "+nodump") } } }
            else { ,@{ log = $t; args = @() } }
    foreach ($r in $runs) {
        $o = & "$iv\vvp.exe" -n "build\$t.vvp" @($r.args) 2>&1
        $o | Set-Content -Encoding utf8 "logs\$($r.log).log"; $o
        $logs += $r.log
        if (-not (Select-String -Quiet "RESULT: ALL TESTS PASSED" "logs\$($r.log).log")) { $fail++ }
    }
}
# negative test: a deliberate bug in the slave register write must be caught
& "$iv\iverilog.exe" -g2012 -DINJECT_BUG -o build\tb_bug.vvp tb\tb_i2c_core.v @src
& "$iv\vvp.exe" -n build\tb_bug.vvp +nodump 2>&1 | Set-Content -Encoding utf8 logs\negative_inject_bug.log
if (Select-String -Quiet "RESULT: FAILED" logs\negative_inject_bug.log) {
    "NEGATIVE TEST: injected bug detected by testbench ... PASS" | Add-Content -Encoding utf8 logs\negative_inject_bug.log
} else { "NEGATIVE TEST ... FAIL (bug not detected)" | Add-Content -Encoding utf8 logs\negative_inject_bug.log; $fail++ }
$sum = foreach ($l in $logs) { Select-String -CaseSensitive "SUMMARY|RESULT" "logs\$l.log" | ForEach-Object { "$($l): $($_.Line)" } }
$sum += (Select-String "NEGATIVE TEST" logs\negative_inject_bug.log | ForEach-Object { $_.Line })
$sum | Set-Content -Encoding utf8 logs\summary.log
Get-Content logs\summary.log
if ($fail) { Write-Host "$fail FAILURE(S)"; exit 1 } else { Write-Host "ALL TESTBENCHES PASSED" }
