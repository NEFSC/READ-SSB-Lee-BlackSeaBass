/* code to read in weekly landings of black sea bass and compute a price  */

# delimit ;
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select st.docid, st.subtrip, st.area, st.negear, st.mesh_cat, st.record_sail, st.record_land, st.ves_len, st.geartype , cl.camsid, cl.permit, cl.hullid, cl.year, cl.month, cl.week, cl.dlr_date, cl.dlr_mkt as market_code, cl.dlr_grade as grade_code, cl.dlrid, cl.itis_tsn, cl.state, cl.port, cl.lndlb , cl.value , cl.livlb, cl.status from cams_land cl 
    LEFT JOIN cams_subtrip st
    on cl.camsid=st.camsid 
    where cl.itis_tsn='167687' 
        and cl.status in ('MATCH','DLR_ORPHAN_SPECIES', 'PZERO', 'DLR_ORPHAN_TRIP')" ;
	
clear;	
jdbc load, exec("`sql'") case(lower);



destring, replace;
compress;
format year %4.0f;
format week month %02.0f;

gen price=value/livlb;

save "${data_raw}\commercial\landings_all_${vintage_string}.dta", replace;

merge m:1 itis_tsn grade_code market_code using "${data_raw}\commercial\bsb_sizes_${vintage_string}.dta", keep(1 3);

rename _merge merge_species_codes;
save "${data_raw}\commercial\landings_all_${vintage_string}.dta", replace;
