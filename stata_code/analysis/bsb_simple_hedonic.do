**********************************************************************
* Purpose: 	code to estimate simple  hedonic models. There is some code to try some mixed linear models, but I didn't go too far down that road.
* Inputs:
*   - BSB_original_combined_dataset$date.dta (from wrappers)
*
* Outputs:
*   -  hedonic models by ols and classification models by mlogit 
*   - omitted_transactions.dta a dataset of cams transactions that are excluded from the estimation
**********************************************************************

*use  "${data_main}\commercial\landings_cleaned_${in_string}.dta", replace
use  "${data_main}\commercial\BSB_original_combined_dataset${in_string}.dta", replace

/* to look at omitted transactions, do this:
use  "${data_main}\commercial\BSB_original_combined_dataset${in_string}.dta", replace
keep if mark_in==0

*/
keep if mark_in==1

/* handle factor variables */
/* adjust the market_desc levels */

replace market_desc=6 if market_desc==5
label define market_desc 6 "Unclassified", add
label define market_desc 5 "", modify
label list market_desc

/* decode year and month*/

decode year, gen(myyear)
drop year
rename myyear year
destring year, replace

decode month, gen(mymonth)
drop month
rename mymonth month
destring month, replace

/**********************************************************************************************************************/
/**********************************************************************************************************************/
/************************** Is this the right collapse?************

********************************* */

collapse (sum) value valueR_CPI lndlb livlb weighting, by(camsid hullid mygear record_sail record_land dlr_date dlrid state grade_desc market_desc dateq year month region status)


gen price=value/lndlb

gen priceR_CPI=valueR_CPI/lndlb


bysort dlr_date: egen total=total(lndlb)
replace total=total/1000
label var total "Total landings (000s)"


/* these egens are daily sums. I'm not sure how to put them into the data prep step and then collapse (first might work) , so I will put them after */
/*  market level quantity supplied */
xi, prefix(_S) noomit i.market_desc*lndlb
bysort dlr_date: egen QJumbo=total(_SmarXlndlb_1)
bysort dlr_date: egen QLarge=total(_SmarXlndlb_2)
bysort dlr_date: egen QMedium=total(_SmarXlndlb_3)
bysort dlr_date: egen QSmall=total(_SmarXlndlb_4)
bysort dlr_date: egen QUnc=total(_SmarXlndlb_6)

gen ownQ=_Smarket_de_1*QJumbo +  _Smarket_de_2*QLarge + _Smarket_de_3*QMedium + _Smarket_de_4*QSmall +_Smarket_de_6*QUnc

gen largerQ=0
replace largerQ=0 if market_desc==1
replace largerQ=QJumbo+largerQ if market_desc==2
replace largerQ=QLarge+largerQ if market_desc==3
replace largerQ=QMedium+largerQ if inlist(market_desc,4,6) 

gen smallerQ=0
replace smallerQ=0 if inlist(market_desc,4,6) 
replace smallerQ=QSmall+smallerQ if market_desc==3
replace smallerQ=QMedium+smallerQ if market_desc==2
replace smallerQ=QLarge+smallerQ if market_desc==1
drop _Smarket_de*
mdesc largerQ smallerQ 


summ priceR_CPI, detail



regress priceR_CPI i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc ib(34).state c.total##c.total, noc
est store ols
regress priceR_CPI i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc ib(34).state c.total##c.total [fweight=weighting], noc
est store weightedOLS

reghdfe priceR_CPI i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc c.total##c.total, cluster(dlr_date) absorb(hullid)
est store hullFEs
reghdfe priceR_CPI i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc c.total##c.total [fweight=weighting], cluster(dlr_date) absorb(hullid)
est store weighted_hullFEs





