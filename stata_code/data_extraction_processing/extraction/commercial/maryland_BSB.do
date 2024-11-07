/* code to read in Maryland "IFQ" landings by permit 
Maryland has a 50 lbs 'open access' possession limit for BSB and up to 14 landings permits.  

This code filters out:
	1. trips (by camsid) that landed less than 50 lbs
	2. recreational trips
	
aggregates the rest to the permit-year level.


*/

#delimit ;
/* Pull data from CAMS, group by permit, year and species */
clear;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");


local sql "select permit, hullid, year, sum(landings) as landings, sum(value) as value from ( 
select permit, hullid, camsid, year, sum(nvl(lndlb,0)) as landings, sum(nvl(value,0)) as value from cams_land cl 
    where cl.itis_tsn=167687 and cl.state='MD' and cl.year>=2010 and cl.rec=0
    group by permit, hullid, camsid, year) A 
    where A.landings>50
    group by permit, hullid, year
    order by year, landings" ;
		
clear;
jdbc load, exec("`sql'") case(lower) ;
destring permit, replace;

save ${data_main}\commercial\MD_yearly_landings_by_type_${vintage_string}.dta, replace ;

