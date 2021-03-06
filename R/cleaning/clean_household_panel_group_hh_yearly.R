#' Author: John Bonney & Santiago Lacouture
#'
#' Clean the Nielsen household panel data to create a data set on the
#' consumer-group-year level. Match sales tax to HH by their location. 
#' Divide consumption by taxability of product and by location of store (same 3 digit or not)

library(data.table)
library(futile.logger)
library(readstata13)

setwd("/project2/igaarder/Data/Nielsen/Household_panel")

# # products file is same across years
# products_file <- "HMS/Master_Files/Latest/products.tsv"
# products <- fread(products_file)
# products <- products[, .(upc, upc_ver_uc, product_module_code, product_group_code)]
# 
# for (yr in 2006:2016) {
#   ## necessary filepaths
#   folderpath <- paste0("HMS/", yr, "/Annual_Files/")
#   panelists_file <- paste0(folderpath, "panelists_", yr, ".tsv")
#   purchases_file <- paste0(folderpath, "purchases_", yr, ".tsv")
#   trips_file <- paste0(folderpath, "trips_", yr, ".tsv")
#   store_file <- paste0("/project2/igaarder/Data/Nielsen/stores_", yr, ".dta")
#   store_file2 <- paste0("/project2/igaarder/Data/Nielsen/stores_", yr - 1, ".dta")
# 
#   ## start with purchases data
#   flog.info("Loading in purchases data for %s", yr)
#   purchases <- fread(purchases_file)
#   purchases <- purchases[, .(trip_code_uc, upc, upc_ver_uc, total_price_paid)]
# 
#   ## merge on the products data to get product module codes (and product group codes)
#   flog.info("Merging products data to purchases for %s", yr)
#   purchases <- merge(purchases, products, by = c("upc", "upc_ver_uc"))
# 
#   ## sum expenditures over UPCs to the product module level
#   flog.info("Summing expenditures over UPCs for %s", yr)
#   purchases <- purchases[, list(
#     total_expenditures = sum(total_price_paid)
#   ), by = .(trip_code_uc, product_module_code, product_group_code)]
# 
#   ## merge on the trip data
#   flog.info("Loading in trips data for %s", yr)
#   trips <- fread(trips_file)
#   trips[, purchase_date := as.Date(purchase_date, "%Y-%m-%d")]
#   trips[, month := month(purchase_date)]
#   trips[, year := year(purchase_date)]
#   trips <- trips[, .(trip_code_uc, household_code, store_code_uc, store_zip3,
#                      year, month, panel_year)]
# 
#   flog.info("Merging trips data to purchases for %s", yr)
#   purchases <- merge(purchases, trips, by = "trip_code_uc")
# 
#   ## Collapse by quarter and year (since is total there wont be problem)
#   purchases[, quarter := ceiling(month / 3)]
#   purchases <- purchases[, list(
#     total_expenditures = sum(total_expenditures) , panel_year = max(panel_year)
#   ), by = .(household_code, product_module_code, product_group_code,
#             store_zip3, quarter, year)]
# 
#   ## Keep purchases greater than 0 for efficiency
#   purchases<-purchases[total_expenditures > 0]
# 
# 
#   ## merge on some individual information?
#   flog.info("Loading in panelists data for %s", yr)
#   panelists <- fread(panelists_file)
#   panelists <- panelists[, .(Household_Cd, Panel_Year, Projection_Factor,
#                              Projection_Factor_Magnet, Household_Income,
#                              Fips_State_Cd, Fips_County_Cd, Panelist_ZipCd, Region_Cd)]
#   setnames(panelists,
#            old = c("Household_Cd", "Panel_Year", "Projection_Factor", "Fips_State_Cd", "Fips_County_Cd",
#                    "Projection_Factor_Magnet", "Household_Income", "Panelist_ZipCd", "Region_Cd"),
#            new = c("household_code", "year", "projection_factor", "fips_state_code", "fips_county_code",
#                    "projection_factor_magnet", "household_income", "zip_code", "region_code"))
#   flog.info("Merging panelists data to purchases for %s", yr)
#   purchases <- merge(purchases, panelists, by = c("household_code", "year"), all.x = T)
# 
#   ## For computational efficiency collapse by type of store: same or different 3 zip code
#   # Module X HH X type_of_store X month level
# 
#   # Retrieve 3 digit zip for hh
#   purchases <- purchases[, hh_zip3 := substring(zip_code, 1, 3)]
#   # Compare store and hh
#   purchases <- purchases[, same_3zip_store := (hh_zip3 == store_zip3)]
#   # Collapse
#   purchases <- purchases[, list(
#     total_expenditures = sum(total_expenditures) , panel_year = max(panel_year)
#   ), by = .(household_code, product_module_code, product_group_code, same_3zip_store, zip_code,
#             household_income, projection_factor,projection_factor_magnet, household_income,
#             fips_state_code, fips_county_code, region_code, quarter, year)]
# 
#   ## save the final dataset
#   flog.info("Saving cleaned dataset for panel year %s", yr)
#   output.path <- paste0("cleaning/purchases_q_", yr, ".csv")
#   fwrite(purchases, output.path)
# 
# }

## collapse expenditures to the quarter level and link all these annual files
purchases.full <- data.table(NULL)
for (yr in 2006:2016) {

  annual.path <- paste0("cleaning/purchases_q_", yr, ".csv")
  purchase.yr <- fread(annual.path)

  ## attach
  flog.info("Appending %s data to master file", yr)
  purchases.full <- rbind(purchases.full, purchase.yr)

}
## Retrieve household info for purchases in the last quarter of previous year but same panel_year
household.cols <- c("fips_county_code", "fips_state_code", "zip_code", "projection_factor", 
                    "projection_factor_magnet", "region_code", "household_income")
purchases.full[, (household.cols) := lapply(.SD, as.numeric), 
               .SDcols = household.cols][,(household.cols) := lapply(.SD, mean, na.rm = T),
                                         by = .(household_code, year), .SDcols = household.cols] 
# Collapse to the year
purchases.full[, N := 1]
purchases.full <- purchases.full[, list(
  total_expenditures = sum(total_expenditures),
  N = sum(N)
), by = .(household_code, product_module_code, product_group_code, projection_factor, projection_factor_magnet,
          household_income, fips_county_code, fips_state_code, zip_code, same_3zip_store, 
          region_code, year) ]
# keep only observations observed during the full year (note there could be observations observed 5 times)
purchases.full <- purchases.full[N>=4]

## Calculate total expenditure per consumer in each year (across stores and modules)
purchases.full[, sum_total_exp := sum(total_expenditures),
               by = .(household_code, year)]

## Keep households that project the national data (projection factor)
purchases.full <- purchases.full[!is.na(projection_factor)]

## Keep only best selling modules
best_selling_modules <- fread("/project2/igaarder/Data/best_selling_modules.csv")
keep_modules <- unique(best_selling_modules[, .(Module)][[1]])
purchases.full <- purchases.full[product_module_code %in% keep_modules]
rm(keep_modules)
rm(best_selling_modules)

## reshape to get a hh X module data
purchases.full <- dcast(purchases.full, household_code + product_group_code + fips_county_code + fips_state_code +
                          zip_code + year + projection_factor + projection_factor_magnet + region_code + sum_total_exp +
                          household_income + product_module_code ~ same_3zip_store, fun=sum,
                         value.var = "total_expenditures")
setnames(purchases.full,
         old = c("FALSE", "TRUE", "NA"),
         new = c("expenditures_diff3", "expenditures_same3", "expenditures_unkn3"))

## There is no need to balance panel here for cross-sectional design


## Identify taxability of module: import
taxability_panel <- fread("/project2/igaarder/Data/taxability_state_panel.csv")

setnames(taxability_panel,
         old = c("fips_state"),
         new = c("fips_state_code"))
# Collapse taxability to the year as rounding the mean 
taxability_panel <- taxability_panel[, list(taxability = round(mean(taxability)),
                                            reduced_rate = mean(reduced_rate, na.rm = T)) ,  
                                     by =.(product_module_code, product_group_code, fips_state_code, year)]

# minor definitions for efficiency
taxability_panel <- data.table(taxability_panel, key = c("fips_state_code", "product_module_code", "product_group_code", "year"))
purchases.full <- data.table(purchases.full, key = c("fips_state_code", "product_module_code", "product_group_code", "year"))

purchases.full <- merge(
  purchases.full, taxability_panel, all.x = T
)
rm(taxability_panel)

# Keep only products for which we know the tax rate
purchases.full <- purchases.full[taxability != 2 & !is.na(taxability)]


## merge on tax rates at household
all_goods_pi_path <- "../../monthly_taxes_county_5zip_2008_2014.csv"
all_pi <- fread(all_goods_pi_path)
setnames(all_pi,
         old = c("fips_state", "fips_county"),
         new = c("fips_state_code", "fips_county_code"))
# Collapse rates to the year as the mean 
all_pi <- all_pi[, list(sales_tax = mean(sales_tax)) , 
                                     by =.(zip_code, fips_county_code,
                                           fips_state_code, year)]
# minor definitions for efficiency
all_pi <- data.table(all_pi, key = c("fips_county_code", "fips_state_code", "zip_code", "year"))
purchases.full <- data.table(purchases.full, key = c("fips_county_code", "fips_state_code", "zip_code", "year"))

purchases.full <- merge(
  purchases.full, all_pi, all.x = T
)
rm(all_pi)

# Impute tax rate to exempt items and to reduced rate items
purchases.full[, sales_tax:= ifelse(taxability == 0 & !is.na(sales_tax), 0, sales_tax)]
purchases.full[, sales_tax:= ifelse(!is.na(reduced_rate) & !is.na(sales_tax), reduced_rate, sales_tax)]

# computing the log tax before collapsing
purchases.full <- purchases.full[, ln_sales_tax := log1p(sales_tax)]


## Collapse to the group:
# Taxability as the mode within the group
# Expenditures as the sum
# Tax as a weighted mean 
# ad-hoc mode function
mode <- function(x) {
  x <- x[!is.na(x)]
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}
# Building weights for tax: sales within group
purchases.full[, sales_weight := sum(expenditures_diff3 + expenditures_same3 + expenditures_unkn3)
               , by =.(year, product_group_code, product_module_code)]
purchases.full[, sales_weight := mean(sales_weight) , by =.(product_group_code, product_module_code)]
purchases.full[, sales_weight := sales_weight/sum(sales_weight) , by =.(product_group_code)]
purchases.full <- purchases.full[, list(
  expenditures_diff3 = sum(expenditures_diff3),
  expenditures_same3 = sum(expenditures_same3),
  expenditures_unkn3 = sum(expenditures_unkn3),
  taxability = mode(taxability),
  ln_sales_tax = weighted.mean(ln_sales_tax, sales_weight)
), by = .(household_code, fips_county_code, fips_state_code, product_group_code,
          zip_code, region_code, year, sum_total_exp, projection_factor,
          projection_factor_magnet, household_income) ]

## Create interest variables
purchases.full <- purchases.full[, expenditures := expenditures_diff3 + expenditures_same3 + expenditures_unkn3]

## Share
purchases.full[, share_expenditures := expenditures/sum_total_exp]

## Logarithms
# Expenditures
purchases.full <- purchases.full[, ln_expenditures := log(expenditures)]
purchases.full$ln_expenditures[is.infinite(purchases.full$ln_expenditures)] <- NA

purchases.full[, ln_expenditures_taxable := ifelse(taxability == 1, ln_expenditures, NA)]
purchases.full[, ln_expenditures_non_taxable := ifelse(taxability == 0, ln_expenditures, NA)]

# Share
purchases.full <- purchases.full[, ln_share := log(share_expenditures)]
purchases.full$ln_share[is.infinite(purchases.full$ln_share)] <- NA

purchases.full[, ln_share_taxable := ifelse(taxability == 1, ln_share, NA)]
purchases.full[, ln_share_non_taxable := ifelse(taxability == 0, ln_share, NA)]

fwrite(purchases.full, "cleaning/consumer_panel_y_hh_group_2006-2016.csv")