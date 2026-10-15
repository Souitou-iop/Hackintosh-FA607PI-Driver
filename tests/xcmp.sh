#!/bin/bash
# xcmp.sh: translate every cached AIR module (.ll) with the old and the new translator CLI, compare the SPIR-V
A=$(getconf DARWIN_USER_CACHE_DIR)nvmtl/aircache; O=~/hackintosh/port200/xcmp; rm -rf $O; mkdir -p $O/old $O/new
export METAL2VULKAN_SPIRV_VAL=$(cd "$(dirname "$0")" && pwd)/fakeval METAL2VULKAN_REPRO_DIR=${TMPDIR:-/tmp}/m2vrepro
one() { f=$1; b=$(basename $f .ll)
  for v in old new; do s=$(perl -MTime::HiRes=time -e 'printf "%d", time*1e9');
    perl -e 'alarm 60; exec @ARGV' ~/hackintosh/port200/m2v.$v $f $O/$v/$b.spv >/dev/null 2>$O/$v/$b.err; rc=$?
    e=$(perl -MTime::HiRes=time -e 'printf "%d", time*1e9'); echo "$v $b $rc $(( (e-s)/1000000 ))"; done; }
export -f one; export O
ls $A/*.ll | xargs -P 8 -I{} bash -c 'one {}' > $O/times.txt
