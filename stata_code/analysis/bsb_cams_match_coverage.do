
graph drop _all
global in_string 2024_12_13
use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq


/* how much of the CAMS landings are matched to a trip for black sea bass */
gen s2=status=="MATCH"

replace s2=1 if status=="DLR_ORPHAN_SPECIES"



collapse (sum) lndlb , by(year state s2)
bysort year state: egen t=total(lndlb)
tempfile cams_states
save `cams_states'

gen frac=lndlb/t

preserve
keep if s2==1
keep if inlist(state,"CT","DE", "MA","MD", "NC","NJ", "NY","RI","VA")

encode state, gen(mystate)
xtset mystate year
xtline frac if year<=2023, ytitle("Fraction of Landings with STATUS==MATCH_OS")  tlabel(1995(10)2025)
graph export ${exploratory}\cams_match_state.png, as(png) width(2000) replace


restore
collapse (sum) lndlb , by(year s2)

bysort year: egen t=total(lndlb)
gen frac=lndlb/t

preserve
keep if s2==1



tsset year
tsline frac if year<=2023, ytitle("Fraction of Landings with STATUS==MATCH_OS")  tlabel(1995(10)2025)
graph export ${exploratory}\cams_match.png, as(png) width(2000) replace

restore





keep year s2 lndlb

reshape wide lndlb, i(year) j(s2)
rename lndlb0 cams_landings_nomatch
rename lndlb1 cams_landings_match


merge 1:1 year using "${data_main}\commercial\veslog_annual_landings_${in_string}.dta", keep(1 3)
assert _merge==3
drop _merge
compress

foreach var of varlist cams_landings_nomatch cams_landings_match veslog_kept_lbs{
	replace `var'=`var'/1000000
	label variable `var' "M lbs"
}
tsset year

tsline cams_landings_nomatch cams_landings_match veslog_kept_lbs if year<=2023, legend(order(1 "CAMS No Match" 2 "CAMS MATCH_OS" 3 "VTR" ) rows(1) position(6))   tlabel(1995(10)2025) tmtick(##5)

graph export ${exploratory}\cams_veslog_hails.png, as(png) width(2000) replace


use `cams_states', clear

drop t

reshape wide lndlb, i(year state) j(s2)
rename lndlb0 cams_landings_nomatch
rename lndlb1 cams_landings_match



merge 1:1 state year using "${data_main}\commercial\veslog_annual_state_landings_${in_string}.dta", keep(1 3)
keep if inlist(state,"CT","DE", "MA","MD", "NC","NJ", "NY","RI","VA")


foreach var of varlist cams_landings_nomatch cams_landings_match veslog_kept_lbs{
	replace `var'=`var'/1000000
	label variable `var' "M lbs"
}
encode state, gen(mystate)
xtset mystate year
xtline  cams_landings_nomatch cams_landings_match veslog_kept_lbs if year<=2023, legend(order(1 "CAMS No Match" 2 "CAMS MATCH_OS" 3 "VTR" ) rows(1) position(6)) tlabel(1995(10)2025, labsize(small))  lwidth(thick)  tmtick(##5)
graph export ${exploratory}\state_cams_veslog_hails.png, as(png) width(2000) replace

assert _merge==3
drop _merge



levelsof state, local(mystates)
	local j=1

foreach l of local mystates{
	tsline cams_landings_nomatch cams_landings_match veslog_kept_lbs if state=="`l'" & year<=2023, legend(order(1 "CAMS No Match" 2 "CAMS MATCH_OS" 3 "VTR" ) rows(1) position(6)) tlabel(1995(10)2025, labsize(small))  tmtick(##5)  lwidth(thick) name(state`j', replace)
	graph export ${exploratory}\cams_veslog_hails_`l'.png, as(png) width(2000) replace

	local ++ j 
}

/* 
"something" is breaking in DE, NC, and VA in recent years regarding the matching.

We have really good coverage on VA, DE, MD, and NJ in terms of getting nearly all of the commercial landings to match.


*/




