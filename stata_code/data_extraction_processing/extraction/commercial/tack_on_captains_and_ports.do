do $mobility

global spacepanels_vintage 2023_04_06


use "$data_nameclean/vsh_operator_key_mod.dta", replace
keep permit tripid dbyear portlnd1 state1 geoid operator operator_key_modified
duplicates drop
compress

do $BlackSeaBass

save "$data_raw/commercial/tripid_operator.dta", replace


do $mobility

use "$data_nameclean/jops_operator_clean.dta", replace
keep  operator_key_modified operator_key jops_full de address1 city address_key address2 st zip address_date


do $BlackSeaBass

save "$data_raw/commercial/jops_operator.dta", replace
