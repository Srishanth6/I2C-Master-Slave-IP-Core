#!/usr/bin/env bash
# run_all.sh - compile and run every testbench with Icarus Verilog (Linux / CI)
# Author: B. Srishanth Reddy
# Usage: scripts/run_all.sh [seed ...]      (default seeds: 1 2 3)
set -u
cd "$(dirname "$0")/.."
mkdir -p build logs waves
SEEDS=${*:-"1 2 3"}
SRC="tb/i2c_monitor.v rtl/i2c_master.v rtl/i2c_slave.v rtl/i2c_apb.v"
fail=0; logs=""
run() {  # run <log> <vvp> [args]
    local log=$1; shift
    vvp -n "$@" > "logs/$log.log" 2>&1; cat "logs/$log.log"
    grep -q "RESULT: ALL TESTS PASSED" "logs/$log.log" || { echo "::error::$log failed"; fail=$((fail+1)); }
    logs="$logs $log"
}
for t in tb_i2c_core tb_i2c_arb tb_i2c_apb tb_i2c_timing tb_i2c_robust tb_i2c_rand; do
    if ! iverilog -g2012 -Wall -o "build/$t.vvp" "tb/$t.v" $SRC > "logs/$t.compile.log" 2>&1; then
        cat "logs/$t.compile.log"; echo "::error::compile failed: $t"; fail=$((fail+1)); continue
    fi
    if [ "$t" = tb_i2c_rand ]; then
        for s in $SEEDS; do run "tb_i2c_rand_seed$s" "build/$t.vvp" "+seed=$s" +nodump; done
    else
        run "$t" "build/$t.vvp"
    fi
done
# negative test: a deliberate bug in the slave register write must be caught
iverilog -g2012 -DINJECT_BUG -o build/tb_bug.vvp tb/tb_i2c_core.v $SRC
vvp -n build/tb_bug.vvp +nodump > logs/negative_inject_bug.log 2>&1
if grep -q "RESULT: FAILED" logs/negative_inject_bug.log; then
    echo "NEGATIVE TEST: injected bug detected by testbench ... PASS" >> logs/negative_inject_bug.log
else
    echo "NEGATIVE TEST ... FAIL (bug not detected)" >> logs/negative_inject_bug.log; fail=$((fail+1))
fi
: > logs/summary.log
for l in $logs; do grep -E "SUMMARY|RESULT" "logs/$l.log" | sed "s/^/$l: /" >> logs/summary.log; done
grep "NEGATIVE TEST" logs/negative_inject_bug.log >> logs/summary.log
echo "=================================================="; cat logs/summary.log
if [ $fail -ne 0 ]; then echo "$fail FAILURE(S)"; exit 1; fi
echo "ALL TESTBENCHES PASSED"
