# check_oracle_tablespace
Nagios Plugin to Check Oracle Table Spaces

Originally by Hannu Kivimäki / CSC - IT Center for Science Ltd.
[check_oracle_tablespace at Nagios Exchange ](https://exchange.nagios.org/directory/Plugins/Databases/Oracle/check_oracle_tablespace/details)

## Description ##

This Nagios plugin checks Oracle tablespace usage. It makes an
SQL query using Oracle's sqlplus command to calculate
tablespace usage percentages for given Oracle SID and databases.
Using '-a' option makes plugin autoextension aware, e.g. usage
percentage is determined by comparing used space against maximum
tablespace size allowed by autoextension, not the current size.

### Examples ###

``` bash
check_oracle_tablespace.sh -s SID -d 'FOO.*' -w 80 -c 90
# TABLESPACE CRITICAL: FOODB1 98% WARNING: FOODB2 82%; FOODB3 84%

check_oracle_tablespace.sh -s SID -d 'FOO.*' -w 80 -c 90 -a
# TABLESPACE CRITICAL: FOODB1 AUTOEXT 91%
```

## Installation ##

  1. Copy check_oracle_tablespace.sh to NAGIOS_HOME/libexec
     and set file permissions (execute for Nagios user).
     NOTE: Please remove read permissions from other users!
	
  1. Edit the script and fill in proper values for ORACLE_ORATAB,
     ORACLE_USER and ORACLE_PASS.
	
  1. Test plugin: `NAGIOS_HOME/libexec/check_oracle_tablespace.sh -h`,
     `NAGIOS_HOME/libexec/check_oracle_tablespace.sh -s <SID> -w 90 -c 95`
  
  1. Configure Oracle tablespace checks in Nagios (and NRPE) settings.

