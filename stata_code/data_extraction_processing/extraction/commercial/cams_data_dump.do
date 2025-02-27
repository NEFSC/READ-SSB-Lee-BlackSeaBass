#delimit ;

/*jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");
*/
global firstyr 1996;
global lastyr = 2025;
clear;


cap mkdir $data_main/commercial/temp ;

/* leave off schema for TTS */

/*

foreach y of numlist $firstyr(1)$lastyr{;

	/* landings */

	local sql "select * from cams_land cl
		where cl.year=`y' and cl.rec=0" ; 


	clear;
	/*jdbc load, exec("`sql' ") case(lower);*/

	odbc load, exec("`sql'; ")  $myNEFSC_USERS_conn;

	compress;
	notes: "`sql'";


	save $data_main/commercial/temp/cams_land_`y'_$vintage_string.dta, replace;

}
local landfiles: dir "$data_main/commercial/temp" files "cams_land_*_$vintage_string.dta" ;

clear;
foreach l of local landfiles{;
	append using $data_main/commercial/temp/`l'	;
};
notes: Joins of CAMS_LAND to CAMS_SUBTRIP must be done on CAMSID and subtrip;
capture destring docid dlrid dlr_stid permit dlr_cflic port bhc subtrip dlr_rptid dlr_utilcd dlr_source dlr_toncl fzone vtr_catchid vtr_dlrid itis_tsn dlr_catch_source dlr_grade dlr_disp rec nemarea area negear sectid, replace;
compress;

save $data_main/commercial/cams_land_$vintage_string.dta, replace;

foreach y of numlist $firstyr(1)$lastyr{;
	rm $data_main/commercial/temp/cams_land_`y'_$vintage_string.dta ;
};

*/


	
	
	foreach y of numlist $firstyr(1)$lastyr{;

	/*subtrip */

	clear;
	local sql "select * from cams_subtrip where year=`y'" ; 
	
	/*	
	jdbc load, exec("`sql'") case(lower);
	*/
	odbc load, exec("`sql'; ")  $myNEFSC_USERS_conn;

	notes: "`sql'";
	notes: Joins of CAMS_SUBTRIP to CAMS_LAND must be done on CAMSID and subtrip;
	save $data_main/commercial/temp/cams_subtrip_`y'_$vintage_string.dta, replace;

	} ;
	
	
	
local st: dir "$data_main/commercial/temp" files "cams_subtrip_*_$vintage_string.dta" ;
clear;
foreach l of local st{;
	append using $data_main/commercial/temp/`l'	;
};
destring, replace;
compress;

notes: Joins of CAMS_SUBTRIP to CAMS_LAND must be done on CAMSID and subtrip ;
save $data_main/commercial/cams_subtrip_$vintage_string.dta, replace;
	
	
	
	foreach y of numlist $firstyr(1)$lastyr{;
	rm $data_main/commercial/temp/cams_subtrip_`y'_$vintage_string.dta ;
};

	
	
	
	
	
	
	foreach y of numlist $firstyr(1)$lastyr{;

	/* orphan subtrip */
	clear;


	local sql "select * from CAMS_VTR_ORPHANS_SUBTRIP where year=`y'" ; 
		
		
	/*	
	jdbc load, exec("`sql'") case(lower);
	*/
	odbc load, exec("`sql'; ")  $myNEFSC_USERS_conn;

	destring, replace;
	compress;

	notes: "`sql'";


	save $data_main/commercial/temp/cams_orphan_subtrip_`y'_$vintage_string.dta, replace;

};




local ost: dir "$data_main/commercial/temp" files "cams_orphan_subtrip_*_$vintage_string.dta" ;
clear;
foreach l of local ost{;
	append using $data_main/commercial/temp/`l'	, force;
};

save $data_main/commercial/cams_orphan_subtrip_$vintage_string.dta, replace;



	foreach y of numlist $firstyr(1)$lastyr{;
	rm $data_main/commercial/temp/cams_orphan_subtrip_`y'_$vintage_string.dta ;
};

	
	




