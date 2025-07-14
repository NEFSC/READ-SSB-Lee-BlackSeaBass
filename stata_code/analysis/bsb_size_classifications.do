/* code to estimate simple classification models */
/*before you can run this, you must run the data extraction and commercial data processing wrappers
*/

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
mdesc largerQ smallerQ 






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
collect export $my_results/FS_avg_lbs.tex, replace tableonly
collect title "Landings per Transaction by year and Market Category"

collect export $my_results/FS_avg_lbs.md, replace

/* And a table of number of obs */
collect style cell, nformat(%8.0gc)
collect title "Number of Observations by year and Market Category \label{FStransactions}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]) (market_desc) (result[N])
collect export $my_results/FS_transactions.tex, replace tableonly

collect title "Number of Observations by year and Market Category"
collect export $my_results/FS_transactions.md, replace
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
collect export $my_results/EST_avg_lbs.tex, replace tableonly

collect title "Landings per Transaction by year and Market Category, Estimation Sample"
collect export $my_results/EST_avg_lbs.md, replace

/* And a table of number of obs */
collect style cell, nformat(%8.0gc)
collect title "Number of Observations by year and Market Category, Estimation Sample \label{ESTtransactions}"

collect layout (year[2018 2019 2020 2021 2022 2023 2024]) (market_desc) (result[N])
collect export $my_results/EST_transactions.tex, replace tableonly

collect title "Number of Observations by year and Market Category, Estimation Sample"
collect export $my_results/EST_transactions.md, replace


/**********************************************************************************************************************/
/**********************************************************************************************************************/







/* simple hedonic regression */
collect create hedonic, replace

regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(44).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
collect get _r_b _r_se e(N), tag(model[Weighted])
est store weighted

regress priceR  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(44).state c.total##c.total i.year i.month if `logical_subset', noc
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
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024)"
collect preview

/* the md version is nice because rmarkdown automatically handles the table being split across rows.*/
collect export $my_results/hedonic_table.md, replace
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024) \label{HedonicTable}"
collect export $my_results/hedonic_table.tex, replace tableonly


/* split the regression into two tables */
collect layout (colname[market_desc mygear grade_desc total total#total]#result result[r2 N]) (model)
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024) \label{HedonicTableA}"
collect export $my_results/hedonic_tableA.tex, replace tableonly

collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024)"
collect export $my_results/hedonic_tableA.md, replace




/* Just print the market category results */
collect layout (colname[market_desc grade_desc]#result result[r2 N]) (model)
collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024) \label{HedonicTableA}"
collect export $my_results/hedonic_table_market_cats.tex, replace tableonly

collect title "Unweighted and Weighted Hedonic Price Regression (2018-2024)"
collect export $my_results/hedonic_table_market_cats.md, replace






collect layout (colname[state year month]#result) (model)
collect style showbase off
collect title "Unweighted and Weighted Hedonic Real Price Regression (2018-2024) \label{HedonicTableB}"
collect export $my_results/hedonic_tableB.tex, replace tableonly

collect title "Unweighted and Weighted Hedonic Real Price Regression (2018-2024)"
collect export $my_results/hedonic_tableB.md, replace 




/* simple hedonic regression */
collect create hedonicNominal, replace


regress price  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(44).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], noc
collect get _r_b _r_se e(N), tag(model[Weighted])
est store NomW

regress price  ibn.market_desc ib(5).mygear ib(1).grade_desc ib(44).state c.total##c.total i.year i.month if `logical_subset', noc
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
collect export $my_results/hedonic_tableNom.tex, replace tableonly

collect title "Unweighted and Weighted Hedonic Nominal Price Regression (2018-2024)"
collect export $my_results/hedonic_tableNom.md, replace


/* split the regression into two tables */
collect layout (colname[market_desc mygear grade_desc total total#total]#result result[r2 N]) (model)
collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024) \label{HedonicTableNomA}"
collect export $my_results/hedonic_tableNomA.tex, replace tableonly

collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024)"
collect export $my_results/hedonic_tableNomA.md, replace 


collect layout (colname[state year month]#result) (model)
collect style showbase off
collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024) \label{HedonicTableNomB}"
collect export $my_results/hedonic_tableNomB.tex, replace tableonly

collect title "Unweighted and Weighted Nominal Hedonic Price Regression (2018-2024)"
collect export $my_results/hedonic_tableNomB.md, replace 

/* when I do this:
reghdfe price ib(4).market_desc ib(5).mygear ib(1).grade_desc ib(44).state c.total##c.total i.year i.month if `logical_subset' [fweight=weighting], absorb(hullid)
the constant terms is the price of small.
*/



/* construct daily totals by market category*/






/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* the classification regression*/
/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* first multinomial logit spec with real prices */
mlogit market_desc priceR_CPI ib(1).month ibn.mygear ib(2018).year ib(44).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(2) noconstant
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
collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitA}"
collect export $my_results/mlogitA.tex, replace tableonly


collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitA.md, replace 



collect layout (colname[state year _cons o._cons]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitB}"
collect export $my_results/mlogitB.tex, replace tableonly

collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitB.md, replace 





/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* Use nominal prices */
/**********************************************************************************************************************/
/**********************************************************************************************************************/
mlogit market_desc price ib(1).month ibn.mygear ib(2018).year ib(44).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(2) noconstant
est store class2

est save "$my_results/class2.ster", replace


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



collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitNomA}"
collect export $my_results/mlogitNomA.tex, replace tableonly



collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitNomA.md, replace 


collect layout (colname[state year]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitNomB}"
collect export $my_results/mlogitNomB.tex, replace tableonly




collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitNomB.md, replace 



collect layout (colname[price mygear]#result) (coleq) 
collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitNom_short.md, replace 













/**********************************************************************************************************************/
/**********************************************************************************************************************/
/* Use centered, nominal prices */
/**********************************************************************************************************************/
/**********************************************************************************************************************/


egen tl=total(weighting*_est_class2)
egen tv=total(value*_est_class2)
gen mean_price=tv/tl
gen price_centered=price-mean_price

mlogit market_desc price_centered ib(1).month ibn.mygear ib(2018).year ib(44).state  [fweight=weighting] if market_desc<=4 & `logical_subset', rrr  baseoutcome(2) noconstant
est store class3


collect create classification3, replace
est restore class3

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

collect layout (colname[price_centered mygear month _cons o._cons]#result) (coleq) 




collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitNomACentered}"
collect export $my_results/mlogitNomA_centered.tex, replace tableonly


collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitNomA_centered.md, replace 


collect layout (colname[state year]#result) (coleq) 

/*
collect layout (result[r2_p N])
collect style cell result[N], nformat(%12.0fc)
*/
collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category\label{mlogitNomBCentered}"
collect export $my_results/mlogitNomB_centered.tex, replace tableonly


collect title "Relative Risk Ratios after Multinomial Logistic Regression to Predict the Market Category"
collect export $my_results/mlogitNomB_centered.md, replace 
















/* I'll flip the order of market categories, so the ordering is
Small, Medium, Large, Jumbo.  Combined with setting the base to "small" in the mixed logit, this shoudl help interpretation.

I'm less happy about the ordered logit. 
1. I want to set the base category in the multinomial to something in the "middle" (Large).  This makes the coefficients easier to interpret.2
2. This makes it hard to compare the ordered logit coefficients to the multinomial coefficients
3. It's more restrictive, which would be good if I had fewer data points. But I'm not 100% sold on the advantages, give the number of observations.

*/
gen order=4-market_desc

ologit order price ib(1).month ib(5).mygear ib(2018).year ib(44).state  [fweight=weighting] if market_desc<=4 & `logical_subset', or
est store ologit_nominal

ologit order priceR ib(1).month ib(5).mygear ib(2018).year ib(44).state [fweight=weighting] if market_desc<=4 & `logical_subset', or
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


collect title "Ordered Logistic"
collect export $my_results/OrderedLogit.md, replace




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








local logical_subset keep==1 & year>=2018 & price>.15
keep if `logical_subset' & market_desc<=4
compress

mlogit market_desc price_centered ib(1).month ibn.mygear ib(2018).year ib(44).state  [fweight=weighting], baseoutcome(2) noconstant




gen insample= market_desc<=4 & keep==1 & year>=2018 & price>.15
assert insampl==1

save "$data_main\commercial\mlogit_estimation_dataset_${vintage_string}.dta"


