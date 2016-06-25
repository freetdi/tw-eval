#!/bin/bash
#
# Felix Salfelder, 2016
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
#


OLDIFS=$IFS
file=$1
timeout=$2
num_int=20
program=tw-heuristic

# let it boot... need more?
inittime=0.01

b=$( basename $0 )
if [ $b = tw-eval-ex.sh ]; then
	mode=ex
	num_int=1000
	program=tw-exact
else
	mode=he
fi

sleeptime=$(echo $timeout / $num_int | bc -l)

if [ -z "$file" ]; then
	echo need gr file >&2
	exit -1
fi	

if [ ! -f $file ]; then
	echo $file does not exist >&2
	exit -1
fi	

basename=`basename $file`
stem=${basename%.gr}
logfile=/dev/stdout # $stem.log
me=$(basename $0)
# exec 2>$logfile

outtmp=/tmp/$me_$$_out
errtmp=/tmp/$me_$$_err
trap "rm -f $errtmp $outtmp" EXIT

# : > $logfile

echo =======what============================ >> $logfile
echo program: `which $program` >> $logfile
echo mode: $mode >>$logfile
echo input graph: $file >> $logfile
echo timeout: $timeout >> $logfile
echo num_int: $num_int >> $logfile

run()
{

$program $TWH_ARGS < $file 2>$errtmp >$outtmp &
pid=$!

sleep $inittime

# this is a bit ugly
# need to kill the process after timeout.
# but don't wait for it...
while [ $num_int -gt 0 ]; do
	sleep $sleeptime;
	kill -0 $pid 2>/dev/null || break;
	if [ "$mode" = he ]; then
		kill -SIGUSR1 $pid 2>/dev/null
	fi
	(( num_int=num_int-1 ))
done;

if [ $num_int -eq 0 ]; then
	sleep .01; # how to avoid it!?

	kill -SIGTERM $pid 2>/dev/null
fi

wait $pid;
}

time_run=$( (time run) 2>&1 )

time_runs=( $time_run )
time_real=${time_runs[1]}
time_user=${time_runs[3]}
time_sys=${time_runs[5]}

# ps aux| grep tee
# wc -l $outtmp | tee $logfile

sed -n '/^s/,//p' <$outtmp >$stem.td

echo =======stderr output from program========= >> $logfile
cat $errtmp >> $logfile

echo =======intermediate results================ >> $logfile

last_intermediate=

while read n
do {
	last_intermediate="$n";
	echo $n >> $logfile;
}
done < <(sed -n '/^[0-9]/p; /^s/q' < $outtmp)


echo =======validation============================ >> $logfile
dbs=$(head -n1 $stem.td | cut -f 4 -d ' ')
if [ -z "$last_intermediate" ]; then
	int_ok=N/A
elif [ "$last_intermediate" -lt "$dbs" ]; then
	int_ok=NO
else
	int_ok=yes
fi
echo intermediate ok: $int_ok

echo -n "tree decomposition: "
cmd="td-validate $file $stem.td"
$cmd &>> $logfile
vresult=$?
# rm $stem.td

echo -n =======run time=========================== >> $logfile
IFS=
echo $time_run >> $logfile
IFS=$OLDIFS

echo =======misc================================== >> $logfile
echo -n "cwd: " >> $logfile
pwd >> $logfile
echo -n "timestamp: " >> $logfile
date >> $logfile
echo -n "input sha1: " >> $logfile
sha1sum < $file >>$logfile
echo -n "treedec sha1: " >> $logfile
sha1sum < $stem.td >>$logfile

echo last_intermediate: $last_intermediate >> $logfile
echo decomposition bag size: $dbs >> $logfile
echo -n "valid: " >> $logfile
if [ $vresult -ne 0 ]; then
	echo no >> $logfile
elif [ "$mode" = he ]; then
	echo $int_ok >> $logfile
else
	echo yes >> $logfile
fi

echo =======tree decomposition================= >> $logfile
cat $stem.td >> $logfile

echo ========csv============================== >> $logfile
echo "$basename; $dbs; $vresult; $time_real; $time_user; $time_sys"

exit $vresult
