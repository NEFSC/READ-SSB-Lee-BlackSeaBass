/* This is a file that produces a dataset that contains #of fish encountered per trip.
This is a port of Scott's "domain_catch_frequencies_gom_cod_wave_2013.sas"



This is a template program for estimating catch frequecies
using the MRIP public-use datasets.

The program is setup to use information in the trip_yyyyw
dataset to define custom domains.  The catch frequencies are
estimated within the domains by merging the trip information
onto the catch_yyyyw datasets.

Required input datasets:
 trip_yyyyw
 catch_yyyyw

yyyy = year
w    = wave


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
merge 1:m year strat_id psu_id id_code using `cl1', keep(1 3) nogenerate


keep if year==$working_year
/* THIS IS THE END OF THE DATA MERGING CODE */



/*This is the "full" mrip data */
tempfile tc1
save `tc1'

gen str3 area_s="ALL"

 /* classify trips that I care about into the things I care about (caught or targeted cod/haddock) and things I don't care about "ZZZZZZZZ" */
 replace prim1_common=subinstr(lower(prim1_common)," ","",.)
replace prim2_common=subinstr(lower(prim1_common)," ","",.)

gen common_dom="zzz"
replace common_dom="BSB" if strmatch(common, "`my_common1'") 
tostring wave, gen(w2)

destring month, gen(mymo)
drop month
tostring mymo, gen(month)
drop mymo
gen my_dom_id_string=area_s +"_"+ month+"_"+common_dom


/* we need to retain 1 observation for each strat_id, psu_id, and id_code.  */
/* A.  Trip (Targeted or Caught) (Cod or Haddock) then it should be marked in the domain "_ATLCO"
	1. Caught my_common.  We retain tot_cat
	2. Did not catch my_common.  We set tot_cat=0
   B.  Trip did not (Target or Caught) (Cod or Haddock) then it is marked in the the domain "ZZZZZ"
	1. Caught my_common.  This is impossible.
	2. Did not catch my_common.  We set tot_cat=0
	
To do this:
1.  We set tot_cat, landing, claim, harvest, and release to zero for all instances of common~="my_common"
2.  We set a variable "no_dup"=0 if the record is "my_common" catch and no_dup=1 otherwise.
3.  We sort on year, strat_id, psu_id, id_code, "no_dup", and "my_dom_id_string".
  For records with duplicate year, strat_id, psu_id, and id_codes, the first entry will be "my_common catch" if it exists.  These will all be have sp_dom "ATLCO."  If there is no my_common catch, but the 
  trip targeted (cod or haddock) or caught cod, the secondary sorting on "my_dom_id_string" ensures the trip is properly classified as an (A2 from above).
4. After sorting, we generate a count variable (count_obs1 from 1....n) and we keep only the "first" observations within each "year, strat_id, psu_id, and id_codes" group.
*/


/*
1  Set tot_cat, landing, claim, harvest, and release to zero for all instances of common~="my_common"
2.  We set a variable "no_dup"=0 if the record is "$my_common" catch and no_dup=1 otherwise.*/

 gen no_dup=0
 replace no_dup=1 if strmatch(common, "$my_common")==0
 	replace tot_cat=0 if strmatch(common, "$my_common")==0
	replace landing=0 if strmatch(common, "$my_common")==0
	replace claim=0 if strmatch(common, "$my_common")==0
	replace harvest=0 if strmatch(common, "$my_common")==0
	replace release=0 if strmatch(common, "$my_common")==0

*catch frequency adjustments for grouped catch (multiple angler catches reported on a single record);
replace claim=claim/cntrbtrs if cntrbtrs>0 
 

/*3.  We sort on year, strat_id, psu_id, id_code, "no_dup", and "my_dom_id_string".
4. After sorting, we generate a count variable (count_obs1 from 1....n) and we keep only the "first" observations within each "year, strat_id, psu_id, and id_codes" group.*/

bysort year strat_id psu_id id_code (no_dup my_dom_id_string): gen count_obs1=_n
keep if count_obs1==1

/*
As suggested by John Foster (MRIP), catch-per-trip at the angler level can be computed by:
	1) dividing claim by cntrbtrs (done above already). Note that when there is group claim and multiple interviews for a single fishing party, 
	   only the leader will have positive value for claim, non-leaders will have zero claim. 
	2) summing harvest and release by (strat_id,psu_id, leader)
	3) dividing harvest and release by the count of id_codes within a leader 
	4) multiplying wp_int by the count of id_codes within a leader to create new_wp_int
	5) Once new_wp_ints are computed, keep only the first observation within each strat_id psu_id leader
	6) Add claim to new_harvest and new_release to get new_tot_cat
	7) specify the new_wp_ints in the svy command and use new_tot_cat as the catch variable

	Note that in some cases, the number of anglers contributing to a claim is different than the number of 
	anglers in the fishing party. This creates a divergence in estimated total harvest using the raw data versus using the 
	adjusted data because we multiply the wp_ints by the total number of anglers interviewed, not by the number of anglers 
	contributing to total claim. Subsequqntly, there will be small differences in total catch between the original and adjusted wp_ints and catch values.
	John Foster recommend re-scaling the new_wp_ints by the ratio of original total catch/adjusted total catch if having 
	adjusted total catch=original total catch is desired
*/
*2) 
 foreach var of varlist harvest release{
	egen sum_`var'=sum(`var'), by(strat_id psu_id leader)
}

*3) 
gen tab=1
egen count_id_codes=sum(tab), by(strat_id psu_id leader)
drop tab 

foreach var of varlist sum_harvest sum_release{
	gen new_`var'=`var'/count_id_codes
}

*4) 
gen new_wp_int=wp_int*count_id_codes

*5) 
cap drop first
bysort strat_id psu_id leader: gen first=1 if _n==1
keep if first==1

*6) 
replace tot_cat=claim+new_sum_harvest+new_sum_release
*get integer values of catch:



  foreach var of varlist tot_cat landing claim harvest release{
	replace `var'=round(`var')
 }




*7) 
sort year strat_id psu_id id_code
svyset psu_id [pweight= new_wp_int], strata(var_id) singleunit(certainty)

 
local myv tot_cat

	svy: tab `myv' my_dom_id_string, count
	/*save some stuff  
	matrix of proportions, row names, column names, estimate of total population size*/
	mat eP=e(Prop)
	mat eR=e(Row)'
	mat eC=e(Col)
	local PopN=e(N_pop)

	local mycolnames: colnames(eC)
	mat colnames eP=`mycolnames'
	
	clear
	/*read the eP into a dataset and convert proportion of population into numbers*/
	svmat eP, names(col)
	foreach var of varlist *{
		replace `var'=`var'*`PopN'
	}
	/*read in the "row" */
	svmat eR
	order eR
	rename eR `myv'
	
	
	
	
	keep `myv' ALL*
	drop *_z*

	gen year=$working_year

	foreach var of varlist ALL*{
	tokenize `var', parse("_")
	rename `var' `1'`3'
	}


	
	reshape long ALL, i(tot_cat) j(month)
	rename ALL count
	sort year month tot_cat
	order year month tot_cat

	
	save "$my_outputdir/${my_common}_catch_class_${working_year}.dta", replace

