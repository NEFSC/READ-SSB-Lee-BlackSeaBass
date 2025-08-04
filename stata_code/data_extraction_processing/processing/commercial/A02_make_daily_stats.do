**********************************************************************
* Purpose: 	code to make the "daily statistics files"

* Inputs:
*   - landings_cleaned_$date.dta (
* Outputs:
*   - daily_ma_$date.dta /*7 day moving sum of QJumbo, QLarge, QMedium, QSmall, QUnclassified */
*   - state_ma_$date.dta /*7 day moving sum of StateQJumbo StateQLarge StateQMedium StateQSmall StateQUnclassif */
*   - stockarea_ma_$date.dta /*7 day moving sum of StockareaQJumbo StockareaQLarge StockareaQMedium StockareaQSmall StockareaQUnclassified */
*   - gear_ma_$date.dta /*7 day moving sum of gearQJumbo gearQLarge gearQMedium gearQSmall gearQUnclassified */
*   - daily_ma_$date.dta /*7 day moving sum of QJumbo, QLarge, QMedium, QSmall, QUnclassified */
*   - camsid_specific_cleaned_ /* landings specific to the camsid, mostly landings by "other trips" */
**********************************************************************


use  "${data_main}\commercial\landings_cleaned_${vintage_string}.dta", replace 


gen lndlbxJumbo=market_desc_string=="Jumbo"
gen lndlbxLarge=market_desc_string=="Large"
gen lndlbxMedium=market_desc_string=="Medium"
gen lndlbxSmall=market_desc_string=="Small"
gen lndlbxUnclassified=market_desc_string=="Unclassified"

foreach var of varlist lndlbxJumbo lndlbxLarge lndlbxMedium lndlbxSmall lndlbxUnclassified{
	replace `var'=`var'*lndlb
}

/*  market level quantity supplied */
bysort dlr_date: egen DailyQJumbo=total(lndlbxJumbo)
bysort dlr_date: egen DailyQLarge=total(lndlbxLarge)
bysort dlr_date: egen DailyQMedium=total(lndlbxMedium)
bysort dlr_date: egen DailyQSmall=total(lndlbxSmall)
bysort dlr_date: egen DailyQUnclassified=total(lndlbxUnclassified)


/* Camsid, dlr_date (Trip) level quantity supplied */
bysort dlr_date camsid: egen OwnQJumbo=total(lndlbxJumbo)
bysort dlr_date camsid: egen OwnQLarge=total(lndlbxLarge)
bysort dlr_date camsid: egen OwnQMedium=total(lndlbxMedium)
bysort dlr_date camsid: egen OwnQSmall=total(lndlbxSmall)
bysort dlr_date camsid: egen OwnQUnclassified=total(lndlbxUnclassified)

/* market category landings by other vessels on this day */
foreach size in Jumbo Large Medium Small Unclassified {
	gen OtherQ`size'=DailyQ`size'-OwnQ`size'
	assert OtherQ`size'>=0
}


/*  market level and state quantity supplied */
bysort dlr_date state: egen StateQJumbo=total(lndlbxJumbo)
bysort dlr_date state: egen StateQLarge=total(lndlbxLarge)
bysort dlr_date state: egen StateQMedium=total(lndlbxMedium)
bysort dlr_date state: egen StateQSmall=total(lndlbxSmall)
bysort dlr_date state: egen StateQUnclassified=total(lndlbxUnclassified)

/* Camsid, dlr_date (Trip) level quantity supplied */
bysort dlr_date camsid state: egen StateOwnQJumbo=total(lndlbxJumbo)
bysort dlr_date camsid state: egen StateOwnQLarge=total(lndlbxLarge)
bysort dlr_date camsid state: egen StateOwnQMedium=total(lndlbxMedium)
bysort dlr_date camsid state: egen StateOwnQSmall=total(lndlbxSmall)
bysort dlr_date camsid state: egen StateOwnQUnclassified=total(lndlbxUnclassified)



/* market category and state landings by other vessels on this day */
foreach size in Jumbo Large Medium Small Unclassified {
	gen StateOtherQ`size'=StateQ`size'-StateOwnQ`size'
    assert StateOtherQ`size'>=0
}
drop StateOwnQ*



/*  market level and stockarea quantity supplied */

bysort dlr_date stockarea: egen StockareaQJumbo=total(lndlbxJumbo)
bysort dlr_date stockarea: egen StockareaQLarge=total(lndlbxLarge)
bysort dlr_date stockarea: egen StockareaQMedium=total(lndlbxMedium)
bysort dlr_date stockarea: egen StockareaQSmall=total(lndlbxSmall)
bysort dlr_date stockarea: egen StockareaQUnclassified=total(lndlbxUnclassified)


/*  market level and stockarea own quantity  */

bysort dlr_date camsid stockarea: egen StockareaOwnQJumbo=total(lndlbxJumbo)
bysort dlr_date camsid stockarea: egen StockareaOwnQLarge=total(lndlbxLarge)
bysort dlr_date camsid stockarea: egen StockareaOwnQMedium=total(lndlbxMedium)
bysort dlr_date camsid stockarea: egen StockareaOwnQSmall=total(lndlbxSmall)
bysort dlr_date camsid stockarea: egen StockareaOwnQUnclassified=total(lndlbxUnclassified)

/*  market level and stockarea quantity supplied */

bysort dlr_date mygear: egen gearQJumbo=total(lndlbxJumbo)
bysort dlr_date mygear: egen gearQLarge=total(lndlbxLarge)
bysort dlr_date mygear: egen gearQMedium=total(lndlbxMedium)
bysort dlr_date mygear: egen gearQSmall=total(lndlbxSmall)
bysort dlr_date mygear: egen gearQUnclassified=total(lndlbxUnclassified)








foreach size in Jumbo Large Medium Small Unclassified {
	gen StockareaOtherQ`size'=StockareaQ`size'- StockareaOwnQ`size'
    assert StockareaOtherQ`size'>=0

}
 
drop StockareaOwnQ*

 
 
 /* 
takea  look at here 
browse if dlr_date==mdy(5,1,2018)
order camsid dlr_date state market_desc lndlb tagstate ndistinct_state ndistinct_stockarea StateOtherQ* OtherQ* OwnQ* StockareaQ* StockareaOtherQ*
browse if dlr_date==mdy(5,1,2018)

*/


/* set the StateOtherQ columns to missing if there is only 1 trip on that day, state, market category */
egen tagstateM = tag(camsid state market_desc dlr_date)
egen ndistinct_stateM = total(tagstateM), by(state dlr_date market_desc)

/*
foreach size in Jumbo Large Medium Small Unclassified{
	replace StateOtherQ`size'=. if ndistinct_stateM==1 & market_desc_string=="`size'"
}
*/

/* set the StockareaOtherQ columns to missing if there is only 1 trip on that day, stockarea, market category */

egen tagstockareaM = tag(camsid stockarea market_desc dlr_date)
egen ndistinct_stockareaM = total(tagstockareaM), by(stockarea dlr_date market_desc)
/*
foreach size in Jumbo Large Medium Small Unclassified {
	replace StockareaOtherQ`size'=. if ndistinct_stockareaM==1 & market_desc_string=="`size'"
}
*/


egen tagstockareaG = tag(camsid mygear market_desc dlr_date)
egen ndistinct_gear = total(tagstockareaG), by(mygear dlr_date market_desc)





drop lndlbx* OwnQ*


/* distinct trips by state and day */
egen tagstate = tag(camsid state dlr_date)
egen ndistinct_state = total(tagstate), by(state dlr_date)

/* distinct trips by stockarea and day */
egen tagstockarea = tag(camsid stockarea dlr_date)
egen ndistinct_stockarea = total(tagstockarea), by(stockarea dlr_date)

/* distinct trips by day */
egen tag = tag(camsid dlr_date)
egen ndistinct_trips = total(tag), by(dlr_date)




order camsid dlr_date OtherQ* StateOtherQ* StateQ* DailyQ* StockareaOtherQ* StockareaQ* gearQ*  ndistinct_state ndistinct_stockarea ndistinct_trips ndistinct_gear

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

keep camsid dlr_date state stockarea mygear StateQ* DailyQ* StockareaQ* gearQ*  ndistinct_state ndistinct_stockarea ndistinct_trips ndistinct_gear
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

preserve
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

restore



/*
7 day moving sum of StockareaQJumbo StockareaQLarge StockareaQMedium StockareaQSmall StockareaQUnclassified
collapsed by dlr_date stockarea
*/

preserve
collapse (first) gearQ* ndistinct_gear, by(dlr_date mygear)
tsset mygear dlr_date
rename ndistinct_gear gear_trips
tsfill, full

foreach var of varlist gearQ* gear_trips{
	replace `var'=0 if `var'==.
    tssmooth ma MA7_`var'=`var', window(7 0 0)
	drop `var'
}
save "${data_main}\commercial\gear_ma_${vintage_string}.dta", replace

restore










