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

if [ $# -lt 2 -o $# -gt 3 ]; then
	echo usage:
	echo "$0 <grfile> <timeout> [<program>]"
	exit 2
fi

file=$1
timeout=$2
version=1
TDVALIDATE=td-validate # must be in PATH

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
me=$(basename $0)

if [ $me = tw-eval-ex.sh ]; then
       mode=ex
       program=tw-exact
else
       mode=he
       program=tw-heuristic
fi

if [ -n "$3" ]; then
	program="$3"
fi

tmpdir=$(mktemp --directory --tmpdir=/dev/shm $me-XXXXXXXX)
trap "rm -rf $tmpdir" EXIT

input=$tmpdir/input.gr
outtmp=$tmpdir/out
errtmp=$tmpdir/err
logfile=/dev/stdout # or $stem.log or $tmpdir/$stem.log

exec > $logfile

# copy input file to ramdisk
cp $file $input

SEED=`od -An -t u4 -N4 /dev/urandom`

echo =======what===============================
echo program: `which $program`
echo input graph: $file
echo timeout: $timeout
echo random seed: $SEED

run()
{
  # run the program for a duration of $timeout then send TERM
  # if still running after .5 seconds, also send KILL
  timeout --kill-after=.5 --signal=TERM $timeout $program -s $SEED \
    <  $input \
    2> $errtmp \
    >  $outtmp
}

sync

# set the current Unix time in milliseconds
start_time=$(($(date +'%s * 1000 + %-N / 1000000')))
time_run=$( (time run) 2>&1 )
exit_status=$?

time_runs=( $time_run )
time_real=${time_runs[1]}
time_user=${time_runs[3]}
time_sys=${time_runs[5]}

grep -v -e '^c status' <$outtmp >$stem.td

echo =======stderr output from program=========
cat $errtmp

echo =======intermediate results===============

# get graph's number of vertices
num_vertices=$(grep -e '^p' $input | cut -f 3 -d ' ')

# everyone starts with a trivial tree decomposition
echo $num_vertices $start_time

grep -e '^c status' $outtmp |
while read n
do {
  echo $n | cut -f 3,4 -d ' '
}
done

echo =======validation=========================
dbs=$(grep -e '^s' $stem.td | cut -f 4 -d ' ')
if [ -z "$dbs" ]; then
	dbs=-1
fi

if [ $exit_status -eq 0 ]; then
  echo -n exited on its own
elif [ $exit_status -eq 124 ]; then
	echo -n exited when we sent TERM
else
  echo -n failure: either we sent KILL or it aborted
fi
echo " (exit_status=$exit_status)"

echo -n "tree decomposition: "
$TDVALIDATE $input $stem.td &>> $logfile
vresult=$?

echo -n =======run time===========================
OLDIFS=$IFS
IFS=
echo $time_run
IFS=$OLDIFS

echo =======misc===============================
echo "user: $(whoami)"
echo "cwd: $(pwd)"
echo "timestamp: $(date)"
echo -n "input sha1: "
sha1sum < $input
echo -n "treedec sha1: "
sha1sum < $stem.td

echo decomposition bag size: $dbs
echo -n "valid treedecomposition: "
if [ $vresult -ne 0 ]; then
	echo no
else
	echo yes
fi

echo =======tree decomposition=================
cat $stem.td

echo =======csv================================
echo -n "$version; $basename; $timeout; $dbs; $vresult; $exit_status; "
echo    "$time_real; $time_user; $time_sys"

exit $vresult
