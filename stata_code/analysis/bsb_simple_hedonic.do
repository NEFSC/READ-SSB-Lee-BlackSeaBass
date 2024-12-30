global in_string 2024_12_20
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
/* there's some suspect records from VA and DE in 2021 to present. Someone is cleaning these up, but I'm not sure who
I will handle the VA using this code
*/



gen questionable_status=0
replace questionable_status=1 if status=="PZERO" & state=="VA" & inlist(dlr_cflic,"2147","1148") & year>=2021
/* I will handle DE using this code, although I don't think it's right. */
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & price==0
replace questionable_status=1 if  status=="PZERO" & state=="DE" & day==1 & port==80999

drop if questionable_status==1

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
label def market_category 1 "Jumbo" 2 "Large" 3 "Medium" 4 "Small" 5 "Extra Small" 6 "Unclassified"

rename market_desc market_desc_string
encode market_desc_string, gen(market_desc) label(market_category) 

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




/* For dealer records with no federal permit number (permit = '000000'), the CAMSID is built as PERMIT, HULLID, dealer partner id, dealer link, and dealer date with the format PERMIT_HULLID_PARTNER_LINK_YYMMDD000000
do these camsids really correspond to a single "trip" or are they just state aggregated data?
*/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/************************** Is this the right collapse?************

1. I need to move anything data processing code on the "by()" to a point before the collapse .





********************************* */

collapse (sum) value lndlb livlb, by(camsid hullid mygear record_sail record_land dlr_date dlrid state grade_desc market_desc dateq year month area status)


gen price=value/lndlb





/* merge deflators _merge=1 has been the current month */ 
merge m:1 dateq using "$data_external/deflatorsQ_${in_string}.dta", keep(1 3)
assert year==2024 & month>=9 if _merge==1
drop if _merge==1
drop _merge

gen priceR_CPI=price/fCPIAUCSL_2023Q1
notes priceR_CPI: real price in 2023Q1 CPIU adjusted dollars

clonevar weighting=lndlb


replace lndlb=lndlb/1000
label var lndlb "landings 000s"

label var year "Year"
label var month "Month"

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

gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(state, 99,12,23,33,42,45) /* no canada, florida, maine, nh, pa, sc*/

*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)
label var total "Total"




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





