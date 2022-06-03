#!/usr/bin/env bash

START=$(date +%s.%N)

arg1=${1:-''}

if [[ $arg1 == '--help' || $arg1 == '-h' || -z "$arg1" ]]; then
    echo "Script scrape unofficial results the day after"
fi

#exit when command fails (use || true when a command can fail)
set -o errexit

#exit when your script tries to use undeclared variables
set -o nounset

#(a.k.a set -x) to trace what gets executed
#set -o xtrace

# in scripts to catch mysqldump fails
set -o pipefail

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file})"
ts=`date +'%Y%m%d-%H%M%S'`

#Set the config file
configFile="$HOME/.binJlam/templateConfig"

#Ensure only one copy is running
pidfile=$HOME/.${__base}.pid
if [ -f ${pidfile} ]; then
   #verify if the process is actually still running under this pid
   oldpid=`cat ${pidfile}`
   result=`ps -ef | grep ${oldpid} | grep ${__base}  || true`

   if [ -n "${result}" ]; then
     echo "Script already running! Check $pidfile. Exiting"
     exit 255
   fi
fi

#grab pid of this process and update the pid file with it
pid=`ps -ef | grep ${__base} | grep -v 'vi ' |  head -n1 |  awk ' {print $2;} '`
echo ${pid} > ${pidfile}


#Capture everything to log
mkdir -p ~/log
log=~/log/$__base-${ts}.log
exec >  >(tee -a $log)
exec 2> >(tee -a $log >&2)
touch $log
chmod 600 $log


#Check that the config file exists
#if [[ ! -f "$configFile" ]] ; then
#        echo "I need a file at $configFile with ..."
#        exit 1
#fi


echo Begin `date`  .....

### BEGIN SCRIPT ###############################################################



### CONFIGURATION
electionID=`echo $__base | cut -d '.' -f 1`
curlTimeout=6
restSecs=10
continueFlag=/tmp/$__base.continue
stopFlag=/tmp/$__base.stop
maxRuns=100
completeStr='"cs":[{"n":"'
dataFormat='json'

touch $continueFlag

if [[ -f $stopFlag ]]; then
	echo Stop Flag active.  To remove
	echo rm $stopFlag
	exit 1
fi

runs=0
set -x
while [[ -f $continueFlag && $runs -lt $maxRuns && ! -f $stopFlag  ]]; do
set +x
	echo Run $runs of $maxRuns...

	for lang in e ; do
		dataDir="$__dir/data/$electionID/$lang/"
		workDir="$dataDir/work/"
		readyDir="$dataDir/ready"

		mkdir -p $workDir $readyDir

		for identifier in `seq 1 124`; do
            cookieJarFile=$workDir/on_cookier_jar.txt
            getCookieUrl="https://rtr.elections.on.ca/RealTimeResults/api/refdata/geteds/513/en"
            curl --cookie-jar $cookieJarFile --max-time $curlTimeout --verbose $getCookieUrl > /dev/null

            echo "Cookie file"
            cat $cookieJarFile
            sleep 5


            dataSource="https://rtr.elections.on.ca/RealTimeResults/api/edresults/getedresults"
			ridingFile=$workDir/$identifier.json
			readyFile=$readyDir/$identifier.json

			startCurl=$(date +%s.%N)
            postData="{\"languageCode\":\"en\",\"electoralDistricts\":[{\"eventId\":513,\"electoralDistrictId\":${identifier}}]}"
            set -x
			curl --cookie $cookieJarFile --max-time $curlTimeout --verbose --data "${postData}" $dataSource  > $ridingFile || true
            set +x
            ls -lh $ridingFile
            wc -l $ridingFile
            cat $ridingFile
            #dos2unix $ridingFile
            echo
            sleep 5
			grep "$completeStr" $ridingFile > /dev/null && mv -v "$ridingFile" "$readyFile" || echo "Could not find $completeStr in $ridingFile"
			endCurl=$(date +%s.%N)
			diffCurl=$(echo "$endCurl - $startCurl" | bc)

			echo; echo
			echo Data for riding $identifier in language $lang done!
			echo; echo

			echo `date`   Sleeping for $diffCurl + 1 seconds
			sleep $diffCurl
			sleep 1
		done

	done

	date
	echo Resting for $restSecs seconds....
	echo
	echo To interupt until next cron:
	echo rm $continueFlag
	echo
	echo To stop permantly
	echo touch $stopFlag
	echo
	for i in `seq $restSecs -1 0`; do
		printf "$i... " ;
		if (( $i % 5 == 0 )) ; then echo ; fi
		sleep 1;
	done
	echo ; echo

	echo Run $runs of $maxRuns done

	let runs++ || true


done


echo; echo; echo; echo;



### END SCIPT ##################################################################

END=$(date +%s.%N)
DIFF=$(echo "$END - $START" | bc)
echo Done.  `date` - $DIFF seconds

if [ -f ${pidfile} ]; then
    rm ${pidfile}
fi
