**********************************************************************
* Purpose: 	code to estimate simple  hedonic models. There is some code to try some mixed linear models, but I didn't go too far down that road.
* Inputs:
*   - landings_cleaned_$date.dta (from wrappers)
*
* Outputs:
*   -  hedonic models by ols and classification models by mlogit 
*   - omitted_transactions.dta a dataset of cams transactions that are excluded from the estimation
**********************************************************************

use  "${data_main}\commercial\landings_cleaned_${in_string}.dta", replace

/**********************************************************************************************************************/
/**********************************************************************************************************************/
/************************** Is this the right collapse?************

********************************* */

collapse (sum) value valueR_CPI lndlb livlb weighting, by(camsid hullid mygear record_sail record_land dlr_date dlrid state grade_desc market_desc dateq year month area status)


gen price=value/lndlb

gen priceR_CPI=valueR_CPI/lndlb

gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(state, 99,12,23,33,42,45) /* no canada, florida, maine, nh, pa, sc*/

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
mdesc largerQ smallerQ 


summ priceR, detail


preserve

keep if keep==0
save "${data_main}\commercial\omitted_transactions${in_string}.dta", replace

restore

keep if keep==1

regress priceR i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc ib(34).state c.total##c.total, noc
est store ols
regress priceR i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc ib(34).state c.total##c.total [fweight=weighting], noc
est store weightedOLS

reghdfe priceR i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc c.total##c.total, cluster(dlr_date) absorb(hullid)
est store hullFEs
reghdfe priceR i.year i.month ibn.market_desc ib(freq).mygear ib(freq).grade_desc c.total##c.total [fweight=weighting], cluster(dlr_date) absorb(hullid)
est store weighted_hullFEs




/*  market level quantity supplied */
xi, prefix(_G) noomit i.grade_desc*lndlb
bysort dlr_date: egen QLive=total(_GgraXlndlb_1)
bysort dlr_date: egen QRound=total(_GgraXlndlb_2)
drop _Ggra*



/*  gear level quantity supplied */
xi, prefix(_GR) noomit i.mygear*lndlb
bysort dlr_date: egen QGill=total(_GRmygXlndlb_1)
bysort dlr_date: egen QLine=total(_GRmygXlndlb_2)
bysort dlr_date: egen QMisc=total(_GRmygXlndlb_3)
bysort dlr_date: egen QPot=total(_GRmygXlndlb_4)
bysort dlr_date: egen QTrawl=total(_GRmygXlndlb_5)


drop _GRmy*

foreach var of varlist Q*{
	egen m`var'=mean(`var')
	replace `var'=`var'-m`var'
	drop m`var'
}


/*
/* takes a long ass time 
mixed priceR ibn.market_desc#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.year i.state, noc || dlr_date: QJumbo QLarge QMedium QSmall, emonly emiterate(2000)
*/
preserve

keep if year>=2021
/* not quite right, need to recheck the market_desc codes */
constraint define 1 _b[3.market_desc#c.QJumbo]=_b[2bn.market_desc#c.QLarge]
constraint define 2 _b[4.market_desc#c.QJumbo]=_b[2bn.market_desc#c.QMedium]
constraint define 3 _b[7.market_desc#c.QJumbo]=_b[2bn.market_desc#c.QSmall]
constraint define 4 _b[4.market_desc#c.QLarge]=_b[3.market_desc#c.QMedium]
constraint define 5 _b[7.market_desc#c.QLarge]=_b[3.market_desc#c.QSmall]
constraint define 6 _b[7.market_desc#c.QMedium]=_b[4.market_desc#c.QSmall]

/* this converges, but I get wrong signs on alot of the inverse demand effects */

mixed priceR ibn.market_desc#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.state i.month, noc constraint(1 2 3 4 5 6) || dlr_date: QJumbo QLarge QMedium QSmall, 

est store model2

mixed priceR ibn.market_desc#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.state i.month ib(freq).mygear ib(freq).grade_desc , noc constraint(1 2 3 4 5 6) || dlr_date: QJumbo QLarge QMedium QSmall, emonly emiterate(100)
est store model1

restore










gen rec_open=0
replace rec_open=1 if dlr_date>=mdy(5,18,2024) & dlr_date<=mdy(9,3,2024) & state=="MA"

replace rec_open=1 if dlr_date>=mdy(5,20,2023) & dlr_date<=mdy(9,7,2023) & state=="MA"
replace rec_open=1 if dlr_date>=mdy(5,21,2022) & dlr_date<=mdy(9,4,2022) & state=="MA"





*/





