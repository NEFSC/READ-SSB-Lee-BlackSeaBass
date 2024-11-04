global in_string 2024_10_18
use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq

collapse (sum) value lndlb livlb, by(camsid hullid negear record_sail record_land dlr_date market_code grade_code dlrid state grade_desc market_desc dateq year month)


gen price=value/lndlb





/* merge deflators _merge=1 has been the current month */ 
merge m:1 dateq using "$data_external/deflatorsQ_${in_string}.dta", keep(1 3)
assert year==2024 & month>=9 if _merge==1
drop if _merge==1
drop _merge

gen priceR_CPI=price/fCPIAUCSL_2023Q1
notes priceR_CPI: real price in 2023Q1 CPIU adjusted dollars


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


replace market_desc="EXTRA SMALL" if market_desc=="PEE WEE (RATS)"
replace market_code="ES" if market_code=="PW"

label def market_category 1 "JUMBO" 2 "LARGE" 3 "MEDIUM OR SELECT" 4 "SMALL" 5 "EXTRA SMALL" 6 "UNCLASSIFIED"

encode market_desc, gen(mym) label(market_category) 
encode grade_desc, gen(mygrade)
encode state, gen(mys)
rename mygear mygear_string
encode mygear_string, gen(mygear)

gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(market_code, "ES","MX", "PW")
replace keep=0 if inlist(state, "CN","FL","ME", "NH","PA","SC")
replace keep=0 if inlist(grade_desc,"UNGRADED")

*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)
replace total=total/1000




summ priceR, detail


preserve

keep if keep==0
save "${data_main}\commercial\omitted_transactions${in_string}.dta", replace

restore

keep if keep==1



regress priceR i.year i.month ibn.mym ib(freq).mygear ib(freq).mygrade ib(freq).mys c.total##c.total, noc
est store ols
regress priceR i.year i.month ibn.mym ib(freq).mygear ib(freq).mygrade ib(freq).mys c.total##c.total [fweight=lndlb], noc
est store weightedOLS

reghdfe priceR i.year i.month ibn.mym ib(freq).mygear ib(freq).mygrade c.total##c.total, cluster(dlr_date) absorb(hullid)
est store hullFEs
reghdfe priceR i.year i.month ibn.mym ib(freq).mygear ib(freq).mygrade c.total##c.total [fweight=lndlb], cluster(dlr_date) absorb(hullid)
est store weighted_hullFEs



/*  market level quantity supplied */
xi, prefix(_S) noomit i.mym*lndlb
bysort dlr_date: egen QJumbo=total(_SmymXlndlb_1)
bysort dlr_date: egen QLarge=total(_SmymXlndlb_2)
bysort dlr_date: egen QMedium=total(_SmymXlndlb_3)
bysort dlr_date: egen QSmall=total(_SmymXlndlb_4)
drop _Smym*



/*  market level quantity supplied */
xi, prefix(_G) noomit i.mygrade*lndlb
bysort dlr_date: egen QLive=total(_GmygXlndlb_1)
bysort dlr_date: egen QRound=total(_GmygXlndlb_2)
drop _Gmyg*



/*  gear level quantity supplied */
xi, prefix(_GR) noomit i.mygear*lndlb
bysort dlr_date: egen QGill=total(_GRmygXlndlb_1)
bysort dlr_date: egen QLine=total(_GRmygXlndlb_2)
bysort dlr_date: egen QMisc=total(_GRmygXlndlb_3)
bysort dlr_date: egen QPot=total(_GRmygXlndlb_4)
bysort dlr_date: egen QTrawl=total(_GRmygXlndlb_5)


drop _GRmy*



foreach var of varlist Q*{
	replace `var'=`var'/1000
}


foreach var of varlist Q*{
	egen m`var'=mean(`var')
	replace `var'=`var'-m`var'
	drop m`var'
}



/*
/* takes a long ass time 
mixed priceR ibn.mym#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.year i.mys, noc || dlr_date: QJumbo QLarge QMedium QSmall, emonly emiterate(2000)
*/
preserve

keep if year>=2021

constraint define 1 _b[3.mym#c.QJumbo]=_b[2bn.mym#c.QLarge]
constraint define 2 _b[4.mym#c.QJumbo]=_b[2bn.mym#c.QMedium]
constraint define 3 _b[7.mym#c.QJumbo]=_b[2bn.mym#c.QSmall]
constraint define 4 _b[4.mym#c.QLarge]=_b[3.mym#c.QMedium]
constraint define 5 _b[7.mym#c.QLarge]=_b[3.mym#c.QSmall]
constraint define 6 _b[7.mym#c.QMedium]=_b[4.mym#c.QSmall]

/* this converges, but I get wrong signs on alot of the inverse demand effects */

mixed priceR ibn.mym#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.mys i.month, noc constraint(1 2 3 4 5 6) || dlr_date: QJumbo QLarge QMedium QSmall, 

est store model2

mixed priceR ibn.mym#(c.QJumbo c.QLarge c.QMedium c.QSmall) i.mys i.month ib(freq).mygear ib(freq).mygrade , noc constraint(1 2 3 4 5 6) || dlr_date: QJumbo QLarge QMedium QSmall, emonly emiterate(100)
est store model1

restore










gen rec_open=0
replace rec_open=1 if dlr_date>=mdy(5,18,2024) & dlr_date<=mdy(9,3,2024) & state=="MA"

replace rec_open=1 if dlr_date>=mdy(5,20,2023) & dlr_date<=mdy(9,7,2023) & state=="MA"
replace rec_open=1 if dlr_date>=mdy(5,21,2022) & dlr_date<=mdy(9,4,2022) & state=="MA"





*/





