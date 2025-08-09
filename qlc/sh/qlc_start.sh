#!/bin/sh
SCRIPT="$0"
echo  "________________________________________________________________________________________"
echo  "Start ${SCRIPT} at `date`"
#echo "----------------------------------------------------------------------------------------"
#echo "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#echo "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
echo  "----------------------------------------------------------------------------------------"
if [ "$1" == "" ] ;then
ls -lrth $HOME/qlc/log/qlc*
echo "type, e.g.:"
echo "$HOME/qlc/bin/qlc_start.sh b2ro iqi9 2018-12-01 2018-12-31 mars log001"
echo  "________________________________________________________________________________________"
echo  "End   ${SCRIPT} at `date`"
echo  "________________________________________________________________________________________"
exit 0
fi
$HOME/qlc/bin/qlc $1 $2 $3 $4 $5 mars >& $HOME/qlc/log/qlc.$6 &
echo "tail -f                            $HOME/qlc/log/qlc.$6"
echo  "________________________________________________________________________________________"
echo  "End   ${SCRIPT} at `date`"
echo  "________________________________________________________________________________________"
exit 0
