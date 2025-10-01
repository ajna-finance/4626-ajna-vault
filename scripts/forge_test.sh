#!/usr/bin/env bash
set -e

# [[ "$(cast chain --rpc-url="$ETH_RPC_URL")" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --v=*)      v="${1#*=}"         ;;
        --mt=*)     mt="${1#*=}"        ;;
        --mc=*)     mc="${1#*=}"        ;;
        gas-report) gas_report_set=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
    shift
done


TEST_ARGS=''

vstr="-vvv"
if [ -n "$v" ]; then
    vstr=""
    for (( i=0; i<$v; i++ ))
    do
        vstr+="v"
    done
    if [[ ! -z $vstr ]]; then
        vstr="-$vstr"
    fi
fi

mcstr=""
if [ -n "$mc" ]; then
  mcstr="--mc $mc"
fi

mtstr=""
if [ -n "$mt" ]; then
  mtstr="--mt $mt"
fi

if [ -n "$gas_report_set" ]; then
    test_args="--gas-report"
fi

forkstr=""
if [ -n "$ETH_RPC_URL" ]; then
    [[ "$(cast chain --rpc-url="$ETH_RPC_URL")" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }
    forkstr="--fork-url ${ETH_RPC_URL}"
fi

echo "Running ${type} tests"
test_data="v: ${vstr:-"default"}, mc: ${mc:-"all"}, mt: ${mt:-"all"}"

echo "$test_data"

forge test $forkstr $mtstr $nmcstr $vstr $mcstr $test_args
# forge test $mtstr $nmcstr $vstr $mcstr $test_args
