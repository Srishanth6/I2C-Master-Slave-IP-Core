# gtkwave_shots.ps1 - open each VCD in GTKWave with a view script and capture the real screen
# Author: B. Srishanth Reddy
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
                 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
New-Item -ItemType Directory -Force waveforms | Out-Null
$views = @{ "core_write"="tb_i2c_core"; "core_rstart"="tb_i2c_core"; "core_nack"="tb_i2c_core";
            "core_10bit"="tb_i2c_core"; "core_stretch"="tb_i2c_core"; "core_400k"="tb_i2c_core";
            "arb_lost"="tb_i2c_arb"; "apb_write"="tb_i2c_apb";
            "busy_reject"="tb_i2c_robust"; "reset_midxfer"="tb_i2c_robust"; "bus_recovery"="tb_i2c_robust";
            "timeout"="tb_i2c_robust"; "timing_fast"="tb_i2c_timing" }
if ($args.Count) { $sel = $args } else { $sel = $views.Keys }
foreach ($v in $sel) {
    $vcd = "waves\$($views[$v]).vcd"
    $p = Start-Process -PassThru "C:\iverilog\gtkwave\bin\gtkwave.exe" -ArgumentList "-r", "scripts\gtkw\gtkwaverc", "-S", "scripts\gtkw\$v.tcl", $vcd
    Start-Sleep -Seconds 8
    $p.Refresh(); [W]::ShowWindow($p.MainWindowHandle, 3) | Out-Null; [W]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds 3
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $bmp.Save("$root\waveforms\gtkwave_$v.png"); $g.Dispose(); $bmp.Dispose()
    Stop-Process -Id $p.Id -Force
    Write-Host "captured waveforms\gtkwave_$v.png"
}
