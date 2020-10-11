#!/usr/bin/env bash
case $1 in
  ubuntu-*) OS=linux;;
  windows-*) OS=win;;
  macos-*)  OS=mac;;
esac
case $2 in
  x86) ARCHBITS=32;;
  x64) ARCHBITS=64;;
esac
case ${OS}${ARCHBITS} in
  win32) ARCHOPTS='-A Win32';;
  win64) ARCHOPTS='-A x64';;
esac
OUT_DIR=tinycc-bin/${OS}${ARCHBITS}
cmake -B $OUT_DIR $ARCHOPTS
cmake --build $OUT_DIR --config Release
