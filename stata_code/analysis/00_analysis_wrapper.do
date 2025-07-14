global in_string 2024_12_20

/* estimate a simple hedonic model */
do "$analysis_code/bsb_simple_hedonic.do"

/*try an finite mixture model. I didn't really pursue this very much */
do "$analysis_code/fmm_tries.do"

/* moderately complex hedonics plus classification models */
do "$analysis_code/bsb_size_classifications.do"
/* more classification models */

do "$analysis_code/bsb_size_classifications_V2.do"


/* predictions */
do "$analysis_code/mlogit_prediction_sumary.do"
