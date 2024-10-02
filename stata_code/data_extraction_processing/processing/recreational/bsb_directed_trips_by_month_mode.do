/* This is a file that produces data on a, b1, b2, and other top-level catch statistics by wave

This is a port of Scott's sas code "codhaddirectedtripsbywave2011,2012, 2013.
THIS PRODUCES the number of trips that 
A. Caught cod
B. Caught haddock
C. Targeted cod
D. Targeted haddock



This is a template program for estimating directed trips
using the MRIP public-use datasets.

The program is setup to use trip_yyyyw datasets to define
custom domains and estimate total angler-trips within domains.
Catch information can be used in defining the domains by 
merging the catch_yyyyw datasets onto the trip_yyyyw datasets.

Required input dataset:
 trip_yyyyw
Optional input dataset:
 catch_yyyyw

yyyy = year
w    = wave


*/

version 12.1
pause on
/* General strategy 
COMPUTE totals and std deviations for cod catch

 */
 clear


local my_common1 $species1

local waves_used $wavelist 


tempfile tl1 cl1

foreach file in $triplist{
	append using ${data_raw}/`file'
}
/* *dtrip will be used to estimate total directed trips, do not change it*/
capture drop $drop_conditional

gen dtrip=1

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






keep if strmatch(common, "`my_common1'")
save `cl1'

use `tl1'
merge 1:m year strat_id psu_id id_code using `cl1', keep(1 3)
replace common=subinstr(lower(common)," ","",.)
replace prim1_common=subinstr(lower(prim1_common)," ","",.)
replace prim2_common=subinstr(lower(prim2_common)," ","",.)

drop _merge
 
/* THIS IS THE END OF THE DATA MERGING CODE */



/*This is the "full" mrip data */
tempfile tc1
save `tc1'



/*classify into (A)ll  */
gen str3 area_s="A"

 
format st_res %02.0f
format cnty_res %03.0f
tostring st_res cnty_res, replace usedisplayformat
gen stco=st_res+cnty_res
 
 
 
 /* classify trips into dom_id=1 (DOMAIN OF INTEREST) and dom_id=2 ('OTHER' DOMAIN). */
gen str1 dom_id="2"
replace dom_id="1" if strmatch(common, "`my_common1'") 
replace dom_id="1" if strmatch(prim1_common, "`my_common1'") 

tostring wave, gen(w2)
tostring year, gen(year2)




/*Deal with Group Catch -- this bit of code generates a flag for each year-strat_id psu_id leader. (equal to the lowest of the dom_id)
Then it generates a flag for claim equal to the largest claim.  
Then it re-classifies the trip into dom_id=1 if that trip had catch of species in dom_id1  */

replace claim=0 if claim==.
replace var_id=strat_id if strmatch(var_id,"")

bysort strat_id psu_id leader (dom_id): gen gc_flag=dom_id[1]
bysort strat_id psu_id leader (claim): gen claim_flag=claim[_N]
replace dom_id="1" if strmatch(dom_id,"2") & claim_flag>0 & claim_flag!=. & strmatch(gc_flag,"1")
gen my_dom_id_string=year2+"_"+stco+"_"+ month+"_"+dom_id

replace my_dom_id_string=ltrim(rtrim(my_dom_id_string))
/*convert this string to a number */
encode my_dom_id_string, gen(my_dom_id)

/* keep 1 observation per year-strat-psu-id_code. This will have dom_id=1 if it targeted or caught my_common1 . Else it will be dom_id=2*/
bysort year wave strat_id psu_id id_code (dom_id): gen count_obs1=_n

keep if count_obs1==1



replace wp_int=0 if wp_int<=0
svyset psu_id [pweight= wp_int], strata(var_id) singleunit(certainty)

sort  my_dom_id  year strat_id psu_id id_code

gen my_dom_id_string2=year2+"_"+month+"_"+dom_id
encode my_dom_id_string2, gen(my_dom_id2)


save "${my_outputdir}/trips_dataset.dta", replace


preserve
local myvariables dtrip
local i=1
/* total with over(<overvar>) requires a numeric variable */

foreach var of local myvariables{
	svy: total `var', over(my_dom_id2)
	
	mat b`i'=e(b)'
	mat colnames b`i'=`var'
	mat V=e(V)
	mat sub`i'=vecdiag(V)'
	mat colnames sub`i'=variance

	local ++i 
}
local --i
sort my_dom_id2 year 
duplicates drop my_dom_id2, force
keep my_dom_id2 year stco month dom_id

foreach j of numlist 1/`i'{
	svmat b`j', names(col)
	svmat sub`j', names(col)

}
keep if strmatch(dom_id,"1")==1
format dtrip %10.0fc
decode my_dom_id2, gen(my_dom_id_string2)
drop my_dom_id2
rename my_dom_id_string2 my_dom_id2



save "${my_outputdir}/`my_common1'_target_stco_${working_year}.dta", replace

restore
