
graph drop _all
global in_string 2024_12_20
use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq
gen day=day(dlr_date)

gen questionable_status=0
replace questionable_status=1 if status=="PZERO" & state=="VA" & inlist(dlr_cflic,"2147","1148") & year>=2021
/* I will handle DE using this code, although I don't think it's right. */
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & price==0
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & port==80999



collapse (sum) value lndlb livlb, by(camsid hullid negear record_sail record_land dlr_date market_code grade_code dlrid state grade_desc market_desc dateq year month questionable_status)



gen price=value/lndlb





/* merge deflators _merge=1 has been the current month */ 
merge m:1 dateq using "$data_external/deflatorsQ_${in_string}.dta", keep(1 3)
assert year==2024 & month>=9 if _merge==1
drop if _merge==1
drop _merge

gen priceR_CPI=price/fCPIAUCSL_2023Q1
notes priceR_CPI: real price in 2023Q1 CPIU adjusted dollars

gen valueR_CPI=value/fCPIAUCSL_2023Q1

notes valueR_CPI: real value in 2023Q1 CPIU adjusted dollars

/* merge gearcodes */
merge m:1 negear using "${data_main}\commercial\cams_gears_${in_string}.dta", keep(1 3)

assert _merge==3
drop _merge


/* need to construct a gear category variable , based on the gear lookup table*/
/*
order negear negear_name mesh_match secgear_mapped fmcode
bysort negear: gen t=_n==1
browse if t==1
*/
gen str mygear="LineHand" if  inlist(negear,10, 20,21,30, 34,40, 420,60,62,65,66) 
replace mygear="LineHand" if negear>=220 & negear<=230
replace mygear="LineHand" if inlist(negear,250, 251, 330, 340, 380,414,90,410) 

replace mygear="Trawl" if negear>=50 & negear<=59
replace mygear="Trawl" if  inlist(negear,150, 170, 71,160,350,351,353,370,450) 
replace mygear="Gillnet" if negear>=100 & negear<=117
replace mygear="Gillnet" if  inlist(negear,500,520) 

replace mygear="Seine" if negear>=120 & negear<=124 
replace mygear="Seine" if inlist(negear,70, 71,160,360) 
replace mygear="PotTrap" if negear>=180 & negear<=212 
replace mygear="PotTrap" if negear>=300 & negear<=301
replace mygear="PotTrap" if inlist(negear,80, 140, 142, 240, 260, 270, 320, 322) /* includes weirs and pounds */ 



replace mygear="Dredge" if negear>=381 & negear<=383
replace mygear="Dredge" if inlist(negear,132,400) 
replace mygear="Unknown" if inlist(negear,999) 


replace mygear="Misc" if inlist(mygear,"Dredge","Unknown", "Seine")

/* rebin Mixed or unsized to unclassified 
rebin pee wee to extra small */ 

replace market_desc="UNCLASSIFIED" if market_desc=="MIXED OR UNSIZED"
replace market_code="UN" if market_code=="MX"

replace market_desc="MEDIUM" if market_desc=="MEDIUM OR SELECT"




/* the PEE WEE (RATS) looks a little odd. */
replace market_desc="EXTRA SMALL" if market_desc=="PEE WEE (RATS)"
replace market_code="ES" if market_code=="PW"

label def market_category 1 "JUMBO" 2 "LARGE" 3 "MEDIUM" 4 "SMALL" 5 "EXTRA SMALL" 6 "UNCLASSIFIED" 7 "PEE WEE (RATS)"

encode market_desc, gen(mym) label(market_category) 


replace grade_desc="LIVE" if grade_desc=="LIVE (MOLLUSCS SHELL ON)"

label def grade_category 2 "LIVE" 1 "ROUND" 3 "UNGRADED" 


encode grade_desc, gen(mygrade) label(grade_category) 
encode state, gen(mys)
rename mygear mygear_string
encode mygear_string, gen(mygear)

gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(market_code, "ES","MX", "PW")
replace keep=0 if inlist(state, "CN","FL","ME", "NH","PA","SC")
replace keep=0 if inlist(grade_desc,"UNGRADED")
replace keep=0 if price>=15



drop if price>=15


*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)
replace total=total/1000

/*******************************Investigate Prices ********************************************/
/* there are definitely more common prices at the $1, $0.50, $0.25, and even $0.05 per pound */
hist price if price<=10, width(.05) xlabel(0(1)10) xmtick(##2)


levelsof market_desc, local(sizes)
	local j=1

foreach l of local sizes{
	hist price if market_desc=="`l'" & price<=10, width(.25) xlabel(0(1)8) xmtick(##2) title("`l'") name(p`j', replace)
	hist price if market_desc=="`l'" & price<=10 [fweight=lndlb], width(.25) xlabel(0(1)8) xmtick(##2) title("`l' (weighted)") name(wp`j', replace)

	local ++ j 
}

graph combine p2 p3 p4 p5 p1 p6, name(price_hist, replace)
graph export ${exploratory}\price_histograms.png, as(png) width(2000) replace
graph combine wp2 wp3 wp4 wp5 wp1 wp6, name(wprice_hist, replace)
graph export ${exploratory}\wprice_histograms.png, as(png) width(2000) replace



graph box price if price<=10,  nooutside over(mygrade, label(labsize(vsmall) angle(45))) over(mym, label(labsize(tiny) angle(45))) name(price_box)
vioplot price if price<=10, over(market_desc) name(price_vio)

gen mygrade_short="R" if mygrade==1
replace mygrade_short="L" if mygrade==2
replace mygrade_short="U" if mygrade==3
vioplot price if price<=10, over(mygrade_short) over(mym)

graph export ${exploratory}\vio_grades.png, as(png) width(2000) replace


/****************************************
There's something funky going on with the Extra smalls. By price, they more closely resemble the Large or mediums.  
The Unclassifieds make more sense they certainly seem to be a mix of Large, Medium, and Small by prices


****************************************/

levelsof year, local(yearlist)
sort year mym
foreach y of local yearlist{

	graph box price if price<=10 & year==`y'& mygrade<=2 & mym~=5, nooutside over(mygrade, label(labsize(vsmall) angle(45))) over(mym, label(labsize(tiny) angle(45))) name(price_box`y') title("`y' ")
	graph export ${exploratory}\price_box`y'.png, as(png) width(2000) replace

	graph box price if price<=10 & year==`y'& mygrade<=2 & mym~=5  [fweight=lndlb], nooutside  over(mygrade, label(labsize(vsmall) angle(45))) over(mym, label(labsize(tiny) angle(45))) name(Wprice_box`y') title("`y' ")
	graph export ${exploratory}\Wprice_box`y'.png, as(png) width(2000) replace

}

/* but there is very little extra small */
preserve
collapse (sum) lndlb livlb, by(mym)
browse
egen t=total(lndlb)
gen frac=lnd/t
gsort - frac
list mym frac
restore












/*******************************Quantity Landed/sold in each transaction ********************************************/


/* there are *lots* of records of really small numbers of pounds 
The median landings report at the market category-size level in the 10-30 lbs range.

Whatever I do, I will need to figure out how to appropriately handle observations where there 5 lbs of landings relative to 100, 500, or 2000  lbs 

*/
centile lndlb, centile(5 10 25 50 75 90 95)
bysort mym: centile lndlb, centile(5 10 25 50 75 90 95)


bysort camsid: egen tl=total(lndlb)
bysort camsid: gen first=_n==1
/* and the median landings is 50 lbs per trip */
centile tl if first==1, centile(5 10 25 50 75 90 95)

preserve
gen large_trip =tl>=50

collapse (sum)lndlb, by(large_trip)
egen t=total(lndlb)
gen frac=lndlb/t
list large lndlb frac
/* However well over 95% of total landings are on "large" trips */

restore




bysort camsid: gen numobs=_N

/* 90% of the trips reports 3 or fewer observations  Ther are a handful of outliers way out on the tail.*/
tab numobs if first==1












/* does a vessel bring in both graded and ungraded fish on 1 trip?*/

gen unc=mym==7
bysort camsid: egen tunc=total(unc)
replace tunc=1 if tunc>=1

gen class=mym<7
bysort camsid: egen tc=total(class)

replace tc=1 if tc>=1
tab tc tunc

/* yes, about 2% of the trips that reported a classified market category also reported an unclassified market category 
25% of the trips that reported an unclassifed market category also reported a classified one, which I find a little odd.*/



replace lndlb=lndlb/1000


/* what's the distrinbution within a year*/
preserve

collapse (sum) lndlb value, by(month mym )

bysort month: egen tl=total(lndlb)
gen frac=lndlb/tl


/* there are a bit more landings of unclassified in summer (may-sept/oct) */
graph bar (asis) lndlb, over(mym) asyvars stack over(month)  ytitle("landings 000s pounds")
graph export ${exploratory}\market_cats_within_year.png, as(png) width(2000)  replace

graph bar (asis) frac, over(mym) asyvars stack over(month)
graph export ${exploratory}\fmarket_cats_within_year.png, as(png) width(2000) replace

restore


/* what's the over time?*/

preserve
collapse (sum) lndlb value, by(year mym )

bysort year: egen tl=total(lndlb)
gen frac=lndlb/tl


/* Smalls really go away by the mid 2000s 
Lots more Jumbos and Larges in latter part of the time series.  Landings spike in 2017.  Pretty big drop in 2009.
And a bit of an uptick in Unclassifieds in 2019-2023
*/
graph bar (asis) lndlb, over(mym) asyvars stack over(year, label(angle(45))) ytitle("landings 000s pounds")

graph export ${exploratory}\market_cats_over_time.png, as(png) width(2000) replace


graph bar (asis) frac, over(mym) asyvars stack  over(year, label(angle(45)))
graph export ${exploratory}\fmarket_cats_over_time.png, as(png) width(2000) replace




/* Just look at 2018 to present, which covers the 2020-2023 no Unclassified years
*/

keep if year>=2018
graph bar (asis) lndlb, over(mym) asyvars stack over(year, label(angle(45))) ytitle("landings 000s pounds")

graph export ${exploratory}\market_cats_over_2018.png, as(png) width(2000) replace


graph bar (asis) frac, over(mym) asyvars stack  over(year, label(angle(45)))
graph export ${exploratory}\fmarket_cats_over_2018.png, as(png) width(2000) replace
restore




/* Just look at 2020-2023 to get a sense of how much questionable landings there might be from DE and VA.*/
preserve
keep if year>=2020 & year<=2023

collapse (sum) lndlb value, by(mym questionable_status)


bysort mym: egen tl=total(lndlb)
gen frac=lndlb/tl


graph bar (asis) lndlb, over(questionable_status) asyvars stack over(mym, label(angle(45))) ytitle("landings 000s pounds")
graph export ${exploratory}\questionable2020.png, as(png) width(2000) replace


graph bar (asis) frac, over(questionable_status) asyvars stack over(mym, label(angle(45))) ytitle("fraction")
graph export ${exploratory}\fquestionable2020.png, as(png) width(2000) replace

restore






preserve
collapse (sum) lndlb value, by(state mym )
drop if inlist(state, "CN","FL","ME", "NH","PA","SC")

bysort state: egen tl=total(lndlb)
gen frac=lndlb/tl


/* Proportionally more unclassifieds in CT, DE, MA, and NY
I droppped out a few random states.
*/
graph bar (asis) lndlb, over(mym) asyvars stack over(state, label(angle(45))) ytitle("landings 000s pounds")
graph export ${exploratory}\market_cats_by_state.png, as(png) width(2000) replace

graph bar (asis) frac, over(mym) asyvars stack  over(state, label(angle(45)))
graph export ${exploratory}\fmarket_cats_by_state.png, as(png) width(2000) replace

restore






preserve
collapse (sum) lndlb value, by(year state mym )
drop if inlist(state, "CN","FL","ME", "NH","PA","SC")

bysort year: egen tyl=total(lndlb)
gen fracy=lndlb/tyl

bysort year state: egen tyls=total(lndlb)
gen frac=lndlb/tyls




levelsof state, local(states)
	local j=1

foreach l of local states{

	graph bar (asis) frac if state=="`l'", over(mym) asyvars stack over(year, label(angle(45)))  title("Size composition in State `l'")  name(Fstate`j', replace)
	graph export ${exploratory}\market_cats_`l'.png, as(png) width(2000) replace

	graph bar (asis) lndlb if state=="`l'", over(mym) asyvars stack over(year, label(angle(45))) title("Size composition in State `l'") name(Lstate`j', replace)
	graph export ${exploratory}\fmarket_cats_`l'.png, as(png) width(2000) replace

	local ++ j 
}

/********
Dealers start classifying in

CT in 2007, although about 20% is still unclassified.
DE in 2001, although the unclassifieds come back in 2022 and 2023.
MA is always classified, although 15 to 20% are unclassified. 
MD is always classified, although there are a few years when it's picks up to 20+%
	MD might also be responsible for the extra smalls in our data in 2018
NC is always classified. And lots of Jumbo.	
NJ is always classified, with about 5-10% per year Unclassified. Jumbo and Large have been increasing there too

NY has quite alot of unclassified Typically 30%
RI starts classifying in 1997, typically less than 5% unclassified.
VA is all classified, except for 2021 to 2023.

One trip pulled in substantially all the Extra small in MD ever in 2019. This feels a little sketch
browse if market_code=="ES" & state=="MD"

*****************/

restore





preserve
collapse (sum) lndlb value, by(year mygear_string )

bysort year: egen tyl=total(lndlb)
gen fracy=lndlb/tyl

bysort year: egen tyls=total(lndlb)
gen frac=lndlb/tyls



/* Proportionally more unclassifieds in CT, DE, MA, and NY
I droppped out a few random states.
*/
graph bar (asis) lndlb, over(mygear_string) asyvars stack over(year, label(angle(45)))  ytitle("landings 000s pounds")
graph export ${exploratory}\gears_by_year.png, as(png) width(2000) replace

graph bar (asis) frac, over(mygear_string) asyvars stack over(year, label(angle(45)))
graph export ${exploratory}\fgears_by_year.png, as(png) width(2000) replace

restore




/* time series of prices by state */
collapse (sum) lndlb value valueR, by(state mym year)
drop if inlist(state, "CN","FL","ME", "NH","PA","SC")

bysort state: egen tl=total(lndlb)
gen frac=lndlb/tl
gen price=value/lndlb*1000

gen priceR=valueR/lndlb*1000


levelsof state, local(states)



foreach l of local states{
	preserve
		keep if state=="`l'"
		tsset mym year

		xtline price if inlist(mym,1,2,3,4)==1, overlay xlabel(1995(5)2025) xmtick(##5) title("`l'")
		graph export ${exploratory}\price_overtime_`l'.png, as(png) width(2000) replace
		
		xtline priceR if inlist(mym,1,2,3,4)==1, overlay xlabel(1995(5)2025) xmtick(##5) title("`l'")
		graph export ${exploratory}\priceR_overtime_`l'.png, as(png) width(2000) replace


	restore
}


levelsof mym, local(sizes)

collapse (sum) lndlb value valueR, by(state mym year)
encode state, gen(mystate)

gen price=value/lndlb*1000

gen priceR=valueR/lndlb*1000


foreach l of local sizes{
	preserve
		keep if mym==`l'
		
		tsset mystate year

		xtline price, overlay xlabel(1995(5)2025) xmtick(##5) title("`l'") legend(rows(2))
		graph export ${exploratory}\price_overstate_`l'.png, as(png) width(2000) replace
		
		xtline priceR, overlay xlabel(1995(5)2025) xmtick(##5) title("`l'") legend(rows(2))
		graph export ${exploratory}\priceR_overstate_`l'.png, as(png) width(2000) replace


	restore
}






/* there's definitely a data error with small in NY in 2002 

Which is mostly traced back to this CAMSID 320410_20020201194500_1483483


At least at the year level, I'm not seeing an effect of the 2004 catch share in MD and VA on prices. There's an upward trend starting in early 2000. It continues for a while. It also is in other states. 
*/

