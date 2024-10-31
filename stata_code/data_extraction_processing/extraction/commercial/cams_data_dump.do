#delimit ;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");

global firstyr 1996;
global lastyr = 2024;
clear;




/* landings */
/* leave off schema for TTS */


local sql "select * from cams_land cl
	where year>=$firstyr and year<=$lastyr" ; 


clear;
jdbc load, exec("`sql'") case(lower);
destring, replace;
notes: "`sql'";


save $data_main/commercial/cams_land_$vintage_string.dta, replace;

clear;
/*subtrip */

local sql "select * from cams_subtrip cst
	where year>=$firstyr and year<=$lastyr" ; 
	
	
jdbc load, exec("`sql'") case(lower);
destring, replace;
notes: "`sql'";
save $data_main/commercial/cams_subtrip_$vintage_string.dta, replace;





/* orphan subtrip */
clear;


local sql "select * from CAMS_VTR_ORPHANS_SUBTRIP where year>=$firstyr and year<=$lastyr" ; 
	
	
jdbc load, exec("`sql'") case(lower);
destring, replace;
notes: "`sql'";


save $data_main/commercial/cams_orphan_subtrip_$vintage_string.dta, replace;



