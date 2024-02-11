#!/bin/bash

# usp_diff.sh <output_file> <reference_file> [additional diff options]

if [ $# -lt 2 ]; then
  echo "Syntax: $0 <out_file> <ref_file> ..."
  exit 1
fi

out_file="$1"
ref_file="$2"

if [ ! -e "$out_file" ]; then
  echo "Missing out file $out_file"
  exit 1;
fi

function confirm()
{
  local question="$1"
  local key
  read -rsn1 -p "$question (Y/N)? " key
  echo
  [ "$key" = "y" -o "$key" = "Y" ]
}

function confirm_compare()
{
  local question="$1"
  local out_file="$2"
  local ref_file="$3"
  local key
  while true; do
    read -rsn1 -p "$question (Y/N/D)? " key
    echo
    [ "$key" = "d" -o "$key" = "D" ] ||
      break
    if test "$DISPLAY"; then
      meld "$out_file" "$ref_file"
    else
      diff -u -p "$out_file" "$ref_file"
    fi
  done
  [ "$key" = "y" -o "$key" = "Y" ]
}

do_update=false
if [ ! -e "$ref_file" ]; then
  echo "Missing ref file $ref_file"
  if confirm '***REF FILE DOES NOT EXIST*** Copy file'; then
    do_update=true
  fi
else
  if diff -q -I "Created with" "$@"; then
    exit 0
  fi

  if confirm_compare 'Update file' "$out_file" "$ref_file"; then
    do_update=true
  fi
fi

if [ "$do_update" = "true" ]; then
  cp "$out_file" "$ref_file"
  exit 0
fi

exit 1
