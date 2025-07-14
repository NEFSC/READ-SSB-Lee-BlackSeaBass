clear
use "$data_main\commercial\mlogit_estimation_dataset_${in_string}.dta"
est drop _all

est use "$my_results/class2.ster", number(1)
est store class2
/* predict using model 2 */

est replay

predict prob*, pr
foreach var of varlist prob*{
	replace `var'=`var'*(weighting/2204.62)
	rename `var' predicted_mt_`var'
}


collapse (sum) predicted_mt_* weighting , by(market_desc)

rename predicted_mt_prob1 pred_Jumbo
rename predicted_mt_prob2 pred_Large
rename predicted_mt_prob3 pred_Medium
rename predicted_mt_prob4 pred_Small


rename weighting true

drop true
format pred_* %8.0fc

export delimited using "$my_results/mlogit_predictions_raw.csv", replace


preserve
/* compute row frequencies */

foreach var of varlist pred_*{
	tempvar t1
	egen `t1'=total(`var')
	gen colfreq_`var'=`var'/`t1'
	
}
renvars colfreq*, subst("_pred" "")


keep market_desc colfreq*
export delimited using "$my_results/mlogit_predictions_col_freq.csv", replace
restore

tempvar t1
egen `t1'=rowtotal(pred_*)

foreach var of varlist pred_*{
	gen rowfreq_`var'=`var'/`t1'
}
renvars rowfreq_*, subst("_pred" "")

keep market_desc rowfreq_*
export delimited using "$my_results/mlogit_predictions_row_freq.csv", replace
