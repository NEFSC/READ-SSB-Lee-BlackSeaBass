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

/* F&R for all mygrade to grade_desc */



/* For dealer records with no federal permit number (permit = '000000'), the CAMSID is built as PERMIT, HULLID, dealer partner id, dealer link, and dealer date with the format PERMIT_HULLID_PARTNER_LINK_YYMMDD000000
do these camsids really correspond to a single "trip" or are they just state aggregated data?
*/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/************************** Is this the right collapse?************

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

/* this is not right unclassified never gets filled in.*/ 
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
replace keep=0 if price>=15

*replace keep=0 if inlist(market_desc,"UNCLASSIFIED")
bysort dlr_date: egen total=total(lndlb)
label var total "Total"

/**********************************************************************************************************************/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* what do I want to estimate on? */
/* Nominal prices that are between $0.15 and $15lb.
North Carolina to Mass

*/
local logical_subset keep==1 & year>=2018 & price>.15








/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* make a table of average lbs and std dev */
collect clear

collect create summary_means, replace
sort year market_desc
collect: by year market_desc: summ weighting
collect dims
collect style cell, nformat(%5.1f)
collect title "Landings per Transaction by year and Market Category \label{FSavglbs}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]#result[mean sd]) (market_desc)

collect export $my_results/FS_avg_lbs.md, replace
collect export $my_results/FS_avg_lbs.tex, replace tableonly

/* And a table of number of obs */
collect style cell, nformat(%8.0gc)
collect title "Number of Observations by year and Market Category \label{FStransactions}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]) (market_desc) (result[N])

collect export $my_results/FS_transactions.md, replace
collect export $my_results/FS_transactions.tex, replace tableonly
/**********************************************************************************************************************/
/**********************************************************************************************************************/

/**********************************************************************************************************************/
/********************Same tables, but just on the data that I will estimate on******************************************/
/* make a table of average lbs and std dev */
collect clear

collect create trimmed_sample, replace
collect: by year market_desc: summ weighting
collect dims
collect style cell, nformat(%5.1f)
collect title "Landings per Transaction by year and Market Category, Estimation Sample \label{ESTavglbs}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]#result[mean sd]) (market_desc)

collect export $my_results/EST_avg_lbs.md, replace
collect export $my_results/EST_avg_lbs.tex, replace tableonly

/* And a table of number of obs */
collect style cell, nformat(%8.0gc)
collect title "Number of Observations by year and Market Category, Estimation Sample \label{ESTtransactions}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]) (market_desc) (result[N])
collect export $my_results/EST_transactions.md, replace
collect export $my_results/EST_transactions.tex, replace tableonly

/**********************************************************************************************************************/
/**********************************************************************************************************************/







/* simple hedonic regression */
collect create hedonic, replace

regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
collect get _r_b _r_se e(N), tag(model[Weighted])
est store weighted

regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset', noc
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
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024) \label{HedonicTable}"
collect preview

/* the md version is nice because rmarkdown automatically handles the table being split across rows.*/
collect export $my_results/hedonic_table.md, replace
collect export $my_results/hedonic_table.tex, replace tableonly

/* split the regression into two tables */
collect layout (colname[market_desc mygear grade_desc total total#total]#result result[r2 N]) (model)
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024) \label{HedonicTableA}"
collect export $my_results/hedonic_tableA.tex, replace tableonly

collect layout (colname[state year month]#result) (model)
collect style showbase off
collect title "Unweighted and Weighted Hedonic Real Price Regression (2018-2024) \label{HedonicTableB}"
collect export $my_results/hedonic_tableB.tex, replace tableonly





/* simple hedonic regression */
collect create hedonicNominal, replace


regress price  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
collect get _r_b _r_se e(N), tag(model[Weighted])
est store NomW

regress price  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset', noc
collect get _r_b _r_se e(N), tag(model[Unweighted])
est store NomU


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
collect title "Unweighted and Weighted Hedonic Nominal Price Regression (2018-2024) \label{HedonicTableNom}"
collect preview

/* the md version is nice because rmarkdown automatically handles the table being split across rows.*/
collect export $my_results/hedonic_tableNom.md, replace
collect export $my_results/hedonic_tableNom.tex, replace tableonly

/* split the regression into two tables */
collect layout (colname[market_desc mygear grade_desc total total#total]#result result[r2 N]) (model)
collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024) \label{HedonicTableNomA}"
collect export $my_results/hedonic_tableNomA.tex, replace tableonly

collect layout (colname[state year month]#result) (model)
collect style showbase off
collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024) \label{HedonicTableNomB}"
collect export $my_results/hedonic_tableNomB.tex, replace tableonly


/* when I do this:
reghdfe price ib(4).market_desc ib(5).mygear ib(1).grade_desc ib(34).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], absorb(hullid)
the constant terms is the price of small.
*/



/* construct daily totals by market category*/






/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* the classification regression*/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* first multinomial logit spec */
mlogit market_desc price ib(1).month ib(5).mygear ib(2018).year ib(34).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(4)
predict pr*

est store class1


collect create classification, replace
est restore class1

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



collect layout (colname[priceR_CPI mygear month _cons o._cons]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitA}"
collect export $my_results/mlogitA.tex, replace tableonly


collect layout (colname[state year]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitB}"
collect export $my_results/mlogitB.tex, replace tableonly






/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* Use nominal instead of real prices */
/**********************************************************************************************************************/
/**********************************************************************************************************************/

mlogit market_desc priceR ib(1).month ib(5).mygear ib(2018).year ib(34).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(4)
est store class2


collect create classification2, replace
est restore class2

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

collect layout (colname[price mygear month _cons o._cons]#result) (coleq) 




collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitA}"
collect export $my_results/mlogitNomA.tex, replace tableonly


collect layout (colname[state year]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Multinomial Logistic Regression to Predict the Market Category\label{mlogitB}"
collect export $my_results/mlogitNomB.tex, replace tableonly





/* I'll flip the order of market categories, so the ordering is
Small, Medium, Large, Jumbo.  Combined with setting the base to "small" in the mixed logit, this shoudl help interpretation */
gen order=4-market_desc

ologit order price ib(1).month ib(5).mygear ib(2018).year ib(34).state  [fweight=weighting] if market_desc<=4 & `logical_subset', or
est store ologit_nominal

ologit order priceR ib(1).month ib(5).mygear ib(2018).year ib(34).state [fweight=weighting] if market_desc<=4 & `logical_subset', or
est store ologitR



collect create classification3, replace

est restore ologit_nominal
collect get _r_b _r_se e(N), tag(model[(ologitN)])

est restore ologitR
collect get _r_b _r_se e(N), tag(model[(ologitR)])


collect dims
collect style showbase all
collect style cell, nformat(%5.3f)
collect style cell result[N], nformat(%12.0fc)
collect style cell border_block, border(right, pattern(nil))
collect style cell result[_r_se], sformat("(%s)")
collect style header result, level(hide)
collect style column, extraspace(1)

collect layout (colname#result) (model)
collect stars _r_p 0.01 "***" 0.05 "** " 0.1 "* ", attach(_r_b) shownote
collect title "Ordered Logistic \label{Ologit}"
collect preview

collect export $my_results/OrderedLogit.tex, replace tableonly



/* Do I ever have CAMSID's that bring in multiple market categories? Yes.  Since CAMS allocates, I can easily get multiple rows if the a vessels  fished in mutiple areas, or used different gears. 

select * from cams_land where camsid='330339_20240523193000_33033924051408' and itis_tsn='167687';

select * from nefsc_garfo.cfders_all_years where docn in ('0408021415897') and nespp3=335 order by day, nespp4;

select * from nefsc_garfo.trip_reports_catch where imgid in (
select distinct imgid from nefsc_garfo.trip_reports_images where docid='33033924051408') and species_id='BSB' order by dealer_num, imgid;


1. Need to figure out how to contract the CAMS data back down to transactions. Perhaps simply 

*/
bysort camsid dlrid: gen trans=_N
tab trans if year>=2018
browse if trans==15 & year>=2018


/* Do I ever have CAMSIDs that bring in unclassifieds that also bring in other market catgories */



/* what about dealer Fixed Effects? */



/*
fmm 2: regress priceR ib(freq).mygear ib(freq).grade_desc ib(freq).state QJumbo QLarge QMedium QSmall if market_desc==6, emopts(iterate(40))
*/




/* I have 9000 obs where price=0. 90% are 100lbs or less. But there are a handful of 9,000+ landings*/

browse if year>=2019 & market_desc>=5


