/* code to read in weekly landings of black sea bass and compute a price  */

# delimit ;
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select year, dnum, dlr, strt1, strt2, city, st, zip, doc from nefsc_garfo.permit_dealer" ;
	
clear;	
/*jdbc load, exec("`sql'") case(lower); */

odbc load, exec("`sql';") $myNEFSC_USERS_conn; 


destring, replace;
compress;


/* I need 1 obs per dnum and year, I will go with the 'last' of the year, which means keeping the max (doc) */

bysort dnum year (doc): gen keep=_n==_N;
keep if keep==1;
bysort dnum year: assert _N==1;
drop doc keep;


foreach var of varlist strt1 strt2 city st zip{;
	rename `var' dlr_`var';
};

rename dlr dlr_name;

save "${data_raw}\commercial\dealers_annual_${vintage_string}.dta", replace;


bysort dnum (year): keep if _n==_N;
drop year;

save "${data_raw}\commercial\dealers_${vintage_string}.dta", replace