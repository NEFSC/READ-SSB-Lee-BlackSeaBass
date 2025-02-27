/* THIS BIT OF CODE IS USED TO EXTRACT VESSEL PERMITS*/
#delimit;

global lastyr 2025;

clear;
odbc load, exec("select vp.ap_year, vp.ap_num, vp.vp_num, vp.plan, vp.cat, vp.start_date, vp.end_date, vp.date_expired, vp.date_canceled from nefsc_garfo.permit_vps_fishery_ner vp where 
	ap_year between 1996 and $lastyr
    order by vp_num, ap_num;")  $myNEFSC_USERS_conn;
    destring, replace;
    renvars, lower;
    
    gen mys=dofc(start_date);
    gen myend=dofc(end_date);
    gen myexp=dofc(date_expired);
    gen mycanc=dofc(date_canceled);

    format my* %td;
drop start_date end_date date_expired date_canceled;
rename mys start_date;
rename myend end_date;
rename myexp date_expired;
rename mycanc date_canceled;
gen  myde=min(end_date, date_expired, date_canceled);
format myde %td;
drop if start_date>=myde | start_date>=myde;

save ${data_main}/commercial/vps_fishery_raw_$today_date_string.dta, replace ;


/*I want to make a dataset that contains the VP_NUM, FY, PLANS_CATS that were active in a FY */

/* I'll make a set of dummies that is 
1 if the permit start_date was before the end of the fishing year AND the permit end_date was after the beginning of the fishing year
*/
















forvalues j=1996(1)$lastyr{;
	gen a`j'=0;
	local k=`j'+1;
	replace a`j'=1 if start_date<mdy(5,1,`k') & myde>=mdy(5,1,`j');
};

collapse (sum) a1996-a$lastyr, by(vp_num plan cat);
foreach var of varlist a*{;
	replace `var'=1 if `var'>=1;
};
reshape long a, i(vp_num plan cat) j(fishing_year);

replace a=1 if a>=1;
drop if a==0;

/*save permits, replace; */
gen plancat=plan + "_" + cat;
drop plan cat;
reshape wide a, i(vp_num fishing_year) j(plancat) string;

foreach var of varlist a*{;
	replace `var'=0 if `var'==.;
	};
renvars a*, predrop(1);

rename vp_num permit;
qui compress;
notes: made by "permit_characteristics_extractions.do";
save ${data_main}\commercial/permit_working_$today_date_string.dta, replace ;




/* THIS BIT OF CODE IS USED TO EXTRACT VESSEL Characteristics*/

#delimit ;
clear;
odbc load, exec("select ap_year, ap_num, vp_num, hull_id, ves_name, strt1, strt2, city, st, zip1, zip2, tel, hport, hpst, pport, ppst, len, crew, gtons, 
ntons, vhp, blt, hold, toc,top, date_issued, date_canceled, max_trap_limit
from nefsc_garfo.permit_vps_vessel where ap_year between 1996 and $lastyr;")  $myNEFSC_USERS_conn;
    destring, replace;
    renvars, lower;
    gen mys=dofc(date_issued);
    gen myend=dofc(date_canceled);
drop date_issued date_canceled;

rename mys date_issued;
rename myend date_canceled;
format date* %td;

tempfile permit_working;
save `permit_working', replace;

forvalues j=1996(1)$lastyr{;
	tempfile new;
	local NEWfiles `"`NEWfiles'"`new'" "'  ;

	use `permit_working', clear;
	gen a`j'=0;
	local k=`j'+1;
	replace a`j'=1 if date_issued<mdy(5,1,`k') & date_canceled>=mdy(5,1,`j');
	bysort vp_num a`j' (ap_num): replace a`j'=0 if _n<_N;
	keep if a`j'==1;
	keep vp_num-top max_trap_limit;
	gen fishing_year=`j';
	save `new';
	clear;
};

append using `NEWfiles';



rename vp_num permit;



/* This bit joins them */

merge 1:1 permit fishing_year using ${data_main}\commercial/permit_working_$today_date_string;
save ${data_main}\commercial/permit_portfolio_$today_date_string,  replace;


keep hull_id fishing_year max_trap_limit;

save "${data_main}\commercial/lobster_traps_$today_date_string, replace;







