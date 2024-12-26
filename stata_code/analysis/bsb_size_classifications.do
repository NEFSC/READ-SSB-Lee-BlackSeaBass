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


/**********************************************************************************************************************/
/**********************************************************************************************************************/
collapse (sum) value lndlb livlb, by(camsid hullid mygear record_sail record_land dlr_date market_code grade_code dlrid state grade_desc market_desc dateq year month area status)


gen price=value/lndlb





/* merge deflators _merge=1 has been the current month */ 
merge m:1 dateq using "$data_external/deflatorsQ_${in_string}.dta", keep(1 3)
assert year==2024 & month>=9 if _merge==1
drop if _merge==1
drop _merge

gen priceR_CPI=price/fCPIAUCSL_2023Q1
notes priceR_CPI: real price in 2023Q1 CPIU adjusted dollars


label def market_category 1 "JUMBO" 2 "LARGE" 3 "MEDIUM OR SELECT" 4 "SMALL" 5 "EXTRA SMALL" 6 "UNCLASSIFIED"

encode market_desc, gen(mym) label(market_category) 


replace grade_desc="LIVE" if grade_desc=="LIVE (MOLLUSCS SHELL ON)"

label def grade_category 2 "LIVE" 1 "ROUND" 3 "UNGRADED" 


encode grade_desc, gen(mygrade) label(grade_category) 
encode state, gen(mys)
rename mygear mygear_string
encode mygear_string, gen(mygear)

replace lndlb=lndlb/1000
label var lndlb "landings 000s"




/*  market level quantity supplied */
xi, prefix(_S) noomit i.mym*lndlb
bysort dlr_date: egen QJumbo=total(_SmymXlndlb_1)
bysort dlr_date: egen QLarge=total(_SmymXlndlb_2)
bysort dlr_date: egen QMedium=total(_SmymXlndlb_3)
bysort dlr_date: egen QSmall=total(_SmymXlndlb_4)
drop _Smym*

gen keep=1

/* drop small time market codes, states, grades, market descriptions */
replace keep=0 if inlist(market_code, "ES","MX", "PW")
replace keep=0 if inlist(state, "CN","FL","ME", "NH","PA","SC")
replace keep=0 if inlist(grade_desc,"UNGRADED")
replace keep=0 if price>=15

*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)


/* For dealer records with no federal permit number (permit = '000000'), the CAMSID is built as PERMIT, HULLID, dealer partner id, dealer link, and dealer date with the format PERMIT_HULLID_PARTNER_LINK_YYMMDD000000
do these camsids really correspond to a single "trip" or are they just state aggregated data?
*/


/*
fmm 2: regress priceR ib(freq).mygear ib(freq).mygrade ib(freq).mys QJumbo QLarge QMedium QSmall if mym==6, emopts(iterate(40))
*/

/* simple hedonic regression */

regress price i.year i.month ibn.mym ib(5).mygear ib(2).mygrade ib(10).mys c.total##c.total if keep==1 & year>=2018 & price>.15, noc
est store uw

gen weighting=round(lndlb*1000)

regress priceR i.year i.month ibn.mym ib(5).mygear ib(2).mygrade ib(10).mys c.total##c.total if keep==1 & year>=2018 & price>.15 [fweight=weighting], noc
est store weighted

/* first multinomial logit spec */
mlogit mym priceR i.month ib(5).mygear i.year ib(10).mys if mym<=4 & year>=2018
predict pr*

browse if year>=2019 & mym>=5

/* I have 9000 obs where price=0. 90% are 100lbs or less. But there are a handful of 9,000+ landings*/






