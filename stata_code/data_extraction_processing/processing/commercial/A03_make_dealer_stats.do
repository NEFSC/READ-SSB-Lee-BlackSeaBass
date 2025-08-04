



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

