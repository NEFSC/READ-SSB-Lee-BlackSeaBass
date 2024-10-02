/* code to read in weekly landings of black sea bass and compute a price  */

# delimit ;
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");





local sizes "select nespp4, species_itis as itis_tsn, grade_code, grade_desc, market_code, market_desc, cf_lndlb_livlb from cfdbs.species_itis_ne where species_itis=167687 order by nespp4";
	
jdbc load, exec("`sizes'") case(lower);
duplicates drop;
destring, replace;
notes: grade_code=00 appears to be a "ungraded" and has a landed-live ratio that is 1.18, so it's probably a gutted weight.;
notes: grade_code==01 and 02 are whole (round and live).;
notes: the market code seems to have borrowed terms from striped bass (Pee Wee/Rats and Schall Schoolies);
save "${data_main}\commercial\bsb_sizes_${vintage_string}.dta", replace;



local sql "select year, month, week, dlr_date, dlr_mkt as market_code , dlr_grade as grade_code , itis_tsn, sum(lndlb) as landings, sum(value) as value, sum(livlb) as live from cams_land where itis_tsn='167687' 
	and status in ('MATCH','DLR_ORPHAN_SPECIES', 'PZERO', 'DLR_ORPHAN_TRIP') 
    group by dlr_mkt, dlr_grade, dlr_date, year, month, week, itis_tsn" ;
	
clear;	
jdbc load, exec("`sql'") case(lower);



destring, replace;
compress;
format year %4.0f;
format week month %02.0f;

gen price=value/landings;

save "${data_main}\commercial\daily_landings_category_${vintage_string}.dta", replace;

merge m:1 itis_tsn grade_code market_code using "${data_main}\commercial\bsb_sizes_${vintage_string}.dta", keep(1 3);

save "${data_main}\commercial\daily_landings_category_${vintage_string}.dta", replace;
