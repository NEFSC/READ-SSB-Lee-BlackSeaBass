/* code to read in weekly landings of black sea bass and compute a price  */
# delimit ;
clear ;
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd");




local sql "select EXTRACT(YEAR FROM d.date_land) as year, d.state1, sum(nvl(c.kept,0)) as kept  from nefsc_garfo.trip_reports_catch c
    left join nefsc_garfo.trip_reports_images i
    on c.imgid=i.imgid
    LEFT JOIN nefsc_garfo.trip_reports_document d
        on i.docid=d.docid
    where c.species_id='BSB' and d.tripcatg in ('1','4')
    group by EXTRACT(YEAR FROM d.date_land), state1
    order by year, state1" ;
jdbc load, exec("`sql'") case(lower);

rename kept veslog_kept_lbs ;
rename state1 state;
compress;
save "${data_main}\commercial\veslog_annual_state_landings_${vintage_string}.dta", replace ;

collapse (sum) veslog_kept_lbs, by(year) ;
save "${data_main}\commercial\veslog_annual_landings_${vintage_string}.dta", replace ;