# delimit ;
/* ITIS TSN keyfile */
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select * from cams_garfo.CFG_ITIS" ; 
jdbc load, exec("`sql'") case(lower);
duplicates drop;
destring, replace;
compress;
notes: "`sql'";
save  $data_main/commercial/cams_species_keyfile_$vintage_string.dta, replace;

/* Port keyfile 

A combined code for state, port and county. Taken with priority from CFDERS -> VTR PORT1 -> PRINC_PORT (permit data). Unknown = 990999. Named ports in VTR are converted to port numbers using the VTR.VLPORTTBL table. */

local sql "select * from CAMS_GARFO.CFG_PORT" ; 



clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/cams_port_$vintage_string.dta, replace;

/* dealer keyfile */

local sql "select * from NEFSC_GARFO.PERMIT_DEALER" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/dealer_permit_$vintage_string.dta, replace;


/* DLR_MKT and DLR_GRADE , DLR_DISP */
/*this has market categories, but  I'm not sure if it's the proper support table */


local sql "select * from CFDBS.SPECIES_ITIS_NE" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/dealer_species_itis_ne$vintage_string.dta, replace;



/* GEAR */

local sql "select * from cams_garfo.CFG_MASTER_GEAR" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/cams_master_gear_keyfile_$vintage_string.dta, replace;


local sql "select * from cams_garfo.cfg_NEGEAR" ; 
clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/cams_negear_keyfile_$vintage_string.dta, replace;





local sql "select * from cams_garfo.cfg_vlgear" ; 
clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/commercial/cams_vlgear_keyfile_$vintage_string.dta, replace;



clear;
local sql "select table_name, column_name, comments from all_col_comments where owner='CAMS_GARFO' and table_name in('CAMS_SUBTRIP','CAMS_LAND','CAMS_ORPHAN_SUBTRIP') order by column_name, table_name" ;
odbc load, exec("`sql' ;") $myNEFSC_USERS_conn;
save  $data_main/commercial/cams_keyfile_$vintage_string.dta, replace;


