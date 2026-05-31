# Taxi Zone Staging

`experiments/runners/demo.sh prepare-data` downloads the NYC TLC Taxi Zone
lookup into this directory and creates the RisingWave-compatible CSV beside it.

The generated CSV files are local runtime inputs and are ignored by Git. Run
`bash experiments/runners/demo.sh cleanup-local` after a demo to remove them.
