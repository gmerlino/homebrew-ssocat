#!/bin/sh
set -eu
source_tree=${1:?Usage: run-macos-tests.sh PATCHED_BUILT_SOURCE_TREE [SSOCAT_BINARY]}
binary=${2:-/opt/homebrew/bin/ssocat}
tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ssocat-macos-tests.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
openssl_prefix=$(brew --prefix openssl@4)
readline_prefix=$(brew --prefix readline)
cc -std=gnu23 -DHAVE_CONFIG_H -I"$source_tree" \
  -I"$openssl_prefix/include" -I"$readline_prefix/include" \
  "$tests_dir/test_packets.c" "$source_tree/libxio.a" \
  -L"$openssl_prefix/lib" -L"$readline_prefix/lib" \
  -lssl -lcrypto -lreadline -lresolv -o "$work_dir/test_packets"
"$work_dir/test_packets"
cc -dynamiclib "$tests_dir/mock_utun.c" -o "$work_dir/mock_utun.dylib"
SSOCAT_TEST_BINARY="$binary" SSOCAT_TEST_SHIM="$work_dir/mock_utun.dylib" \
  python3 "$tests_dir/test_tcp.py"
