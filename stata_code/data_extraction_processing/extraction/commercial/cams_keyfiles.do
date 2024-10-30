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
save  $data_main/cams_species_keyfile_$today_date_string.dta, replace;
export delimited using  $data_main/cams_species_keyfile_$today_date_string.csv, replace;


/* Port keyfile 

A combined code for state, port and county. Taken with priority from CFDERS -> VTR PORT1 -> PRINC_PORT (permit data). Unknown = 990999. Named ports in VTR are converted to port numbers using the VTR.VLPORTTBL table. */

local sql "select * from CAMS_GARFO.CFG_PORT" ; 



clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/cams_port_$today_date_string.dta, replace;
export delimited using  $data_main/cams_port_$today_date_string.csv, replace;

/* dealer keyfile */

local sql "select * from NEFSC_GARFO.PERMIT_DEALER" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/dealer_permit_$today_date_string.dta, replace;
export delimited using  $data_main/dealer_permit_$today_date_string.csv, replace;


/* DLR_MKT and DLR_GRADE , DLR_DISP */

/*this has market categories, but  I'm not sure if it's the proper support table */


local sql "select * from CFDBS.SPECIES_ITIS_NE" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/dealer_species_itis_ne$today_date_string.dta, replace;
export delimited using  $data_main/dealer_species_itis_ne$today_date_string.csv, replace;



/* GEAR */

local sql "select * from cams_garfo.CFG_MASTER_GEAR" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/cams_master_gear_keyfile_$today_date_string.dta, replace;
export delimited using  $data_main/cams_master_gear_keyfile_$today_date_string.csv, replace;


local sql "select * from cams_garfo.cfg_NEGEAR" ; 
clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/cams_negear_keyfile_$today_date_string.dta, replace;
export delimited using  $data_main/cams_negear_keyfile_$today_date_string.csv, replace;





local sql "select * from cams_garfo.cfg_vlgear" ; 
clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
compress;
notes: "`sql'";

save  $data_main/cams_vlgear_keyfile_$today_date_string.dta, replace;
export delimited using  $data_main/cams_vlgear_keyfile_$today_date_string.csv, replace;
