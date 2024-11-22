
graph drop _all
global in_string 2024_11_07
use "${data_raw}\commercial\landings_all_${in_string}.dta", replace
drop if merge_species_codes==1
replace dlr_date=dofc(dlr_date)
format dlr_date %td

gen dateq=qofd(dlr_date)
format dateq %tq


/* how much of the CAMS landings are matched to a trip for black sea bass */

collapse (sum) lndlb , by(year state permit hullid)
replace lndlb=lndlb/1000
keep if inlist(state,"CT","DE", "MA","MD", "NC","NJ", "NY","RI","VA")


drop if inlist(permit,190998,290998,390998,490998)
drop if hullid=="0000000" & permit==0
drop if hullid=="000000" & permit==0
drop if hullid=="FROM_SHORE" 

/*

preserve
keep if state=="DE"
collapse (sum) lndlb, by(permit year state)
reshape wide lndlb, i(year) j(permit)
graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off)

graph export ${exploratory}\permits_DE.png, as(png) width(2000) replace

restore


preserve
keep if state=="DE"
collapse (sum) lndlb, by(hullid year state)
reshape wide lndlb, i(year) j(hullid) string
graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off)

graph export ${exploratory}\hullid_DE.png, as(png) width(2000) replace

restore
*/
levelsof state, local(states)

foreach st of local states{

	preserve
	keep if state=="`st'"
	collapse (sum) lndlb, by(hullid year state)

	drop if inlist(hullid, "PA9999", "NY0000","MD9999", "NJ9999", "NC9999", "NH9999", "MS9999")
	drop if inlist(hullid, "000", "0000","00000", "000000", "0000000", "00000000", "MS9999")
	drop if inlist(hullid, "VA9999", "NY9999","MD9999", "CTD9999", "999999", "Unknown", "UNREGISTER", "RI9999")
	encode hullid, gen(my)

	tsset my year
	tsfill, full
	replace lndlb=0 if lndlb==.
	bysort my: egen tl=total(lndlb)
	bysort year (tl): gen r=_N-_n+1

	keep if r<=25
	drop hullid state tl r
	reshape wide lndlb, i(year) j(my) 
	graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off) title("`st' landings by hullid") ytitle("landings 000s")

	graph export ${exploratory}\hullid_`st'.png, as(png) width(2000) replace

	restore

	preserve
	keep if state=="`st'"
	collapse (sum) lndlb, by(permit year state)
	drop if inlist(permit,0)
	tsset permit year
	tsfill, full
	replace lndlb=0 if lndlb==.
	bysort permit: egen tl=total(lndlb)
	bysort year (tl): gen r=_N-_n+1

	keep if r<=25
	drop  state tl r
	reshape wide lndlb, i(year) j(permit) 
	graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off) title("`st' landings by permit") ytitle("landings 000s")

	graph export ${exploratory}\permit_`st'.png, as(png) width(2000) replace

	restore


}
/*  Grand  */

	preserve
	collapse (sum) lndlb, by(hullid year)

	drop if inlist(hullid, "PA9999", "NY0000","MD9999", "NJ9999", "NC9999", "NH9999", "MS9999")
	drop if inlist(hullid, "000", "0000","00000", "000000", "0000000", "00000000", "MS9999")
	drop if inlist(hullid, "VA9999", "NY9999","MD9999", "CTD9999", "999999", "Unknown", "UNREGISTER", "RI9999")
	encode hullid, gen(my)

	tsset my year
	tsfill, full
	replace lndlb=0 if lndlb==.
	bysort my: egen tl=total(lndlb)
	bysort year (tl): gen r=_N-_n+1

	keep if r<=25
	drop hullid tl r
	decode my, gen(subhull)
	drop my
	reshape wide lndlb, i(year) j(subhull) string
	graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off) title("Top 25 landings by hullid") ytitle("landings 000s")

	graph export ${exploratory}\hullid_coastwide.png, as(png) width(2000) replace

	restore

	preserve
	collapse (sum) lndlb, by(permit year)
	drop if inlist(permit,0)
	tsset permit year
	tsfill, full
	replace lndlb=0 if lndlb==.
	bysort permit: egen tl=total(lndlb)
	bysort year (tl): gen r=_N-_n+1

	keep if r<=25
	drop  tl r
	reshape wide lndlb, i(year) j(permit) 
	graph bar (asis) lndlb*, stack over(year,label(angle(45))) legend(off) title("Top 25  landings by permit") ytitle("landings 000s")

	graph export ${exploratory}\permit_coastwide.png, as(png) width(2000) replace

	restore










