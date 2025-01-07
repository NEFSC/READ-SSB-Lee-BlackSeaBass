/* code to estimate experiment with finite mixture smodels */
/*before you can run this, you must run the data extraction and commercial data processing wrappers
*/
global in_string 2024_12_20
use  "${data_main}\commercial\landings_cleaned_${in_string}.dta", replace




/* For dealer records with no federal permit number (permit = '000000'), the CAMSID is built as PERMIT, HULLID, dealer partner id, dealer link, and dealer date with the format PERMIT_HULLID_PARTNER_LINK_YYMMDD000000
do these camsids really correspond to a single "trip" or are they just state aggregated data?
*/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/************************** Is this the right collapse?************

Aggregating to stockarea drops out a few observations.


********************************* */
collapse (sum) value valueR_CPI lndlb livlb weighting, by(camsid hullid mygear record_sail record_land dlr_date dlrid state grade_desc market_desc dateq year month stockarea status)


gen price=value/lndlb
gen priceR_CPI=valueR_CPI/lndlb




gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(state, 99,12,23,33,42,45) /* no canada, florida, maine, nh, pa, sc*/
replace keep=0 if price>=15

*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)
label var total "Total"












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

/**********************************************************************************************************************/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* what do I want to estimate on? */
/* Nominal prices that are between $0.15 and $15lb.
North Carolina to Mass

*/
keep if keep==1 & year>=2018 & price>.15





/* simple hedonic regression */
regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib1.stockarea ib(34).state c.total##c.total i.year i.month  [fweight=weighting], noc
est store weighted


/* simple hedonic regression on Jumbos and Larges*/
regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib1.stockarea ib(34).state c.total##c.total i.year i.month  [fweight=weighting] if market_desc<=2, noc
est store JandL


regress priceR  ibn.market_desc  i.year i.month  [fweight=weighting] if market_desc<=2, noc



/*an FMM on just the Jumbos and Larges. This isn a bad model because there's nothing in the 'class'  equation*/
fmm 2 if market_desc<=2,  emopts(iterate(40)): regress priceR i.year i.month  [fweight=weighting] , noconstant 


/*an FMM on just the Larges and Mediums, with just state and year in the class equation*/

fmm 2 if inlist(market_desc,2,3), lcprob(i.state i.year)   emopts(iterate(200)): regress priceR i.year i.month QJumbo QLarge QMedium [fweight=weighting]

est store fmm2
predict cl, classpr
replace cl=. if _est_fmm2==0
summ cl
graph box cl if _est_fmm2, over(market_desc)
twoway (kdensity cl if market_desc==2) (kdensity cl if market_desc==3)




