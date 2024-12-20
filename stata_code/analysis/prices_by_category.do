global vintage_string 2024_12_20

use "${data_main}\commercial\daily_landings_category_${vintage_string}.dta", replace
keep if _merge==3
/* make line and box plots of prices and volumes by grade and market code */

replace dlr_date=dofc(dlr_date)
format dlr_date %td


/* rebin Mixed or unsized to unclassified 
rebin pee wee to extra small */ 

replace market_desc="UNCLASSIFIED" if market_desc=="MIXED OR UNSIZED"
replace market_code="UN" if market_code=="MX"


replace market_desc="EXTRA SMALL" if market_desc=="PEE WEE (RATS)"
replace market_code="ES" if market_code=="PW"

/* this is a silly regression because I have collapsed things to the day already */

label def market_category 1 "JUMBO" 2 "LARGE" 3 "MEDIUM OR SELECT" 4 "SMALL" 5 "EXTRA SMALL" 6 "UNCLASSIFIED"

encode market_desc, gen(mym) label(market_category) 



regress price i.year i.month i.mym

/* */

preserve

collapse (sum) landings value, by(year mym)
tsset mym year
xtline landings
xtline value

restore
/*The important categories are Jumbo, Large, Medium/Select, and Unclassified
Nearly everything is landed and sold whole */

gen keep=1
replace keep=0 if inlist(market_code, "ES","MX", "PW")



preserve
collapse (sum) landings value, by(year mym keep)
tsset mym year
xtline landings if keep==1
xtline value if keep==1
gen price =value/landings
xtline price if keep==1
restore
/* The yearly prices really move together. There are a couple of odd bumps up and down. */
/* 2001 smalls, 2009 unclassified stick out. These could be a timing thing. */


collapse (sum) landings value, by(year week mym keep)
gen weekly_date=yw(year, week)
format weekly_date %tw
gen price=value/landings
tsset my weekly_date
xtline price if keep==1 & price<=10

/* The weekly black sea bass price series looks pretty nicely behaved. 
Something happens in 2020 */


xtline price if price<=10 & inlist(mym, 1,2,3), overlay


 xtline price if price<=10 & inlist(mym,1, 2,3) & year>=2010 & year<=2019, overlay
 
/*just eyeballing it, it looks like something happens in 2016*/
