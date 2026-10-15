#!/bin/bash
# switchprof.sh: profile WindowServer while the user switches desktops for 8 s.
#   sudo bash ~/hackintosh/ws196/switchprof.sh      -> ~/hackintosh/ws196/prof-<time>/
# Records every 100 ms: presents/s, the swap thread's wait for the GPU (#196 frame fence), tagged buffers, GPU busy %;
# plus a spindump of WindowServer (where its CPU time goes) and per-process CPU.
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
O=${HACK:-$HOME/hackintosh}/ws196/prof-$(date +%H%M%S); mkdir -p "$O"
r() { sysctl -n debug.nvaccel_iop_flips debug.nvaccel_wsw_wait_us debug.nvaccel_wsw_waits debug.nvaccel_wsw_pend debug.nvaccel_gpu_util 2>/dev/null | tr '\n' ' '; }
sampler() {
  read f0 u0 w0 p0 g <<< "$(r)"
  for i in $(seq 1 100); do sleep 0.1; read f u w p g <<< "$(r)"
    printf "%5d ms  presents %3d/s  gpuwait %6.1f ms/s (%2d waits, %5.2f ms each)  tagged %3d/s  gpu %3s%%\n" $((i*100)) $(( (f-f0)*10 )) \
      "$(echo "($u-$u0)/100" | bc -l)" $((w-w0)) "$(echo "if ($w-$w0>0) ($u-$u0)/($w-$w0)/1000 else 0" | bc -l)" $(( (p-p0)*10 )) "$g"
    f0=$f; u0=$u; w0=$w; p0=$p; done; }
echo "In 3 seconds: switch desktops back and forth (Control+Left / Control+Right, or a 3-finger swipe) for about 8 seconds."
sleep 3; echo ">>> GO - switch desktops now"
sampler > "$O/counters.txt" &
top -l 9 -s 1 -o cpu -n 8 -stats pid,command,cpu,threads > "$O/top.txt" 2>&1 &
spindump WindowServer 8 10 -file "$O/spindump.txt" -noProcessingWhileSampling >/dev/null 2>&1
wait
echo ">>> done. Results in $O"
chown -R asus:staff "$O"
