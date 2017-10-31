# check_oracle_tablespace
Nagios Plugin to Check Oracle Table Spaces

Originally by Hannu Kivimäki / CSC - IT Center for Science Ltd.
[check_oracle_tablespace at Nagios Exchange ](https://exchange.nagios.org/directory/Plugins/Databases/Oracle/check_oracle_tablespace/details)

## Description ##

This Nagios plugin checks Oracle tablespace usage. It makes an SQL
query using Oracle's sqlplus command to calculate tablespace usage
percentages for given Oracle SID and databases. The plugin is
autoextension aware, e.g. usage percentage is determined by comparing
used space against maximum tablespace size allowed by autoextension,
not the current size.

### Examples ###

``` bash
check_oracle_tablespace.sh -s SID -d 'FOO.*' -w 80 -c 90
# TABLESPACE CRITICAL: FOODB1 98% WARNING: FOODB2 82%; FOODB3 84%
```

## Installation ##

  1. Copy check_oracle_tablespace.sh to NAGIOS_HOME/libexec
     and set file permissions (execute for Nagios user).
     NOTE: Please remove read permissions from other users!
	
  1. Edit the script and fill in proper values for ORACLE_ORATAB,
     ORACLE_USER and ORACLE_PASS. Alternatively, pass Oracle SID,
     user, and password via -s, -u, and -p options.
	
  1. Test plugin: `NAGIOS_HOME/libexec/check_oracle_tablespace.sh -h`,
     `NAGIOS_HOME/libexec/check_oracle_tablespace.sh -s <SID> -w 90 -c 95`
  
  1. Configure Oracle tablespace checks in Nagios (and NRPE) settings.

## Security ##

By default, the plugin connects to Oracle as user NAGIOS. To configure
user NAGIOS with minimum privilege required for monitoring tablespace
size, execute the following grants.

```sql
GRANT CONNECT TO NAGIOS;
GRANT SELECT on SYS.DBA_DATA_FILES to NAGIOS;
GRANT SELECT on SYS.DBA_SEGMENTS to NAGIOS;
GRANT SELECT on SYS.DBA_FREE_SPACE to NAGIOS;
```

You may specify a password via the command line -p option. However, in
some systems, the command line is visible via unix ps or via proc
filesystem. To avoid disclosing the password, the password can be
passed to the script via a password file or an exported environment
variable. To specify a password via a password file or environment
variable, use `-p file:/path/passwordfile` or `-p env:MYVAR`.
