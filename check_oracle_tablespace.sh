#!/bin/sh
#
# Nagios plugin to check Oracle tablespace usage.
#
# $Id: check_oracle_tablespace.sh,v 1.10 2008/11/10 12:53:54 kivimaki Exp $
#
# Copyright (C) 2006-2008  Hannu Kivim�ki / CSC  - IT Center for Science Ltd.
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
ORACLE_ORATAB="/var/opt/oracle/oratab"
ORACLE_USER="username"
ORACLE_PASS="password"

# External commands
CMD_AWK="/usr/bin/awk"
CMD_EGREP="/usr/xpg4/bin/egrep"

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
CHECK_AUTOEXTENSION=0
IGNORE_NO_AUTOEXTENSION=0
VERBOSE=0

# ------------------------------ FUNCTIONS -------------------------------------

printInfo() {
    echo "Nagios plugin to check Oracle tablespace usage."
    echo "Copyright (C) 2006-2008  Hannu Kivim�ki / CSC  - IT Center for Science Ltd."
}

printHelp() {
    echo
    echo "Usage: check_oracle_tablespace.sh -s SID [-d <regexp>] [-w <1-100>] [-c <1-100>] [-a] [-i]"
    echo
    echo "  -s  Oracle system identifier (SID)"
    echo "  -d  which tablespaces/databases to check, defaults to all (/usr/xpg4/bin/egrep regexp)"
    echo "  -w  warning threshold (usage% as integer)"
    echo "  -c  critical threshold (usage% as integer)"
    echo "  -a  check autoextension - if tablespace has autoextension enabled,"
    echo "      usage is calculated using autoextension max size instead of"
    echo "      current tablespace max size. All autoextensible tablespaces"
    echo "      are also marked with AUTOEXT in status text. NOTE: If"
    echo "      autoextension max size is set to unlimited, usage% is zero."
    echo "  -i  ignore non-autoextensible tablespaces if the same db also"
    echo "      has one or more tablespaces with autoextension enabled"
    echo "      (to supress alerts in cases where a db might have both full,"
    echo "      non-autoextensible tablespaces and some autoextensible"
    echo "      tablespaces with room to expand)"
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
    echo "\$Id: check_oracle_tablespace.sh,v 1.10 2008/11/10 12:53:54 kivimaki Exp $"
    echo
}

# Checks command line options (pass $@ as parameter).
checkOptions() {
    if [ $# -eq 0 ]; then
        printInfo
        printHelp
        exit $STATE_UNKNOWN
    fi

    while getopts s:d:w:c:ailhvV OPT $@; do
            case $OPT in
                s) # Oracle SID
                   ORACLE_SID="$OPTARG"
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
# 3 usage % considering autoextension (=used/max) as integer
# 4 autoextensible YES/NO
#
#  SOMETABLESPACE1          74 58 YES
#  SOMETABLESPACE2          90 90  NO
#  ...
#
if [ $VERBOSE -eq 1 ]; then
    echo "Executing $ORACLE_HOME/bin/sqlplus..."
fi
if [ ! -x "$ORACLE_HOME/bin/sqlplus" ]; then
    echo "Error: $ORACLE_HOME/bin/sqlplus not found or not executable."
    exit $STATE_UNKNOWN
fi
$ORACLE_HOME/bin/sqlplus $ORACLE_USER/$ORACLE_PASS <<EOF | $CMD_EGREP -i "$DB_REGEXP" | $CMD_EGREP "YES$|NO$" > $TEMP_FILE
set linesize 80
set pages 500
set head off

column tablespace_name format a20
column usage_pct       format 999
column max_pct         format 999
column autoextensible  format a5

break on report

select	df.TABLESPACE_NAME,
        round(((df.BYTES - fs.BYTES) / df.BYTES) * 100) usage_pct,
        round(decode(df.MAXBYTES, 34359721984, 0, (df.BYTES - fs.BYTES) / df.MAXBYTES * 100)) max_pct,
        df.AUTOEXTENSIBLE
from
    (
        select 	TABLESPACE_NAME,
                sum(BYTES) BYTES,
                AUTOEXTENSIBLE,
                decode(AUTOEXTENSIBLE, 'YES', sum(MAXBYTES), sum(BYTES)) MAXBYTES
        from 	dba_data_files
        group 	by TABLESPACE_NAME,
                AUTOEXTENSIBLE
    )
    df,
    (
        select 	TABLESPACE_NAME,
                sum(BYTES) BYTES
        from 	dba_free_space
        group 	by TABLESPACE_NAME
    )
    fs
where 	df.TABLESPACE_NAME=fs.TABLESPACE_NAME
order 	by df.TABLESPACE_NAME asc
/
EOF
if [ "`cat $TEMP_FILE`" = "" ]; then
    echo "Error: Empty result from sqlplus. Check plugin settings and Oracle status."
    exit $STATE_UNKNOWN
fi
if [ $VERBOSE -eq 1 ]; then
    cat $TEMP_FILE
fi

# Loop through tablespace usage percentages and set a flag if thresholds
# are exceeded.
#
if [ $VERBOSE -eq 1 ]; then
    echo "Comparing usage percentages to threshold values..."
fi
column=0
for row in `cat $TEMP_FILE`; do
    column=`expr $column + 1`
    case $column in
        1) # tablespace name
           ts=$row
           ;;
        2) # usage percentage
           usage=$row
           ;;
        3) # usage percentage considering autoextension
           autoext_usage=$row;
           ;;
        4) # autoextensible
           autoext=$row
           
           # Reset column.
           column=0
           
           # Skip non-autoextensible tablespaces if '-i' was specified and
           # if same db has autoextensible tablespaces as well.
           if [ $IGNORE_NO_AUTOEXTENSION -eq 1 ] && [ $autoext = "NO" ]; then
                if [ "`$CMD_EGREP \"^$ts[[:space:]].*YES\$\" $TEMP_FILE`" != "" ]; then
                    continue
                fi
           fi

           # Decide which usage percentage to use.
           if [ $CHECK_AUTOEXTENSION -eq 1 ] && [ $autoext = "YES" ]; then
                usage=$autoext_usage
                aetext="AUTOEXT "
           else
                aetext=""
           fi
           if [ $CRIT_TRIGGER -eq 1 ] && [ $usage -ge $CRIT_THRESHOLD ]; then
              # Critical threshold was exceeded. Append tablespace and usage
              # to status text (shown in Nagios service status information).
              CRIT_EXCEEDED=1
              if [ "$CRIT_STATE_TEXT" != "" ]; then
                CRIT_STATE_TEXT="${CRIT_STATE_TEXT}; ${ts} ${aetext}${usage}%"
              else
                CRIT_STATE_TEXT="${CRIT_STATE_TEXT}${ts} ${aetext}${usage}%"
              fi
              if [ $VERBOSE -eq 1 ]; then
                  echo "${ts} ${aetext}${usage}% CRITICAL"
              fi

           elif [ $WARN_TRIGGER -eq 1 ] && [ $usage -ge $WARN_THRESHOLD ]; then
              # Warning threshold was exceeded. Append tablespace and usage
              # to status text (shown in Nagios service status information).
              WARN_EXCEEDED=1
              if [ "$WARN_STATE_TEXT" != "" ]; then
                WARN_STATE_TEXT="${WARN_STATE_TEXT}; ${ts} ${aetext}${usage}%"
              else
                WARN_STATE_TEXT="${WARN_STATE_TEXT}${ts} ${aetext}${usage}%"
              fi              
              if [ $VERBOSE -eq 1 ]; then
                  echo "${ts} ${aetext}${usage}% WARNING"
              fi
           fi
           ;;
    esac
done

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
