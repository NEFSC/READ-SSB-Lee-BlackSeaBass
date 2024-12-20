/* code to read in weekly landings of black sea bass and compute a price  */


# delimit ;
clear ;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select cl.permit, cl.year, cl.itis_tsn, cl.state, sum(cl.lndlb) as landings, sum(cl.value) as value,  sum(st.lat_dd*cl.lndlb)/sum(cl.lndlb) as lat_mean, sum(st.lon_dd*cl.lndlb)/sum(cl.lndlb) as lon_mean from cams_land cl 
 LEFT JOIN CAMS_SUBTRIP st
    on cl.camsid=st.camsid and cl.subtrip=st.subtrip
 where cl.itis_tsn=167687 and cl.year>=2000 and st.lat_dd is not null and st.lon_dd is not null and cl.lndlb>0 and cl.rec=0
 group by cl.year, cl.permit, cl.itis_tsn, cl.state"; 

jdbc load, exec("`sql'") case(lower);

destring, replace;
compress;
format year %4.0f;

encode state, gen(mys);

save "${data_main}\commercial\bsb_locations_landings_${vintage_string}.dta", replace;