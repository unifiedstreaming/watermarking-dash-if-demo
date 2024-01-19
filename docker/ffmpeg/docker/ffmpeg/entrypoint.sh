#!/bin/sh

if [ $# -gt 0 ]
then
  exec "$@"
elif [[ $MODE == SMOOTH ]]
then
  python3 /usr/local/bin/mss_ingest.py
elif [[ $MODE == CMAFDUAL ]]
then 
  python3 /usr/local/bin/cmaf_dual_ingest.py
else
  python3 /usr/local/bin/cmaf_ingest.py
fi 