log using $my_results/bsb_size_classificationsV2_${in_string}.smcl, replace

**********************************************************************
* Purpose: 	code to estimate more complex  classification models.
* Inputs:
*   - landings_cleaned_$date.dta (from wrappers)
*
* Outputs:
*   -  hedonic models by ols and classification models by mlogit 

**********************************************************************

/* code to estimate simple classification models */
/*before you can run this, you must run the data extraction and commercial data processing wrappers
*/

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

Aggregating to stockarea drops out a few observations.


********************************* */

collapse (sum) value valueR_CPI lndlb livlb weighting, by(camsid hullid mygear record_sail record_land dlr_date dlrid state grade_desc market_desc dateq year month region stockarea status)


gen price=value/lndlb
gen priceR_CPI=valueR_CPI/lndlb

gen keep=1


*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
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






/**********************************************************************************************************************/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* what do I want to estimate on? */
/* Nominal prices that are between $0.15 and $15lb.
North Carolina to Mass

*/
local logical_subset year>=2013 & price>.15 & price<=12





/* simple hedonic regression */
collect create hedonic, replace

regress priceR_CPI  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
collect get _r_b _r_se e(N), tag(model[Weighted])
est store weighted

regress priceR_CPI  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset', noc
collect get _r_b _r_se e(N), tag(model[Unweighted])
est store uw




collect dims
collect style showbase all
collect style cell, nformat(%5.3f)
collect style cell result[N], nformat(%12.0fc)
collect style cell border_block, border(right, pattern(nil))
collect style cell result[_r_se], sformat("(%s)")
collect style header result, level(hide)
collect style column, extraspace(1)

collect style cell colname[total#total], nformat(%7.5f)
collect style row stack, spacer delimiter(" x ")
collect layout (colname#result result[r2 N]) (model)
collect style header result[r2 N], level(label)
collect label levels result r2 "R-squared", modify
collect stars _r_p 0.01 "***" 0.05 "** " 0.1 "* ", attach(_r_b) shownote
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2025) \label{HedonicTable}"
collect preview

/* I eyeballed the 'base' results and the results when we don't collapse on stockarea. As expected the 'weighted' regression has the same coefficients. The unweighted regressions are slightly different. 

This is because the two weighted regressions are actually identical.
*/ 



/* just adding stockarea to the regression doesn't do much. the north stock gets about $0.04 or 0.05 per lb */
regress priceR_CPI  ibn.market_desc ib(5).mygear ib(1).grade_desc ib1.stockarea ib(5).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
est store simplearea

/* adding interactions of stockarea and state and stockareax month produces some interesting stuff 
gear, total, and year coefficients don't change much.

North stock get $0.64 per lb more than the south stock in Jan in NJ.   In other months the premium is smaller (see the stockarea# month coeffs). NJ (and CT) have the largest positive North effect (stockarea#state), so even though the north coefficient changes alot, the results are quite consistent with the simpler specifiation.

The "month" coefficients are now interpretable as the monthly premium for the south stock.  These are also consistent with the simpler model.
*/
regress priceR_CPI  ibn.market_desc ib(5).mygear ib(1).grade_desc ib1.stockarea##(ib(5).state i.month) c.total##c.total i.year if `logical_subset' [fweight=weighting], noc
est store interacted_area


/* add trip days to the regression */

gen tripdays=hours(record_land-record_sail)/24
gen interact=tripdays~=.
replace tripdays=0 if tripdays==.
regress price (c.tripdays##c.tripdays)#i.interact ibn.market_desc ib(5).mygear ib(1).grade_desc ib1.stockarea##(ib(5).state i.month) c.total##c.total i.year if `logical_subset' [fweight=weighting], noc


/* are there many camsid with different gears? */

bysort camsid mygear: egen tlg=total(lndlb)
bysort camsid (tlg): gen firstgear=mygear[_N]


browse if firstgear~=mygear
count if firstgear~=mygear
order firstgear mygear
label var firstgear "predominant gear"
label values firstgear mygear
order mygear
bysort camsid: gen t=firstgear-mygear
order t
replace t=1 if t~=0
bysort camsid: egen switchers=total(t)
order switchers
tab switchers
browse if switchers>=1
sort camsid
drop t
sort camsid lndlb
order lndlb stockarea dlrid, after(firstgear)
sort camsid firstgear mygear
order market_desc tlg


tempfile base_data
save `base_data', replace


collapse (sum) lndlb, by(state stockarea year)
browse
reshape wide lndlb, i(year state) j(stockarea)
foreach var of varlist lnd* {
	replace `var'=0 if `var'==.
}



decode state, gen(state_string)




levelsof state_string, local(statenames)

foreach l of local statenames{
	preserve
	keep if state_string=="`l'"

	graph bar (asis) lndlb1 lndlb2, stack over(year, label(angle(45))) legend(order(1 "South" 2 "North")) ytitle("000s of lbs") name(Lstate`l', replace) title("Landings by Stock Area in `l'")
	graph export ${exploratory}\state_stockareas_`l'.png, as(png) width(2000) replace
	restore
}

/* The more northern states -- NY, CT, MA, and RI have less than 1% landings from the south. These states have possession limits that make it infeasible to go south and then return north.
VA, MD, NC  are a bit more northern that I expected however this is because those states have high possession limits that can enable 'distant waters' fishing.
DE is the only state that "makes sense", but that is just a few boats and I don't want to read too much into it.*/

use `base_data', clear




/* PZERO is shorthand for no federal permit
	* state only, to either a federal or state dealer 
	* these have to be trips in state waters. 
*/




/* first multinomial logit spec */
mlogit market_desc price ib(1).month ib(5).mygear ib(2018).year ib(5).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(4)
predict pr*

est store class1


collect create classification, replace

mlogit market_desc price ib(1).month ib(5).mygear i.stockarea i4.status [fweight=weighting] if market_desc<=4  & `logical_subset' & year==2022, baseoutcome(4) rrr
collect get _r_b _r_se e(N), tag(model[(Mlogit)])





collect dims
collect style showbase off
collect style cell, nformat(%5.3f)
collect style cell border_block, border(right, pattern(nil))
collect style cell result[_r_se], sformat("(%s)")
collect style header result, level(hide)
collect style column, extraspace(1)
collect style row stack, spacer delimiter(" x ")
collect layout (colname#result ) (coleq)

collect style header result[r2_p N], level(label)
collect label levels result r2_p "R-squared", modify
collect stars _r_p 0.01 "***" 0.05 "** " 0.1 "* ", attach(_r_b) shownote
collect preview



collect layout ( mygear#result month#result colname[price _cons o._cons]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitA}"


collect layout (state#result year#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitB}"






/* a very simple model */
local logical_subset keep==1 & year>=2018 & price>.15

mlogit market_desc price if market_desc<=4  & `logical_subset' & year>=2018, baseoutcome(4) 

est store super_simple


mlogit market_desc price if market_desc<=4  & `logical_subset' & year>=2018 [fweight=weighting] , baseoutcome(4) 
est store simple_weighted


log close
