/* code to read in weekly landings of black sea bass and compute a price  */
clear
jdbc connect , jar("$jar")  driverclass("$classname")  url("$NEFSC_USERS_URL")  user("$myuid") password("$mypwd")




local sql "select year, week, sum(value) as value, sum(lndlb) as landings, state from cams_land where itis_tsn='167687' and rec=0 group by year, week, state"
jdbc load, exec("`sql'") case(lower)



destring, replace
compress
format year %4.0f
format week %02.0f

encode state, gen(mys)

gen weekly_date=yw(year, week)

format weekly_date %tw

tsset mys weekly_date


gen price=value/landings

save "${data_main}\commercial\weekly_landings_${vintage_string}.dta", replace