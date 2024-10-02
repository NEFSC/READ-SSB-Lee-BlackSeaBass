/* This is just a little helper file that calls all the monthly files and stacks the data into single datasets 
It also aggregates everything into the proper format for the recreational bioeconomic model 
It's quite awesome.



Running survey commands on multiple years takes a very long time. 

In order to do a data update, you will need to:

1. run the copy_over_raw_mrip.do to copy and convert the sas7bdat files to dta. 

2. Run get_ma_allocation to get Recreation sites for MA (NORTH SOUTH) and 

3. Change the working year to the most recent year.

	CHECK for missing waves in the "ab1_lengths", catch totals, catch frequencies.
	

	Because there are relatively few observations in FY2020, we decided to use the annual length-frequency distribution. 
	However, we will want to do catch per trip at either the wave or month level.
 */
#delimit cr
	global my_projdir "V:/READ-SSB-Lee-MRIP-BLAST"
	global mrip_estim_pub_2018 "A:/products/mrip_estim/Public_data_cal2018"

global my_datadir "${my_projdir}/data_folder"
global data_raw "${workdir}/raw"


global workdir "C:\Users\min-yang.lee\Desktop\BSB"
global my_outputdir "${workdir}\data_folder\main"
global my_codedir "${workdir}\stata_code"

global process_list 2022 

/*  */


/*Set up the catchlist, triplist, and b2list global macros. These hold the filenames that are needed to figure out the catch, length-frequency, trips, and other things.*/




/********************************************************************************/
/********************************************************************************/
/* loop over calendar years */
/********************************************************************************/
/********************************************************************************/
foreach yr of global process_list {
	global working_year `yr'
	global previous_year=$working_year-1


global wavelist 1 2 3 4 5 6
global species1 "blackseabass"
/*this is dumb, but I'm too lazy to replace everything that referred to these local/globals */



/*catchlist -- this assembles then names of files that are needed in the catchlist */
/*Check to see if the file exists */	/* If the file exists, add the filename to the list if there are observations */


global catchlist: dir "${data_raw}" files "catch_$working_year*.dta" 
global triplist: dir "${data_raw}" files "trip_$working_year*.dta" 
global b2list: dir "${data_raw}" files "size_b2_$working_year*.dta" 
global sizelist: dir "${data_raw}" files "size_$working_year*.dta" 

/*
foreach sp in blackseabass{
	global my_common `sp'

	do "${workdir}/domain_catch_frequencies_gom_month.do"
}

*/

global my_common $species1

/* catch totals  -- these are done for all 3 years at once */

do "${my_codedir}/domain_bsb_monthly_catch_totals.do"


/* caught/targeted cod or haddock by wave */

do "${my_codedir}/bsb_directed_trips_by_month_mode.do"



}


