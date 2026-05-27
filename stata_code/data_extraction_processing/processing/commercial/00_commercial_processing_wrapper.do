global in_string 2026_05_01
do "$processing_code/commercial/A01_make_landings_cleaned.do"
do "$processing_code/commercial/A02_make_daily_stats.do"

do "$processing_code/commercial/A03_make_dealer_stats.do"
do "$processing_code/commercial/A04_make_moving_average_prices.do"

