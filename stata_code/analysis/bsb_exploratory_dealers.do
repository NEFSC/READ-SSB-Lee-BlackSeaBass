
graph drop _all
global in_string 2024_12_20
use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq





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



/* encode grade */
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



collapse (sum) lndlb, by(dlrid year market_desc)
rename market_desc mym




rename dlrid dnum 
merge m:1 dnum year using  "${data_raw}\commercial\dealers_annual_${in_string}.dta", keep (1 3)
rename dnum dlrid
drop _merge



reshape wide lndlb, i(year dlrid) j(mym)
foreach var of varlist lndlb*{
	replace `var'=0 if `var'==.
}

egen total=rowtotal(lndlb1-lndlb6)

gen unclassified_frac=lndlb6/total
order unclassified_frac
bysort year: egen t6=total(lndlb6)
bysort year: egen tt=total(total)
gen yearly_unc=t6/tt
order yearly_un
gsort year -unclassified_frac
browse if unclassified_frac>yearly_unc & year>=2010
sort dlrid year


gen f6=lndlb6/t6




order year dlrid dlr_name yearly_unc unclassified_frac lndlb6 f6 t6
bysort year (f6): gen frank=_N-_n+1
browse if year>=2010 & frank<=5
order frank
gsort year frank

browse if year>=2010 & frank<=5
/* the biggest fraction of the unclassifieds (30-60%) is coming in with dlrid=0 

Status of the matching record between CFDERS and VTR: 
MATCH = records fully match at the CAMSID-ITIS_GROUP1 level; 
DLR_ORPHAN_SPECIES = matching CAMSID (trip) but the ITIS_GROUP1 in CFDERS does not appear on the VTR; 
DLR_ORPHAN_TRIP = dealer trip with no matching VTR trip; 
VTR_ORPHAN_SPECIES = matching CAMSID (trip) but the ITIS_GROUP1 on the VTR does not appear on the CFDERS trip (these records were previously excluded from AA tables); 
VTR_ORPHAN_TRIP = VTR trip with no matching trip in CFDERS (these records were previously excluded from AA tables); 
VTR_NOT_SOLD = VTR records kept for bait-home-consumption and therefore not sold to the dealer and not in CFDERS (these records were previously excluded from AA tables); 
PZERO = Records where PERMIT = '000000'. These are not included in the apportionment or imputation processes.


I don't even understand how these get into the dealer databases  (if we don't know the dealer, who is doing the reporting?)

CFDERS_ALL_YEARS has a CF_License (Commercial fisherman license issued by a State)  and a state_dnum (State Dealer License Number) field. These are interesting. Do I "need" anything? or can I make do with these as dummies?

*/


use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td
gen dateq=qofd(dlr_date)
format dateq %tq

replace market_desc="UNCLASSIFIED" if market_desc=="MIXED OR UNSIZED"
replace market_code="UN" if market_code=="MX"
replace market_desc="MEDIUM" if market_desc=="MEDIUM OR SELECT"
/* the PEE WEE (RATS) looks a little odd. */
replace market_desc="EXTRA SMALL" if market_desc=="PEE WEE (RATS)"
replace market_code="ES" if market_code=="PW"
label def market_category 1 "JUMBO" 2 "LARGE" 3 "MEDIUM" 4 "SMALL" 5 "EXTRA SMALL" 6 "UNCLASSIFIED" 7 "PEE WEE (RATS)"
encode market_desc, gen(mym) label(market_category) 
replace grade_desc="LIVE" if grade_desc=="LIVE (MOLLUSCS SHELL ON)"
label def grade_category 2 "LIVE" 1 "ROUND" 3 "UNGRADED"
collapse (sum) lndlb, by(year mym status)
browse if mym==6




