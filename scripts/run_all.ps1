# run_all.ps1 - compile and run every testbench with Icarus Verilog (Windows)
# Author: B. Srishanth Reddy
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$iv = "C:\iverilog\bin"
New-Item -ItemType Directory -Force build, logs, waves | Out-Null
$rtl = "rtl\i2c_master.v", "rtl\i2c_slave.v", "rtl\i2c_apb.v"
$fail = 0
foreach ($t in "tb_i2c_core", "tb_i2c_arb", "tb_i2c_apb") {
    $c = & "$iv\iverilog.exe" -g2012 -Wall -o "build\$t.vvp" "tb\$t.v" @rtl 2>&1
    $c | Set-Content -Encoding utf8 "logs\$t.compile.log"; $c
    $o = & "$iv\vvp.exe" -n "build\$t.vvp" 2>&1
    $o | Set-Content -Encoding utf8 "logs\$t.log"; $o
    if (-not (Select-String -Quiet "RESULT: ALL TESTS PASSED" "logs\$t.log")) { $fail++ }
}
# negative test: a deliberate bug in the slave register write must be caught
& "$iv\iverilog.exe" -g2012 -DINJECT_BUG -o build\tb_bug.vvp tb\tb_i2c_core.v @rtl
& "$iv\vvp.exe" -n build\tb_bug.vvp +nodump 2>&1 | Set-Content -Encoding utf8 logs\negative_inject_bug.log
if (Select-String -Quiet "RESULT: FAILED" logs\negative_inject_bug.log) {
    "NEGATIVE TEST: injected bug detected by testbench ... PASS" | Add-Content -Encoding utf8 logs\negative_inject_bug.log
} else { "NEGATIVE TEST ... FAIL (bug not detected)" | Add-Content -Encoding utf8 logs\negative_inject_bug.log; $fail++ }
$sum = foreach ($t in "tb_i2c_core", "tb_i2c_arb", "tb_i2c_apb") { Select-String "SUMMARY|RESULT" "logs\$t.log" | ForEach-Object { $_.Line } }
$sum += (Select-String "NEGATIVE TEST" logs\negative_inject_bug.log | ForEach-Object { $_.Line })
$sum | Set-Content -Encoding utf8 logs\summary.log
Get-Content logs\summary.log
if ($fail) { Write-Host "$fail FAILURE(S)"; exit 1 } else { Write-Host "ALL TESTBENCHES PASSED" }
