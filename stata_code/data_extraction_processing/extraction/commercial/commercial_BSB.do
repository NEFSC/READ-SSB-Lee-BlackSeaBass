/* code to read in annual landings of black sea bass by permit */
/* code to read in trip-level landings of all species on trips that landed at least 100lbs of BSB */

#delimit ;
/* Pull data from CAMS, group by permit, year and species */
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select permit, year, sum(nvl(lndlb,0)) as landings, sum(nvl(value,0)) as value, itis_tsn from cams_land cl where 
		itis_tsn =167687 
        group by permit, year, itis_tsn" ;
		
clear;
jdbc load, exec("`sql'") case(lower) ;
destring permit, replace;

gen str10 type="STATE" if inlist(permit,000000,190998,290998,390998,490998);
replace type="FEDERAL" if type=="";



save ${data_main}\commercial\yearly_landings_by_type_${vintage_string}.dta, replace ;


/* select trip level landings of all species from trips that had at least 100lbs of black sea bass landings */
local sql "select sum(lndlb) as landings, sum(value) as value, year, state, itis_tsn, itis_group1 from cams_land where camsid in (
	select distinct camsid from (
		select camsid, sum(lndlb) as landings from cams_land where itis_tsn=167687 group by camsid)
	where landings>100
)
     group by year, state, itis_tsn, itis_group1";

	 
	 
clear;
jdbc load, exec("`sql'") case(lower) ;

save ${data_main}\commercial\subtrip_landings_${vintage_string}.dta, replace ;


collapse (sum) landings value, by(itis_tsn year itis_group);

format year %4.0f;
sort year value;
bysort year: egen tv=total(value);
gen pct=value/tv;
drop tv;
gsort year -pct;
browse if pct>=.01;

save ${data_main}\commercial\annual_landings_on_BSB_trips_${vintage_string}.dta, replace ;
