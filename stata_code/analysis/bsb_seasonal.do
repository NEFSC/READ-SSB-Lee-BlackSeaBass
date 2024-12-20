/* state patterns of landings */
global in_string 2024_12_20

use  "${data_main}\commercial\weekly_landings_${in_string}.dta", replace

graph box landings, over(week)


xtline landings

/* I can exclude CN, FL, ME, NH, NK, PA, and SC */

gen keep=1
replace keep=0 if inlist(state, "CN", "FL", "ME", "NH", "NK", "PA", "SC")
drop if keep==0


xtline landings if keep==1

/* very seasonal, especially in MA and RI*/


/* there's been a big growth in CT and RI in percentage terms, but these have been contributing minimal amounts of landings */
tsline landings if state=="CT"
tsline landings if state=="RI"


/* the landings have quite a bit of seasonality.  Southern landings are higher in Fall, Winter, Spring.   

Northern landings are higher in Summer/Fall
These are two good examples. MA (North) and NJ (South) look similar.


*/ 
graph box landings if state=="MD" , over(week,label(angle(45)))
graph box landings if state=="RI" , over(week,label(angle(45)))