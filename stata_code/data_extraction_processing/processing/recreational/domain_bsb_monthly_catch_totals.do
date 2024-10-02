/* This is a file that produces data on a, b1, b2, and other top-level catch statistics by month


This is a port of Scott's sas code

*/
version 12.1

/* General strategy 
COMPUTE totals and std deviations for cod catch

 */
local my_common1 $species1

mata: mata clear
tempfile tl1 cl1
clear

foreach file in $triplist{
	append using ${data_raw}/`file'
}
cap drop $drop_conditional

sort year strat_id psu_id id_code
/*  Deal with new variable names in the transition period  

  */

	capture confirm variable wp_int_chts
	if _rc==0{
		drop wp_int
		rename wp_int_chts wp_int
		else{
		}
}
	capture confirm variable wp_size_chts
	if _rc==0{
		drop wp_size
		rename wp_size_chts wp_size
		else{
		}
}
save `tl1'
clear

foreach file in $catchlist{
	append using ${data_raw}/`file'
}
cap drop $drop_conditional
replace var_id=strat_id if strmatch(var_id,"")
replace wp_catch=wp_int if wp_catch==.
/*  Deal with new variable names in the transition period    */

	capture confirm variable wp_int_chts
	if _rc==0{
		drop wp_int
		rename wp_int_chts wp_int
		else{
		}
}
	capture confirm variable wp_size_chts
	if _rc==0{
		drop wp_size
		rename wp_size_chts wp_size
		else{
		}

}

	capture confirm variable wp_catch_chts
	if _rc==0{
		drop wp_catch
		rename wp_catch_chts wp_catch
		else{
		}

}
sort year strat_id psu_id id_code
replace common=subinstr(lower(common)," ","",.)
save `cl1'
use `tl1'
merge 1:m year strat_id psu_id id_code using `cl1', keep(3)
drop _merge
/*ONLY keep trips for which there was catch>0 */

/* THIS IS THE END OF THE DATA MERGING CODE */
/*This is the "full" mrip data */
tempfile tc1
save `tc1'




/*classify into GOM or GBS */
gen str3 area_s="ALL"


 /* classify catch into the things I care about (common==$mycommon) and things I don't care about "ZZZZZZZZ" */
 gen common_dom="zzzzzz"
 replace common_dom="BSB" if strmatch(common, "`my_common1'") 
 
 
format st_res %02.0f
format cnty_res %03.0f
tostring st_res cnty_res, replace usedisplayformat
gen stco=st_res+cnty_res
 
 
tostring wave, gen(w2)
tostring year, gen(year2)
*gen my_dom_id_string=year2+area_s+"_"+w2+"_"+common_dom
gen my_dom_id_string=year2+"_"+stco+"_"+month+"_"+common_dom

replace my_dom_id_string=ltrim(rtrim(my_dom_id_string))
encode my_dom_id_string, gen(my_dom_id)
replace wp_catch=0 if wp_catch<=0
sort year my_dom_id

/* this gets immediately overwritten with wp_catch as survey weights */
svyset psu_id [pweight= wp_int], strata(strat_id) singleunit(certainty)
/*svyset psu_id [pweight= wp_int], strata(strat_id) singleunit(certainty) */

svyset psu_id [pweight= wp_catch], strata(var_id) singleunit(certainty)

gen my_dom_id_string2=year2+"_"+month+"_"+common_dom
encode my_dom_id_string2, gen(my_dom_id2)


save "$my_outputdir/catch_dataset.dta", replace




 
local myvariables tot_cat claim harvest release
local i=1
/* total with over(<overvar>) requires a numeric variable



 */

foreach var of local myvariables{
	svy: total `var', over(my_dom_id2)
	
	mat b`i'=e(b)'
	mat colnames b`i'=`var'
	mat V=e(V)

	local ++i 
}
local --i
sort year my_dom_id2
duplicates drop my_dom_id2, force
keep my_dom_id year stco month common_dom

foreach j of numlist 1/`i'{
	svmat b`j', names(col)
}

drop if strmatch(common_dom,"zzzzzz")
sort year stco month common_dom



save "$my_outputdir/${my_common}_catch_$working_year.dta", replace


*/
