# Start background logger
r_user <- system("whoami", intern = TRUE)
perf_log_file <- here("R_code", "analysis", "fit_random_forest","perf_usage.log")
system(
  paste0(
    "bash -c 'while true; do ",
    "CPU=$(top -bn2 -d0.5 | grep Cpu | tail -1 | awk \"{print \\$2+\\$4}\"); ",
    "MEM=$(ps -u ", r_user, " --no-headers -o rss | awk \"{sum+=\\$1} END {print sum/1024}\"); ",
    "echo \"$(date +%H:%M:%S) CPU: ${CPU}% MEM: ${MEM}MB\"; ",
    "sleep 30; done' > ", perf_log_file, " 2>&1 &"
  )
)
message("Performance logger started for user: ", r_user, ", writing to: ", perf_log_file)

