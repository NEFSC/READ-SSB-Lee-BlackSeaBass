**********************************************************************
* Purpose: 	code to do my make the dealer aggregate statistics.
* Inputs:
*   - landings_cleaned_$date.dta 


* Outputs:

*   - dlrid_historical_stats_ : Dealer historical (2010-2014) used for target encoding
*   - dlrid_last_year: Dealer historical (2010-2014) used for target encoding

**********************************************************************



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
	rename lndlb`l' DealerHLbsPurchased`l'
	
	replace TransactionCount`l'=0 if TransactionCount`l'==.
	label var TransactionCount`l'  "Dealer level number of transactions from 2010-2014 in market category `l' "

	
}

egen totalland=rowtotal(DealerHLbsPurchased*)
egen totaltrans=rowtotal(TransactionCount*)



local sizes Jumbo Large Medium Small Unclassified
foreach l of local sizes{
	gen Share2014`l'=DealerHLbsPurchased`l'/totalland
	label var Share2014`l' "Dealer Share of pounds from 2010-2014 in market category `l'"
	gen Frac2014T`l'=TransactionCount`l'/totaltrans
	label var Frac2014T`l' "Dealer Fraction of total transactions from 2010-2014 in market category `l'"

}
drop totalland totaltrans

order dlrid DealerHLbsPurchased* TransactionCount* Share2014* Frac2014T*

compress

notes: pounds landed and fraction pound landed of bsb 
save "${data_main}\commercial\dlrid_historical_stats_${vintage_string}.dta", replace








/* Previous Year landings */

use "${data_main}\commercial\landings_cleaned_${vintage_string}.dta", replace
keep if year>=2014

bysort dlrid camsid market_desc: gen TransactionCount=_n==1
/* sum by dlr and market category */
collapse (sum) lndlb TransactionCount, by(dlrid market_desc year)
decode market_desc, gen(mymarket)

keep lndlb dlrid mymarket TransactionCount year
/* reshape and zero fill */

bysort dlrid year: egen TotalPounds=total(lndlb)
bysort dlrid year: egen TotalTrans=total(TransactionCount)
gen LagSharePounds=lndlb/TotalPounds
gen LagShareTrans=TransactionCount/TotalTrans
keep year dlrid mymarket LagSharePounds LagShareTrans lndlb TransactionCount

rename lndlb LagPounds
rename TransactionCount LagTrans
/* lag my statistics */
replace year=year+1

reshape wide LagSharePound LagShareTrans LagPounds LagTrans, i(dlrid year) j(mymarket) string

/* zero fill if there are missings here. This means a dealer never purchased one of the market categories  */
foreach var of varlist LagSharePound* LagShareTrans* LagPounds* LagTrans* {
	replace `var'=0 if `var'==.
}
tsset dlrid year
/* do not zero fill here. missing values mean the dealer didn't buy anything in the previous year */
tsfill, full

notes: merge this on dlrid and year to get 1 year lags of the share of Pounds into the estimation dataset
save "${data_main}\commercial\dlrid_lag_stats_${vintage_string}.dta", replace


























