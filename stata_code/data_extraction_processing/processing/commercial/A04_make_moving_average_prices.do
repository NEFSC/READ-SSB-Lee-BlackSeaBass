**********************************************************************
* Purpose: 	code to make the "group wise moving averages of prices"

* We want to create a 'benchmark' price by market category so we can add a "deviation from benchmark" variable to the classification model.

* An easy way to do this is to use "today's price", "yesterdays price", or "recent prices."
* From the hedonic model, there are two complications
	* landed state seems to matter.  Some states just have higher or lower prices
	* law of demand seems to hold -- days with higher landings have lower prices
* the gold standard would be the prices predicted by a demand model at the state-market category level.
	* this would have to fit the data very well, otherwise we would be introducing extra noise.

* Inputs:
*   - landings_cleaned_$date.dta 
* Outputs:
*   - grand_moving_average_prices_$date.dta /*7 day moving average of prices by group. */
**********************************************************************

/*load data and drop out the unclassified */

use  "${data_main}\commercial\landings_cleaned_${vintage_string}.dta", replace 
drop if market_desc_string=="Unclassified"

/* I want to create a subregional aggregation in case there are lots of 'gaps' in the data (no landings by market category in a state) 
These are loosely based on the hedonic model results 
	CT and NY have similar coefficients 
	NC, VA, MD, and DE have similar coefficients. I aggregate in SC.
	
	MA is similar to the southern, but far away geographically. I added NH and ME to MA
	RI and NJ have similar coefficients too.  But there are lots of observations for these states, so we can keep them separate.

*/
gen subregion=state_string
replace subregion="CTNY" if inlist(state_string,"CT","NY")
replace subregion="DELMARVAC" if inlist(state_string,"DE", "MD","VA","NC","SC")
replace subregion="MA_N" if inlist(state_string,"MA","NH","ME")
drop if inlist(state_string,"CN","PA","FL")

preserve

/**********************************************************************************/
/**********************************************************************************/
/* state adjust */
keep if inlist(market_desc_string, "Large","Jumbo","Medium")

collapse (sum) valueR_CPI lndlb, by(year state)

egen tv=total(valueR_CPI), by(year)
egen tl=total(lndlb), by(year)

gen price=valueR_CPI/lndlb

gen pricebar=tv/tl

gen state_adjust=pricebar - price

notes state_adjust: this is the regional average price minus the state average.  Subtract this from the average price to get the average state level price

keep year state state_adjust
keep if year<=2024

compress

tempfile state_adjust
save `state_adjust'




/**********************************************************************************/
/**********************************************************************************/
/* compute a moving average price for each market category (All NER) */
restore
preserve
collapse (sum) valueR_CPI lndlb, by(dlr_date market_desc)
/*balance the panel */
tsset market_desc dlr_date
tsfill, full

/* zero fill  
foreach var of varlist valueR_CPI lndlb{
	replace `var'=0 if `var'==.
}
*/

/* compute moving sums of landings and value */
rangestat (sum) valueR_CPI (sum) lndlb (count) valueR_CPI, interval(dlr_date -14 -1) by(market_desc)

/* compute the moving average price by market category*/
gen ma14price=valueR_CPI_sum/lndlb_sum
keep dlr_date market_desc ma14price
tempfile moving_average_prices
save `moving_average_prices'
restore




preserve
/**********************************************************************************/
/**********************************************************************************/
/* compute subregion level moving average prices by market category */

collapse (sum) valueR_CPI lndlb, by(dlr_date subregion market_desc)
gen price_subreg=valueR_CPI/lndlb

/* tsset cant operate on two ids, so contract it down to 1 */

egen myg=group(subregion market_desc)
tsset myg dlr_date
tsfill, full

bysort myg: fillmissing market_desc, with(any)
bysort myg: fillmissing subregion, with(any)

/* compute moving sums of landings and value */

rangestat (sum) valueR_CPI (sum) lndlb (count) valueR_CPI, interval(dlr_date -14 -1) by(myg)
gen ma14subregionprice=valueR_CPI_sum/lndlb_sum

/* Drop out any moving average prices that have 5 or fewer days of data in 14 */
replace ma14subregionprice=. if valueR_CPI_count<=5
keep dlr_date market_desc subregion ma14subregionprice
tempfile subregionprice
save `subregionprice'



restore















/**********************************************************************************/
/**********************************************************************************/
/* compute state level moving average prices by market category */
collapse (sum) valueR_CPI lndlb, by(dlr_date state subregion market_desc)

/* drop out a handful of states */
drop if inlist(state,12,42,45,23,33)

/* tsset cant operate on two ids, so contract it down to 1 */

egen myg=group(state subregion market_desc)
tsset myg dlr_date
tsfill, full

bysort myg: fillmissing market_desc, with(any)
bysort myg: fillmissing state, with(any)
bysort myg: fillmissing subregion, with(any)

/* compute moving sums of landings and value */

rangestat (sum) valueR_CPI (sum) lndlb (count) valueR_CPI, interval(dlr_date -14 -1) by(myg)
gen ma14stateprice=valueR_CPI_sum/lndlb_sum

/* Drop out any moving average prices that have 5 or fewer days of data in 14 */
replace ma14stateprice=. if valueR_CPI_count<=3
keep dlr_date market_desc state subregion ma14stateprice

/* this is a dataset with 5 columns: date, market category, state, subregion, and the moving average price */




/**********************************************************************************/
/**********************************************************************************/
/* combine all the moving average prices into a single dataset */

/* merge the All-NER moving average price*/

merge m:1 dlr_date market_desc using `moving_average_prices'

assert _merge ==3
drop _merge


/* merge the sub-region moving average price*/

merge m:1 dlr_date subregion market_desc using `subregionprice'
assert _merge ==3
drop _merge


gen year=year(dlr_date)

/* merge the state adjustment */

merge m:1 year state using `state_adjust', keep(1 3)
assert inlist(_merge,1,3)
drop _merge




sort dlr_date subregion state market_desc
drop year



/* A tiny bit of QA */
keep if dlr_date>=mdy(1,1,2017)
keep if dlr_date<mdy(1,1,2025)
tab state market_desc if ma14stateprice==.
tab state market_desc



/* 

There are some days where I don't have a state-price for a market category. 

I always have a regionwide price for a market category.

I also have an annual state level price for each market category. 

For missing data, I will daily regionwide price by an annual state adjustment factor.

imputed small price on day t in state s = regionwide small price on day t + adjustment factor for state s

At the yearly level, compute the markup (over the regionwide price) : 

state adjust == difference between each states Jumbo, Large, and Medium price and the regional Jumbo, Large, and Medium price.
 */


clonevar imp_ma15stateprice=ma14stateprice
replace imp_ma15stateprice=ma14price - state_adjust if imp_ma14stateprice==.


keep dlr_date market_desc state imp_ma14stateprice
reshape wide imp_ma14stateprice, i(dlr_date state) j(market_desc)

rename imp_ma14stateprice1 JumboMA14price
rename imp_ma14stateprice2 LargeMA14price
rename imp_ma14stateprice3 MediumMA14price
rename imp_ma14stateprice4 SmallMA14price

save "${data_main}\commercial\grand_moving_average_prices_${vintage_string}.dta", replace








