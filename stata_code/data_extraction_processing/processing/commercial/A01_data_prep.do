/* code to do some data cleaning and preparations 
There are only a few "drops" in this bit of code:
1. I drop things that don't have a species code, this is mostly VTR discards, VTR not sold and vtr orphan species that don't have a price.  There are a few with novel market codes (XG) or grade codes (23) 
2. I drop out some observations from DE and VA that I strongly suspect are duplicates.
3. I drop rows where lndlb=0. I have no idea where these came from.
4. I drop rows that are too recent to get a GDP implicit price deflator. This would the current quarter and probably the most recent quarter.

Everything else is data creation or labeling. I prefer to do any 'dropping' as close to the estimation step as possible.
*/



use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq


/* how much of the CAMS landings are matched to a trip for black sea bass */
gen s2=status=="MATCH"
replace s2=1 if status=="DLR_ORPHAN_SPECIES"

gen day=day(dlr_date)
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* there's some suspect records from VA and DE in 2021 to present. Someone is cleaning these up, but I'm not sure who
I will handle the VA using this code
*/



gen questionable_status=0
replace questionable_status=1 if status=="PZERO" & state=="VA" & inlist(dlr_cflic,"2147","1148") & year>=2021
/* I will handle DE using this code, although I don't think it's right. */
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & price==0
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & port==80999
drop if questionable_status==1
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/**********************************************************************************************************************/



/*
I  need to be careful/concerned about a state-level 'dump' of data that has a made-up price.
PZEROS that are single transactions are not a problem. 
*/
drop if lndlb==0 



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




/* rebin Mixed or unsized to unclassified*/ 

replace market_desc="UNCLASSIFIED" if market_desc=="MIXED OR UNSIZED"
replace market_code="UN" if market_code=="MX"


/* bin Extra Small and PeeWee into Small */
replace market_code="SQ" if inlist(market_code,"PW", "ES")
replace market_desc="SMALL" if inlist(market_desc,"PEE WEE (RATS)", "EXTRA SMALL")

replace market_desc=proper(market_desc)
replace market_desc="Medium" if inlist(market_desc,"Medium Or Select")

replace market_code="JB" if market_code=="XG"
replace market_desc="Jumbo" if inlist(market_desc,"Extra Large")


label def market_category 1 "Jumbo" 2 "Large" 3 "Medium" 4 "Small" 5 "Extra Small" 6 "Unclassified"

rename market_desc market_desc_string
encode market_desc_string, gen(market_desc) label(market_category) 

/* encode grade */
replace grade_desc="Live" if grade_desc=="LIVE (MOLLUSCS SHELL ON)"
replace grade_desc="Round" if grade_desc=="UNGRADED"
replace grade_desc=proper(grade_desc)
label def grade_category 2 "Live" 1 "Round" 3 "Ungraded" 
encode grade_desc, gen(mygrade) label(grade_category) 
drop grade_desc
rename mygrade grade_desc


rename state state_string

label def state_fips  09 "CT" 10 "DE" 12 "FL" 23 "ME" 24 "MD" 25 "MA" 33 "NH" 34 "NJ" 36 "NY" 37 "NC" 42 "PA" 44 "RI" 45 "SC" 50 "VT" 51 "VA" 99 "CN"
encode state_string, gen(state) label(state_fips)


/* encode gear */
rename mygear mygear_string
encode mygear_string, gen(mygear)

/* Partition into northern and southern stock units */
label def stockunit  0 "Unknown" 1 "South" 2 "North" 

gen stockarea=0

/*south is 621 and greater, plus 614 and 615 */
replace stockarea=1 if area>=621
replace stockarea=1 if inlist(area,614,615)
/*north is 613 and smaller, plus 616 */
replace stockarea=2 if inlist(area,616)
replace stockarea=2 if area<=613 

assert stockarea>=1
label values stockarea stockunit


/* For dealer records with no federal permit number (permit = '000000'), the CAMSID is built as PERMIT, HULLID, dealer partner id, dealer link, and dealer date with the format PERMIT_HULLID_PARTNER_LINK_YYMMDD000000
do these camsids really correspond to a single "trip" or are they just state aggregated data?
*/
/* merge deflators _merge=1 has been the current month */ 
merge m:1 dateq using "$data_external/deflatorsQ_${in_string}.dta", keep(1 3)
assert year==2024 & month>=9 if _merge==1
drop if _merge==1
drop _merge
gen valueR_CPI=value/fCPIAUCSL_2023Q1

clonevar weighting=lndlb

/* this needs to be moved to the end  */
label var lndlb "landings pounds"

label var valueR_CPI "real dollars"
label var value "nominal dollars"

notes value: nominal value in dollars
notes valueR_CPI: real value in 2023Q1 CPIU adjusted dollars


label var year "Year"
label var month "Month"

gen semester=1 if month<=6
replace semester=2 if month>=7






save  "${data_main}\commercial\landings_cleaned_${vintage_string}.dta", replace






/* interact market category with landings*/
xi, prefix(_M) noomit i.market_desc*lndlb

/*  market level quantity supplied */
bysort dlr_date: egen DailyQJumbo=total(_MmarXlndlb_1)
bysort dlr_date: egen DailyQLarge=total(_MmarXlndlb_2)
bysort dlr_date: egen DailyQMedium=total(_MmarXlndlb_3)
bysort dlr_date: egen DailyQSmall=total(_MmarXlndlb_4)
bysort dlr_date: egen DailyQUnclassified=total(_MmarXlndlb_6)


/* Camsid, dlr_date (Trip) level quantity supplied */
bysort dlr_date camsid: egen OwnQJumbo=total(_MmarXlndlb_1)
bysort dlr_date camsid: egen OwnQLarge=total(_MmarXlndlb_2)
bysort dlr_date camsid: egen OwnQMedium=total(_MmarXlndlb_3)
bysort dlr_date camsid: egen OwnQSmall=total(_MmarXlndlb_4)
bysort dlr_date camsid: egen OwnQUnclassified=total(_MmarXlndlb_6)

/* market category landings by other vessels on this day */
foreach size in Jumbo Large Medium Small Unclassified {
	gen OtherQ`size'=DailyQ`size'-OwnQ`size'
}


/*  market level and state quantity supplied */
bysort dlr_date state: egen StateQJumbo=total(_MmarXlndlb_1)
bysort dlr_date state: egen StateQLarge=total(_MmarXlndlb_2)
bysort dlr_date state: egen StateQMedium=total(_MmarXlndlb_3)
bysort dlr_date state: egen StateQSmall=total(_MmarXlndlb_4)
bysort dlr_date state: egen StateQUnclassified=total(_MmarXlndlb_6)


/* market category and state landings by other vessels on this day */
foreach size in Jumbo Large Medium Small Unclassified {
	gen StateOtherQ`size'=StateQ`size'-OwnQ`size'
}


/*  market level and stockarea quantity supplied */

bysort dlr_date stockarea: egen StockareaQJumbo=total(_MmarXlndlb_1)
bysort dlr_date stockarea: egen StockareaQLarge=total(_MmarXlndlb_2)
bysort dlr_date stockarea: egen StockareaQMedium=total(_MmarXlndlb_3)
bysort dlr_date stockarea: egen StockareaQSmall=total(_MmarXlndlb_4)
bysort dlr_date stockarea: egen StockareaQUnclassified=total(_MmarXlndlb_6)

foreach size in Jumbo Large Medium Small Unclassified {
	gen StockareaOtherQ`size'=StockareaQ`size'-OwnQ`size'
}
 
 
 
 
 /* 
takea  look at here 
browse if dlr_date==mdy(5,1,2018)
order camsid dlr_date state market_desc lndlb tagstate ndistinct_state ndistinct_stockarea StateOtherQ* OtherQ* OwnQ* StockareaQ* StockareaOtherQ*
browse if dlr_date==mdy(5,1,2018)

*/


/* set the StateOtherQ columns to missing if there is only 1 trip on that day, state, market category */
egen tagstateM = tag(camsid state market_desc dlr_date)
egen ndistinct_stateM = total(tagstateM), by(state dlr_date market_desc)


foreach size in Jumbo Large Medium Small Unclassified{
	replace StateOtherQ`size'=. if ndistinct_stateM==1 & market_desc_string=="`size'"
}


/* set the StockareaOtherQ columns to missing if there is only 1 trip on that day, stockarea, market category */

egen tagstockareaM = tag(camsid stockarea market_desc dlr_date)
egen ndistinct_stockareaM = total(tagstockareaM), by(stockarea dlr_date market_desc)

foreach size in Jumbo Large Medium Small Unclassified {
	replace StockareaOtherQ`size'=. if ndistinct_stockareaM==1 & market_desc_string=="`size'"
}

drop _Mmarket* _MmarX* OwnQ*


/* distinct trips by state and day */
egen tagstate = tag(camsid state dlr_date)
egen ndistinct_state = total(tagstate), by(state dlr_date)

/* distinct trips by stockarea and day */
egen tagstockarea = tag(camsid stockarea dlr_date)
egen ndistinct_stockarea = total(tagstockarea), by(stockarea dlr_date)

/* distinct trips by day */
egen tag = tag(camsid dlr_date)
egen ndistinct_trips = total(tag), by(dlr_date)




order camsid dlr_date OtherQ* StateOtherQ* StateQ* DailyQ* StockareaOtherQ* StockareaQ* ndistinct_state ndistinct_stockarea ndistinct_trips

preserve

keep camsid dlr_date OtherQ* StateOtherQ* StateQ* DailyQ* StockareaOtherQ* StockareaQ*   ndistinct_state ndistinct_stockarea ndistinct_trips
collapse (first) Other* StateOther* StateQ* DailyQ* StockareaOtherQ* StockareaQ*, by(camsid dlr_date)
compress
foreach var of varlist Other* StateOther* StateQ* DailyQ* StockareaOtherQ* StockareaQ* {
	label variable `var' ""
}

sort dlr_date camsid
save "${data_main}\commercial\camsid_specific_cleaned_${vintage_string}.dta", replace
restore







/* Compute moving sums */
/*7 day moving sum of QJumbo, QLarge, QMedium, QSmall, QUnclassified */

keep camsid dlr_date state stockarea StateQ* DailyQ* StockareaQ* ndistinct_state ndistinct_stockarea ndistinct_trips
preserve
rename ndistinct_trips trips
collapse (first) DailyQ* trips, by(dlr_date)
tsset dlr_date
tsfill, full


foreach var of varlist DailyQ* trips{
	replace `var'=0 if `var'==.
    tssmooth ma MA7_`var'=`var', window(7 0 0)
	drop `var'
}

save "${data_main}\commercial\daily_ma_${vintage_string}.dta", replace
restore

/*7 day moving sum of StateQJumbo StateQLarge StateQMedium StateQSmall StateQUnclassified
collapsed by dlr_date, state
*/




preserve

collapse (first) StateQ* ndistinct_state, by(dlr_date state)
tsset state dlr_date
tsfill, full
rename ndistinct_state state_trips

foreach var of varlist StateQ* state_trips{
	replace `var'=0 if `var'==.
    tssmooth ma MA7_`var'=`var', window(7 0 0)
	drop `var'
}
save "${data_main}\commercial\state_ma_${vintage_string}.dta", replace
restore



/*
7 day moving sum of StockareaQJumbo StockareaQLarge StockareaQMedium StockareaQSmall StockareaQUnclassified
collapsed by dlr_date stockarea
*/


collapse (first) StockareaQ* ndistinct_stockarea, by(dlr_date stockarea)
tsset stockarea dlr_date
rename ndistinct_stockarea stockarea_trips
tsfill, full

foreach var of varlist StockareaQ* stockarea_trips{
	replace `var'=0 if `var'==.
    tssmooth ma MA7_`var'=`var', window(7 0 0)
	drop `var'
}
save "${data_main}\commercial\stockarea_ma_${vintage_string}.dta", replace

/* I could easily construct a variable for the number of trips that landed a particular market category (by state or stockarea).
Because states have possession limits, I think this is too close to the quantity landed variables to be worthwhile. 
But if I change my mind, I can operate on ndistinct_stateM and ndistinct_stockareaM */


/* historical dealnum things */

use "${data_main}\commercial\landings_cleaned_${vintage_string}.dta", replace
bysort dlrid camsid market_desc: gen TransactionCount=_n==1

keep if year>=2010 & year<=2014
/* sum by dlr and market category */
collapse (sum) lndlb TransactionCount, by(dlrid market_desc)
decode market_desc, gen(mymarket)

keep lndlb dlrid mymarket TransactionCount
/* reshape and zero fill */
reshape wide lndlb TransactionCount, i(dlrid) j(mymarket) string

local sizes Jumbo Large Medium Small Unclassified


foreach  l of local sizes {
	replace lndlb`l'=0 if lndlb`l'==.
	label var lndlb`l'  "Dealer level pounds purchased from 2010-2014 in market category `l'"
	
	replace TransactionCount`l'=0 if TransactionCount`l'==.
	label var TransactionCount`l'  "Dealer level number of transactions from 2010-2014 in market category `l' "

	
}

egen totalland=rowtotal(lndlb*)
egen totaltrans=rowtotal(TransactionCount*)



local sizes Jumbo Large Medium Small Unclassified
foreach l of local sizes{
	gen Share`l'=lndlb`l'/totalland
	label var Share`l' "Dealer Share of pounds from 2010-2014 in market category `l'"
	gen FracT`l'=TransactionCount`l'/totaltrans
	label var FracT`l' "Dealer Fraction of total transactions from 2010-2014 in market category `l'"

}
drop totalland totaltrans

order dlrid lndlb* TransactionCount* Share* FracT*

compress

notes: pounds landed and fraction pound landed of 
save "${data_main}\commercial\dlrid_historical_stats_${vintage_string}.dta", replace


