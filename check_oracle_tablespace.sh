#!/bin/sh
#
# Nagios plugin to check Oracle tablespace usage.
#
# Copyright (C) 2006-2008  Hannu Kivimäki / CSC  - IT Center for Science Ltd.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

# ------------------------------ SETTINGS --------------------------------------

# Oracle environment settings (could be parametrized)
ORACLE_ORATAB="/etc/oratab"
ORACLE_USER="NAGIOS"
ORACLE_PASS="password"

# External commands
CMD_AWK="/bin/awk"
CMD_EGREP="/bin/egrep"

# Temporary work file (will be removed automatically)
TEMP_FILE="/tmp/check_oracle_tablespace_$$.tmp"

# Nagios plugin return values
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Default values
WARN_THRESHOLD=-1
WARN_EXCEEDED=0
WARN_STATE_TEXT=""
WARN_TRIGGER=0
CRIT_THRESHOLD=-1
CRIT_EXCEEDED=0
CRIT_STATE_TEXT=""
CRIT_TRIGGER=0
VERBOSE=0

PLUGIN_VERSION=1.11
# ------------------------------ FUNCTIONS -------------------------------------

printInfo() {
    echo "Nagios plugin to check Oracle tablespace usage."
    echo "Copyright (C) 2006-2008  Hannu Kivimäki / CSC  - IT Center for Science Ltd."
}

printHelp() {
    echo
    echo "Usage: check_oracle_tablespace.sh -s SID [-d <regexp>] [-w <1-100>] [-c <1-100>]"
    echo
    echo "  -s  Oracle system identifier (SID)"
    echo "  -u  Oracle username"
    echo "  -p  Oracle system password (using openssl passin syntax with pass:, file:, env:, and stdin options)"
    echo "  -d  which tablespaces/databases to check, defaults to all ($CMD_EGREP regexp)"
    echo "  -w  warning threshold (usage% as integer)"
    echo "  -c  critical threshold (usage% as integer)"
    echo
    echo "  -h  this help screen"
    echo "  -l  license info"
    echo "  -v  verbose output (for debugging)"
    echo "  -V  version info"
    echo
    echo "Example: check_oracle_tablespace.sh -s MYSID -d 'FOO.*' -w 90 -c 95"
    echo
    echo "This will return CRITICAL if tablespace usage of any database"
    echo "matching regular expression 'FOO.*' (case insensitive, will be"
    echo "used as a parameter for 'egrep -i') is 95% or more, WARNING if"
    echo "usage is 90% or more and otherwise OK. Warning threshold is ignored"
    echo "if it is higher or equal to critical threshold."
    echo
}

printLicense() {
    echo
    echo "This program is free software; you can redistribute it and/or"
    echo "modify it under the terms of the GNU General Public License"
    echo "as published by the Free Software Foundation; either version 2"
    echo "of the License, or (at your option) any later version."
    echo
    echo "This program is distributed in the hope that it will be useful,"
    echo "but WITHOUT ANY WARRANTY; without even the implied warranty of"
    echo "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
    echo "GNU General Public License for more details."
    echo
    echo "You should have received a copy of the GNU General Public License"
    echo "along with this program; if not, write to the Free Software"
    echo "Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA."
    echo
}

printVersion() {
    echo
    echo "check_oracle_tablespace.sh $PLUGIN_VERSION"
    echo
}

# Checks command line options (pass $@ as parameter).
checkOptions() {
    if [ $# -eq 0 ]; then
        printInfo
        printHelp
        exit $STATE_UNKNOWN
    fi

    while getopts s:d:w:c:u:p:lhvV OPT $@; do
            case $OPT in
                s) # Oracle SID
                   ORACLE_SID="$OPTARG"
                   ;;
                u) # Oracle USER
                   ORACLE_USER="$OPTARG"
                   ;;
		p) # Oracle Password, openssl style
		   case ${OPTARG%:*} in
		       file)
			   passwordFile=${OPTARG#*:}
			   if [ ! -r "$passwordFile" ]; then
			       echo "Error reading password file \`$passwordFile'"
			       exit $STATE_UNKNOWN
			   fi
			   ORACLE_PASS=$(cat "$passwordFile")
			   ;;
		       env)
			   varName=${OPTARG#*:}
			   ORACLE_PASS=${!varName}
			   ;;
		       pass)
			   ORACLE_PASS=${OPTARG#*:}
			   ;;
		       stdin)
			   ORACLE_PASS=$(cat)
			   ;;
		       *)
			   ORACLE_PASS=$OPTARG
			   ;;
		   esac
		   ;;
                d) # Oracle databases (regular expression for egrep)
                   DB_REGEXP="$OPTARG"
                   ;;
                w) # warning threshold
                   opt_warn_threshold=$OPTARG
                   WARN_TRIGGER=1
                   ;;
                c) # critical threshold
                   opt_crit_threshold=$OPTARG
                   CRIT_TRIGGER=1
                   ;;
                a) # check tablespace autoextension
                   CHECK_AUTOEXTENSION=1
                   ;;
                i) # ignore non-autoextensible tablespaces if db
                   # still has room to expand in autoextensible ones
                   IGNORE_NO_AUTOEXTENSION=1
                   ;;
                l) printInfo
                   printLicense
                   exit $STATE_UNKNOWN
                   ;;
                h) printInfo
                   printHelp
                   exit $STATE_UNKNOWN
                   ;;
                v) VERBOSE=1
                   ;;
                V) printInfo
                   printVersion
                   exit $STATE_UNKNOWN
                   ;;
                ?) printInfo
                   printHelp
                   exit $STATE_UNKNOWN
                   ;;
            esac
    done

    TMP=`$CMD_EGREP \^${ORACLE_SID}\: $ORACLE_ORATAB`
    if [ -z "$ORACLE_SID" ] || [ "$TMP" = "" ]; then
        echo "Error: Invalid Oracle SID (see $ORACLE_ORATAB)."
        printInfo
        printHelp
        exit $STATE_UNKNOWN
    else
        ORACLE_HOME=`echo $TMP | $CMD_AWK 'BEGIN{FS=":"}{print $2}'`
    fi

    if [ -z "$DB_REGEXP" ]; then
        DB_REGEXP=".*"
    fi

    threshold_error=0
    if [ $WARN_TRIGGER -eq 1 ]; then
        if [ "`echo $opt_warn_threshold | grep '^[0-9]*\$'`" = "" ]; then
            threshold_error=1
        elif [ $opt_warn_threshold -gt 100 ]; then
            threshold_error=1
        else
            WARN_THRESHOLD=$opt_warn_threshold
        fi
    fi
    if [ $CRIT_TRIGGER -eq 1 ]; then
        if [ "`echo $opt_crit_threshold | grep '^[0-9]*\$'`" = "" ]; then
            threshold_error=1
        elif [ $opt_crit_threshold -gt 100 ]; then
            threshold_error=1
        else
            CRIT_THRESHOLD=$opt_crit_threshold
        fi
    fi
    if [ $threshold_error -eq 1 ]; then
        echo "Error: Invalid threshold values (must be between 0-100)."
        printInfo
        printHelp
        exit $STATE_UNKNOWN
    fi
}

# ----------------------------- MAIN PROGRAM -----------------------------------

checkOptions $@

if [ $VERBOSE -eq 1 ]; then
    echo "ORACLE_SID = $ORACLE_SID"
    echo "ORACLE=HOME = $ORACLE_HOME"
fi
export ORACLE_SID
export ORACLE_HOME

# Feed SQL as here document to sqlplus to query tablespace information.
# Result is stored into temporary text file with four columns separated
# with whitespace:
#
# 1 tablespace name
# 2 usage % (=used/total) as integer
#
#  SOMETABLESPACE1          58
#  SOMETABLESPACE2          90
#  ...
#
if [ $VERBOSE -eq 1 ]; then
    echo "Executing $ORACLE_HOME/bin/sqlplus..."
fi
if [ ! -x "$ORACLE_HOME/bin/sqlplus" ]; then
    echo "Error: $ORACLE_HOME/bin/sqlplus not found or not executable."
    exit $STATE_UNKNOWN
fi
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/\"$ORACLE_PASS\" <<EOF | $CMD_EGREP -i "$DB_REGEXP" > $TEMP_FILE
set linesize 80 pages 500 head off echo off feedback off
set sqlprompt ""

column tablespace_name format a30
column usage_pct       format 999
break on report

SELECT 
       df.tablespace_name,
       round(100 * ( nvl(tu.totalusedspace, 0) / df.totalspace)) usage_pct
FROM
(SELECT tablespace_name,
round(sum( decode(autoextensible, 'YES', maxbytes, 'NO', bytes) ) / 1048576) TotalSpace
FROM dba_data_files
GROUP BY tablespace_name) df,
(SELECT round(sum(bytes)/(1024*1024)) totalusedspace, tablespace_name
FROM dba_segments
GROUP BY tablespace_name) tu
WHERE df.tablespace_name = tu.tablespace_name (+)
order by df.TABLESPACE_NAME asc
/
EOF
if [ "`cat $TEMP_FILE`" = "" ]; then
    echo "Error: Empty result from sqlplus. Check plugin settings and Oracle status."
    exit $STATE_UNKNOWN
fi
  
if [ $VERBOSE -eq 1 ]; then
    cat $TEMP_FILE
fi

errors=$($CMD_EGREP \^ORA- "$TEMP_FILE")
if [ "$errors" ]; then
    echo "Error: Oracle errors in result from sqlplus. Check permissions for user $ORACLE_USER: $errors"
    exit $STATE_UNKNOWN
fi

# Loop through tablespace usage percentages and set a flag if thresholds
# are exceeded.
#
if [ $VERBOSE -eq 1 ]; then
    echo "Comparing usage percentages to threshold values..."
fi
column=0
while read ts usage; do
    if [ "$ts" = "" ] || [ "$usage" = "" ]; then continue; fi
    if [ $CRIT_TRIGGER -eq 1 ] && [ "$usage" -ge $CRIT_THRESHOLD ]; then
        # Critical threshold was exceeded. Append tablespace and usage
        # to status text (shown in Nagios service status information).
        CRIT_EXCEEDED=1
        if [ "$CRIT_STATE_TEXT" != "" ]; then
            CRIT_STATE_TEXT="${CRIT_STATE_TEXT}; ${ts} ${usage}%"
        else
            CRIT_STATE_TEXT="${CRIT_STATE_TEXT}${ts} ${usage}%"
        fi
        if [ $VERBOSE -eq 1 ]; then
            echo "${ts} ${usage}% CRITICAL"
        fi

    elif [ $WARN_TRIGGER -eq 1 ] && [ "$usage" -ge $WARN_THRESHOLD ]; then
        # Warning threshold was exceeded. Append tablespace and usage
        # to status text (shown in Nagios service status information).
        WARN_EXCEEDED=1
        if [ "$WARN_STATE_TEXT" != "" ]; then
            WARN_STATE_TEXT="${WARN_STATE_TEXT}; ${ts} ${usage}%"
        else
            WARN_STATE_TEXT="${WARN_STATE_TEXT}${ts} ${usage}%"
        fi              
        if [ $VERBOSE -eq 1 ]; then
            echo "${ts} ${usage}% WARNING"
        fi
    fi
done < "$TEMP_FILE"

# Remove temporary work file.
rm -f $TEMP_FILE

# Print check results and exit.
if [ $CRIT_EXCEEDED -eq 1 ]; then
    if [ $WARN_EXCEEDED -eq 1 ]; then
        echo "TABLESPACE CRITICAL: $CRIT_STATE_TEXT WARNING: $WARN_STATE_TEXT"
    else
        echo "TABLESPACE CRITICAL: $CRIT_STATE_TEXT"
    fi
    exit $STATE_CRITICAL

elif [ $WARN_EXCEEDED -eq 1 ]; then
    echo "TABLESPACE WARNING: $WARN_STATE_TEXT"
    exit $STATE_WARNING
fi

echo "TABLESPACE OK"
exit $STATE_OK
